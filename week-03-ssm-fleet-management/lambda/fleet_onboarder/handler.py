"""
fleet_onboarder — Week 3 SSM Fleet Management
Triggers SSM Automation to onboard an EC2 instance into the managed fleet.
Waits for automation to complete and returns compliance summary.
"""

import os
import json
import time
import boto3

ssm = boto3.client("ssm")

ONBOARD_DOCUMENT = os.environ["ONBOARD_DOCUMENT_NAME"]


def lambda_handler(event, context):
    instance_id         = event["instance_id"]
    ticket_id           = event["ticket_id"]
    automation_role_arn = event["automation_role_arn"]

    print(f"Onboarding instance {instance_id} for ticket {ticket_id}")

    # Start SSM Automation
    resp = ssm.start_automation_execution(
        DocumentName=ONBOARD_DOCUMENT,
        Parameters={
            "InstanceId":          [instance_id],
            "AutomationAssumeRole": [automation_role_arn],
        }
    )

    execution_id = resp["AutomationExecutionId"]
    print(f"Started automation execution: {execution_id}")

    # Poll until complete (max 5 min)
    for _ in range(30):
        time.sleep(10)
        status_resp = ssm.get_automation_execution(
            AutomationExecutionId=execution_id
        )
        status = status_resp["AutomationExecution"]["AutomationExecutionStatus"]
        print(f"Automation status: {status}")

        if status in ("Success", "Failed", "Cancelled", "TimedOut"):
            break

    # Get patch compliance summary
    try:
        compliance = ssm.list_compliance_summaries(
            Filters=[{"Key": "InstanceId", "Values": [instance_id], "Type": "EQUAL"}]
        )
        patch_summary = next(
            (s for s in compliance.get("ComplianceSummaryItems", [])
             if s.get("ComplianceType") == "Patch"),
            {}
        )
    except Exception as e:
        print(f"Could not retrieve compliance: {e}")
        patch_summary = {}

    return {
        "ticket_id":           ticket_id,
        "instance_id":         instance_id,
        "automation_status":   status,
        "execution_id":        execution_id,
        "compliant_count":     patch_summary.get("CompliantSummary", {}).get("CompliantCount", 0),
        "non_compliant_count": patch_summary.get("NonCompliantSummary", {}).get("NonCompliantCount", 0),
        "onboard_success":     status == "Success",
    }
