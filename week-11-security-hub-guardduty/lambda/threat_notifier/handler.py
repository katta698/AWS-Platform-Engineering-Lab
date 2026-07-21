"""Notify (do not auto-mutate) on GuardDuty threat findings.

Triggered by EventBridge on native "GuardDuty Finding" events. Threat findings
(reconnaissance, credential exfiltration, crypto-mining, etc.) are judgement
calls — killing the wrong instance or key mid-incident can be worse than the
threat — so this path deliberately does NOT remediate. It formats the finding
into a readable alert and publishes it to SNS so a human triages it.

An optional severity floor (GUARDDUTY_MIN_SEVERITY) suppresses low-severity
noise. GuardDuty severity is numeric: Low 1.0-3.9, Medium 4.0-6.9, High/Critical
7.0-8.9+.

This complements the CSPM auto-remediators: Security Hub's config findings get
fixed automatically; GuardDuty's active-threat findings get escalated to a
person. Both flow through the same EventBridge/SNS backbone.
"""

import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
MIN_SEVERITY = float(os.environ.get("GUARDDUTY_MIN_SEVERITY", "4.0"))


def _severity_label(score):
    if score >= 7.0:
        return "HIGH/CRITICAL"
    if score >= 4.0:
        return "MEDIUM"
    return "LOW"


def _resource_summary(detail):
    res = detail.get("resource", {})
    rtype = res.get("resourceType", "unknown")
    if rtype == "Instance":
        inst = res.get("instanceDetails", {})
        return f"EC2 instance {inst.get('instanceId', '?')}"
    if rtype == "AccessKey":
        ak = res.get("accessKeyDetails", {})
        return f"IAM principal {ak.get('userName', '?')} ({ak.get('userType', '?')})"
    if rtype == "S3Bucket":
        buckets = res.get("s3BucketDetails", [])
        names = ", ".join(b.get("name", "?") for b in buckets) or "?"
        return f"S3 bucket(s) {names}"
    return f"resource type {rtype}"


def lambda_handler(event, context):
    detail = event.get("detail", {})
    severity = float(detail.get("severity", 0))

    if severity < MIN_SEVERITY:
        logger.info(
            "GuardDuty finding %s severity %.1f below floor %.1f; suppressed",
            detail.get("id"), severity, MIN_SEVERITY,
        )
        return {"suppressed": True, "severity": severity}

    label = _severity_label(severity)
    finding_type = detail.get("type", "unknown")
    region = detail.get("region", event.get("region", "?"))
    account = detail.get("accountId", "?")
    title = detail.get("title", finding_type)
    description = detail.get("description", "")
    resource = _resource_summary(detail)
    count = detail.get("service", {}).get("count", 1)

    message = (
        f"GuardDuty threat finding — {label} (severity {severity})\n\n"
        f"Type:        {finding_type}\n"
        f"Title:       {title}\n"
        f"Resource:    {resource}\n"
        f"Account:     {account}\n"
        f"Region:      {region}\n"
        f"Occurrences: {count}\n\n"
        f"{description}\n\n"
        f"This is an active-threat finding and was NOT auto-remediated — it "
        f"needs human triage. Investigate in the GuardDuty / Security Hub console."
    )
    subject = f"[GuardDuty {label}] {finding_type}"

    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)
    logger.info("Published GuardDuty finding %s (%s) to SNS", detail.get("id"), finding_type)
    return {"notified": True, "type": finding_type, "severity": severity}
