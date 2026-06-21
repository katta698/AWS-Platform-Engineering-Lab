"""
cost_alerter/handler.py

Triggered by SNS when AWS Cost Anomaly Detection fires.
Parses the raw JSON payload, formats a human-readable alert,
and publishes it to the formatted alert SNS topic (email subscribers).

Environment variables:
  ALERT_SNS_TOPIC_ARN  — ARN of the formatted alert SNS topic
  ENVIRONMENT          — deployment environment label (dev / prod)
"""

import json
import os
import boto3

sns = boto3.client("sns")

ALERT_TOPIC_ARN = os.environ["ALERT_SNS_TOPIC_ARN"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")


def lambda_handler(event, context):
    """Entry point — iterates over SNS records (usually just one)."""
    for record in event.get("Records", []):
        raw_message = record["Sns"]["Message"]

        try:
            payload = json.loads(raw_message)
        except json.JSONDecodeError:
            print(f"[ERROR] Could not parse SNS message as JSON: {raw_message[:200]}")
            continue

        subject, body = format_alert(payload)

        response = sns.publish(
            TopicArn=ALERT_TOPIC_ARN,
            Subject=subject[:100],  # SNS subject limit is 100 chars
            Message=body,
        )
        print(f"[OK] Alert published. MessageId={response['MessageId']} | Subject={subject}")

    return {"statusCode": 200}


def format_alert(payload: dict) -> tuple:
    """
    Transforms the raw Cost Anomaly Detection payload into a readable email.

    Payload shape (from AWS docs):
    {
      "accountId": "123456789012",
      "anomalyId": "...",
      "anomalyStartDate": "2026-06-01",
      "anomalyEndDate": "2026-06-11",
      "dimensionValue": "Amazon EC2",
      "impact": {
        "maxImpact": 15.23,
        "totalActualSpend": 25.23,
        "totalExpectedSpend": 10.00,
        "totalImpact": 15.23,
        "totalImpactPercentage": 152.3
      },
      "rootCauses": [
        {
          "linkedAccount": "...",
          "linkedAccountName": "...",
          "region": "us-east-1",
          "service": "Amazon EC2",
          "usageType": "BoxUsage:t3.medium"
        }
      ]
    }
    """
    impact = payload.get("impact", {})
    total_impact = impact.get("totalImpact", 0.0)
    total_actual = impact.get("totalActualSpend", 0.0)
    total_expected = impact.get("totalExpectedSpend", 0.0)
    pct = impact.get("totalImpactPercentage", 0.0)

    dimension = payload.get("dimensionValue", "Unknown Service")
    account_id = payload.get("accountId", "Unknown")
    start_date = payload.get("anomalyStartDate", "Unknown")
    end_date = payload.get("anomalyEndDate", "In progress")
    anomaly_id = payload.get("anomalyId", "N/A")

    root_causes = payload.get("rootCauses", [])
    root_cause_lines = "\n".join(
        "  • Service: {service} | Region: {region} | Usage: {usageType}".format(
            service=rc.get("service", "?"),
            region=rc.get("region", "?"),
            usageType=rc.get("usageType", "?"),
        )
        for rc in root_causes[:5]  # cap to avoid overly long emails
    ) or "  No root cause data available"

    subject = (
        f"[{ENVIRONMENT.upper()}] Cost Anomaly: "
        f"${total_impact:.2f} above expected — {dimension}"
    )

    body = """AWS Cost Anomaly Alert
======================

Environment  : {env}
Account ID   : {account_id}
Service      : {dimension}
Period       : {start_date} → {end_date}

Spend Summary
-------------
  Expected spend : ${total_expected:.2f}
  Actual spend   : ${total_actual:.2f}
  Overage        : ${total_impact:.2f}  (+{pct:.1f}%)

Root Causes (top 5)
-------------------
{root_cause_lines}

Anomaly ID   : {anomaly_id}

Review in AWS Console:
https://console.aws.amazon.com/cost-management/home#/anomaly-detection/monitors

---
Managed by Terraform | Week 05 — Cost Anomaly Detection Lab""".format(
        env=ENVIRONMENT.upper(),
        account_id=account_id,
        dimension=dimension,
        start_date=start_date,
        end_date=end_date,
        total_expected=total_expected,
        total_actual=total_actual,
        total_impact=total_impact,
        pct=pct,
        root_cause_lines=root_cause_lines,
        anomaly_id=anomaly_id,
    )

    return subject, body
