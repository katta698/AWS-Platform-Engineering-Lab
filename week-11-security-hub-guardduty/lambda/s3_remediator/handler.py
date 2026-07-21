"""Auto-remediate publicly accessible S3 buckets flagged by Security Hub.

Triggered by EventBridge on "Security Hub Findings - Imported" events for the
FSBP S3 public-access controls (S3.1 account-level BPA, S3.2/S3.3 bucket public
read/write, S3.8 bucket-level BPA). Remediation applies the four Block Public
Access settings to the offending bucket.

Same guardrail as the SG remediator: the bucket is only changed if it carries
the opt-in tag (default `auto-remediate=true`); otherwise a human is notified
via SNS and the finding is marked NOTIFIED. Outcomes are written back with
BatchUpdateFindings. Failures raise so the async invocation lands in the DLQ.
"""

import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
securityhub = boto3.client("securityhub")
sns = boto3.client("sns")

TAG_KEY = os.environ.get("REMEDIATION_TAG_KEY", "auto-remediate")
TAG_VALUE = os.environ.get("REMEDIATION_TAG_VALUE", "true")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

BPA_CONFIG = {
    "BlockPublicAcls": True,
    "IgnorePublicAcls": True,
    "BlockPublicPolicy": True,
    "RestrictPublicBuckets": True,
}


def _bucket_from_finding(finding):
    for res in finding.get("Resources", []):
        if res.get("Type") == "AwsS3Bucket":
            arn = res.get("Id", "")  # arn:aws:s3:::bucket-name
            if ":::" in arn:
                return arn.split(":::", 1)[1].split("/", 1)[0]
            details = res.get("Details", {}).get("AwsS3Bucket", {})
            if details.get("Name"):
                return details["Name"]
    return None


def _is_opted_in(bucket):
    try:
        tagset = s3.get_bucket_tagging(Bucket=bucket)["TagSet"]
    except s3.exceptions.ClientError as e:
        if "NoSuchTagSet" in str(e):
            return False
        raise
    return any(t["Key"] == TAG_KEY and t["Value"] == TAG_VALUE for t in tagset)


def _apply_bpa(bucket):
    # Idempotent by nature — setting BPA to all-true repeatedly is a no-op.
    s3.put_public_access_block(
        Bucket=bucket, PublicAccessBlockConfiguration=BPA_CONFIG
    )
    logger.info("Applied Block Public Access to bucket %s", bucket)


def _update_finding(finding, status, note):
    securityhub.batch_update_findings(
        FindingIdentifiers=[
            {"Id": finding["Id"], "ProductArn": finding["ProductArn"]}
        ],
        Workflow={"Status": status},
        Note={"Text": note[:512], "UpdatedBy": "s3-remediator-lambda"},
    )


def _notify(subject, message):
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)


def _process(finding):
    control = finding.get("Compliance", {}).get("SecurityControlId", "unknown")
    bucket = _bucket_from_finding(finding)
    if not bucket:
        logger.warning("No S3 bucket in finding %s; skipping", finding.get("Id"))
        return

    if not _is_opted_in(bucket):
        msg = (
            f"Security Hub flagged S3 bucket {bucket} ({control}) as publicly "
            f"accessible, but it is not tagged {TAG_KEY}={TAG_VALUE}, so no "
            f"automatic change was made. Review it manually.\n\n"
            f"Finding: {finding.get('Title')}"
        )
        _notify(f"[REVIEW] Public S3 bucket {bucket} (not auto-remediated)", msg)
        _update_finding(finding, "NOTIFIED", f"Untagged bucket {bucket} — notified for manual review.")
        logger.info("Bucket %s not opted in; notified and marked NOTIFIED", bucket)
        return

    _apply_bpa(bucket)
    note = f"Auto-remediated {control}: applied S3 Block Public Access to {bucket}."
    _update_finding(finding, "RESOLVED", note)
    _notify(
        f"[RESOLVED] Blocked public access on S3 bucket {bucket}",
        f"{note}\n\nFinding: {finding.get('Title')}",
    )
    logger.info(note)


def lambda_handler(event, context):
    findings = event.get("detail", {}).get("findings", [])
    logger.info("Received %d finding(s)", len(findings))
    for finding in findings:
        _process(finding)
    return {"processed": len(findings)}
