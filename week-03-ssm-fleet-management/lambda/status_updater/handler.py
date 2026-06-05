"""
status_updater — Week 3 SSM Fleet Management
Closes ServiceNow ticket with fleet operation results.
Supports both onboarding and patch operation outcomes.
"""

import os
import json
import urllib.request
import urllib.parse
import base64
import boto3

ssm = boto3.client("ssm")


def get_param(name: str) -> str:
    return ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]


def update_servicenow_ticket(ticket_id: str, comment: str, state: str = "3"):
    """Close ServiceNow RITM ticket with comment. State 3 = Closed Complete."""
    instance_url = get_param(os.environ["SNOW_INSTANCE_URL_PARAM"])
    username     = get_param(os.environ["SNOW_USERNAME_PARAM"])
    password     = get_param(os.environ["SNOW_PASSWORD_PARAM"])

    url = f"{instance_url}/api/now/table/sc_req_item"
    query = urllib.parse.urlencode({"sysparm_query": f"number={ticket_id}", "sysparm_limit": "1"})

    # Get the sys_id
    req = urllib.request.Request(f"{url}?{query}")
    credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {credentials}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")

    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())

    records = data.get("result", [])
    if not records:
        print(f"Ticket {ticket_id} not found in ServiceNow")
        return False

    sys_id = records[0]["sys_id"]

    # Update the ticket
    patch_url = f"{instance_url}/api/now/table/sc_req_item/{sys_id}"
    body = json.dumps({
        "state":          state,
        "close_notes":    comment,
        "work_notes":     comment,
    }).encode()

    patch_req = urllib.request.Request(patch_url, data=body, method="PATCH")
    patch_req.add_header("Authorization", f"Basic {credentials}")
    patch_req.add_header("Content-Type", "application/json")
    patch_req.add_header("Accept", "application/json")

    with urllib.request.urlopen(patch_req) as resp:
        result = json.loads(resp.read())

    print(f"Updated ticket {ticket_id}: state={state}")
    return True


def build_onboard_comment(event: dict) -> str:
    status  = "SUCCESS" if event.get("onboard_success") else "FAILED"
    return (
        f"[SSM Fleet Manager - Instance Onboarding {status}]\n\n"
        f"Instance ID: {event.get('instance_id')}\n"
        f"Automation Status: {event.get('automation_status')}\n"
        f"Execution ID: {event.get('execution_id')}\n\n"
        f"Patch Compliance:\n"
        f"  Compliant patches: {event.get('compliant_count', 0)}\n"
        f"  Non-compliant patches: {event.get('non_compliant_count', 0)}\n\n"
        f"Instance is now registered in SSM Fleet Manager.\n"
        f"Access via: AWS Console > Systems Manager > Fleet Manager\n"
        f"Session access: aws ssm start-session --target {event.get('instance_id')}"
    )


def build_patch_comment(event: dict) -> str:
    status  = "SUCCESS" if event.get("patch_success") else "FAILED"
    return (
        f"[SSM Patch Manager - {event.get('operation', 'Patch')} {status}]\n\n"
        f"Patch Group: {event.get('patch_group')}\n"
        f"Operation: {event.get('operation')}\n"
        f"Automation Status: {event.get('automation_status')}\n"
        f"Execution ID: {event.get('execution_id')}\n\n"
        f"Fleet Compliance Summary:\n"
        f"  Total instances: {event.get('total_instances', 0)}\n"
        f"  Compliant: {event.get('compliant', 0)}\n"
        f"  Non-compliant: {event.get('non_compliant', 0)}\n"
        f"  Compliance rate: {event.get('compliance_pct', 0)}%\n\n"
        f"Patch Details:\n"
        f"  Installed: {event.get('installed_patches', 0)}\n"
        f"  Missing: {event.get('missing_patches', 0)}\n"
        f"  Failed: {event.get('failed_patches', 0)}\n\n"
        f"Full report: AWS Console > Systems Manager > Patch Manager > Compliance"
    )


def lambda_handler(event, context):
    ticket_id    = event["ticket_id"]
    request_type = event.get("request_type", "patch")

    if request_type == "onboard":
        comment = build_onboard_comment(event)
        success = event.get("onboard_success", False)
    else:
        comment = build_patch_comment(event)
        success = event.get("patch_success", False)

    snow_state = "3" if success else "4"  # 3=Closed Complete, 4=Closed Incomplete

    try:
        update_servicenow_ticket(ticket_id, comment, snow_state)
        snow_updated = True
    except Exception as e:
        print(f"Failed to update ServiceNow: {e}")
        snow_updated = False

    return {
        "ticket_id":    ticket_id,
        "snow_updated": snow_updated,
        "success":      success,
        "comment":      comment,
    }
