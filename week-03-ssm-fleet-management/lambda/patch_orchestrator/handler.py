"""
patch_orchestrator — Week 3 SSM Fleet Management
Triggers SSM Automation patch-fleet document for Scan or Install.
Collects per-instance compliance results and returns summary.
"""

import os
import json
import time
import boto3

ssm = boto3.client("ssm")

PATCH_DOCUMENT = os.environ["PATCH_FLEET_DOCUMENT_NAME"]


def lambda_handler(event, context):
    patch_group         = event["patch_group"]
    operation           = event.get("operation", "Scan").capitalize()  # normalize: scan→Scan, install→Install
    ticket_id           = event["ticket_id"]
    automation_role_arn = event["automation_role_arn"]

    print(f"Running patch {operation} on group {patch_group} for ticket {ticket_id}")

    # Start SSM Automation
    resp = ssm.start_automation_execution(
        DocumentName=PATCH_DOCUMENT,
        Parameters={
            "Operation":           [operation],
            "PatchGroup":          [patch_group],
            "AutomationAssumeRole": [automation_role_arn],
        }
    )

    execution_id = resp["AutomationExecutionId"]
    print(f"Started automation execution: {execution_id}")

    # Poll until complete (max 10 min for Install)
    max_polls = 60 if operation == "Install" else 30
    for _ in range(max_polls):
        time.sleep(10)
        status_resp = ssm.get_automation_execution(
            AutomationExecutionId=execution_id
        )
        status = status_resp["AutomationExecution"]["AutomationExecutionStatus"]
        print(f"Automation status: {status}")

        if status in ("Success", "Failed", "Cancelled", "TimedOut"):
            break

    # Collect compliance summary for the patch group
    try:
        patch_states = ssm.describe_instance_patch_states_for_patch_group(
            PatchGroup=patch_group
        )
        states = patch_states.get("InstancePatchStates", [])

        total           = len(states)
        compliant       = sum(1 for s in states if s.get("PatchGroup") and s.get("MissingCount", 0) == 0)
        non_compliant   = total - compliant
        total_missing   = sum(s.get("MissingCount", 0) for s in states)
        total_installed = sum(s.get("InstalledCount", 0) for s in states)
        total_failed    = sum(s.get("FailedCount", 0) for s in states)

        compliance_pct = round((compliant / total * 100), 1) if total > 0 else 0

    except Exception as e:
        print(f"Could not retrieve patch states: {e}")
        total = compliant = non_compliant = total_missing = total_installed = total_failed = 0
        compliance_pct = 0

    return {
        "ticket_id":          ticket_id,
        "patch_group":        patch_group,
        "operation":          operation,
        "automation_status":  status,
        "execution_id":       execution_id,
        "total_instances":    total,
        "compliant":          compliant,
        "non_compliant":      non_compliant,
        "missing_patches":    total_missing,
        "installed_patches":  total_installed,
        "failed_patches":     total_failed,
        "compliance_pct":     compliance_pct,
        "patch_success":      status == "Success",
    }
