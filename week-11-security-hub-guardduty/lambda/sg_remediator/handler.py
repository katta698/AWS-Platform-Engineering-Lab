"""Auto-remediate open management-port security groups flagged by Security Hub.

Triggered by EventBridge on "Security Hub Findings - Imported" events for the
FSBP controls that detect unrestricted ingress to high-risk ports (EC2.13 = SSH
22, EC2.14 = RDP 3389, EC2.19 = high-risk ports open to the world).

Guardrail: a security group is only mutated if it carries the opt-in tag
(default `auto-remediate=true`). Anything untagged is left untouched and a
notification is published to SNS instead, so a human still sees it. Every
outcome is written back to the finding via BatchUpdateFindings so Security Hub
reflects reality.

Failures are intentionally raised so the async invocation lands in the DLQ — a
dropped security action is worse than a slow one.
"""

import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
securityhub = boto3.client("securityhub")
sns = boto3.client("sns")

TAG_KEY = os.environ.get("REMEDIATION_TAG_KEY", "auto-remediate")
TAG_VALUE = os.environ.get("REMEDIATION_TAG_VALUE", "true")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
# High-risk ports we revoke world-open ingress for. Overridable via env.
HIGH_RISK_PORTS = {
    int(p) for p in os.environ.get("HIGH_RISK_PORTS", "22,3389").split(",") if p.strip()
}
WORLD_CIDRS = {"0.0.0.0/0"}
WORLD_CIDRS_V6 = {"::/0"}


def _sg_id_from_finding(finding):
    """Pull the security group id out of an ASFF finding's Resources."""
    for res in finding.get("Resources", []):
        if res.get("Type") == "AwsEc2SecurityGroup":
            arn = res.get("Id", "")
            # arn:aws:ec2:<region>:<acct>:security-group/sg-xxxx
            if "security-group/" in arn:
                return arn.rsplit("security-group/", 1)[1]
            details = res.get("Details", {}).get("AwsEc2SecurityGroup", {})
            if details.get("GroupId"):
                return details["GroupId"]
    return None


def _is_opted_in(group_id):
    resp = ec2.describe_security_groups(GroupIds=[group_id])
    tags = resp["SecurityGroups"][0].get("Tags", [])
    return any(t["Key"] == TAG_KEY and t["Value"] == TAG_VALUE for t in tags)


def _covers_high_risk_port(perm):
    """True if this ingress permission spans any high-risk port."""
    ip_proto = perm.get("IpProtocol")
    if ip_proto == "-1":  # all traffic
        return True
    from_port = perm.get("FromPort")
    to_port = perm.get("ToPort")
    if from_port is None or to_port is None:
        return False
    return any(from_port <= port <= to_port for port in HIGH_RISK_PORTS)


def _revoke_world_open_rules(group_id):
    """Revoke only the 0.0.0.0/0 or ::/0 ingress on high-risk ports.

    Surgical: strips just the world-open CIDR from matching permissions, leaving
    any legitimate scoped ingress in place. Idempotent — a rule already gone
    raises InvalidPermission.NotFound, which we treat as success.
    """
    resp = ec2.describe_security_groups(GroupIds=[group_id])
    permissions = resp["SecurityGroups"][0].get("IpPermissions", [])
    revoked = []

    for perm in permissions:
        if not _covers_high_risk_port(perm):
            continue
        world_v4 = [r for r in perm.get("IpRanges", []) if r.get("CidrIp") in WORLD_CIDRS]
        world_v6 = [
            r for r in perm.get("Ipv6Ranges", []) if r.get("CidrIpv6") in WORLD_CIDRS_V6
        ]
        if not world_v4 and not world_v6:
            continue

        revoke_perm = {"IpProtocol": perm["IpProtocol"]}
        if "FromPort" in perm:
            revoke_perm["FromPort"] = perm["FromPort"]
        if "ToPort" in perm:
            revoke_perm["ToPort"] = perm["ToPort"]
        if world_v4:
            revoke_perm["IpRanges"] = world_v4
        if world_v6:
            revoke_perm["Ipv6Ranges"] = world_v6

        try:
            ec2.revoke_security_group_ingress(
                GroupId=group_id, IpPermissions=[revoke_perm]
            )
            revoked.append(revoke_perm)
            logger.info("Revoked world-open ingress on %s: %s", group_id, revoke_perm)
        except ec2.exceptions.ClientError as e:
            if "InvalidPermission.NotFound" in str(e):
                logger.info("Rule already absent on %s (idempotent): %s", group_id, revoke_perm)
            else:
                raise
    return revoked


def _update_finding(finding, status, note):
    securityhub.batch_update_findings(
        FindingIdentifiers=[
            {"Id": finding["Id"], "ProductArn": finding["ProductArn"]}
        ],
        Workflow={"Status": status},
        Note={"Text": note[:512], "UpdatedBy": "sg-remediator-lambda"},
    )


def _notify(subject, message):
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)


def _process(finding):
    control = finding.get("Compliance", {}).get("SecurityControlId", "unknown")
    group_id = _sg_id_from_finding(finding)
    if not group_id:
        logger.warning("No security group id in finding %s; skipping", finding.get("Id"))
        return

    if not _is_opted_in(group_id):
        msg = (
            f"Security Hub flagged security group {group_id} ({control}) for "
            f"unrestricted ingress, but it is not tagged {TAG_KEY}={TAG_VALUE}, "
            f"so no automatic change was made. Review it manually.\n\n"
            f"Finding: {finding.get('Title')}"
        )
        _notify(f"[REVIEW] Open security group {group_id} (not auto-remediated)", msg)
        _update_finding(finding, "NOTIFIED", f"Untagged SG {group_id} — notified for manual review.")
        logger.info("SG %s not opted in; notified and marked NOTIFIED", group_id)
        return

    revoked = _revoke_world_open_rules(group_id)
    note = (
        f"Auto-remediated {control}: revoked {len(revoked)} world-open ingress "
        f"rule(s) on {group_id} for high-risk ports {sorted(HIGH_RISK_PORTS)}."
    )
    _update_finding(finding, "RESOLVED", note)
    _notify(
        f"[RESOLVED] Closed open security group {group_id}",
        f"{note}\n\nFinding: {finding.get('Title')}",
    )
    logger.info(note)


def lambda_handler(event, context):
    findings = event.get("detail", {}).get("findings", [])
    logger.info("Received %d finding(s)", len(findings))
    for finding in findings:
        _process(finding)
    return {"processed": len(findings)}
