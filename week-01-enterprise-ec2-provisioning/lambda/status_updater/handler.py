"""
Lambda: ServiceNow Status Updater
───────────────────────────────────
Triggered by: Step Functions (final state — both success and failure paths)
Purpose:
  1. Write deployment status back to ServiceNow ticket via REST API
  2. Attach ALB DNS, CloudWatch dashboard URL to the ticket
  3. On success: close the ticket (Resolved)
  4. On failure: set ticket to "Failed" with error details

Environment Variables:
  SERVICENOW_INSTANCE_PARAM  - SSM: ServiceNow instance name (e.g., mycompany)
  SERVICENOW_USER_PARAM      - SSM: ServiceNow API username
  SERVICENOW_PASSWORD_PARAM  - SSM: ServiceNow API password (or OAuth token)
"""

import json
import os
import boto3
import logging
import urllib.request
import urllib.error
import base64

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client("ssm")

SERVICENOW_INSTANCE_PARAM = os.environ["SERVICENOW_INSTANCE_PARAM"]
SERVICENOW_USER_PARAM     = os.environ["SERVICENOW_USER_PARAM"]
SERVICENOW_PASSWORD_PARAM = os.environ["SERVICENOW_PASS_PARAM"]

# ServiceNow ticket states
SN_STATE_IN_PROGRESS = "2"
SN_STATE_RESOLVED    = "6"
SN_STATE_CLOSED      = "7"


def get_ssm_param(name: str) -> str:
    return ssm_client.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]


def get_sn_credentials() -> tuple:
    instance = get_ssm_param(SERVICENOW_INSTANCE_PARAM)
    user     = get_ssm_param(SERVICENOW_USER_PARAM)
    password = get_ssm_param(SERVICENOW_PASSWORD_PARAM)
    return instance, user, password


def update_servicenow_ticket(
    instance: str,
    user: str,
    password: str,
    ticket_id: str,
    state: str,
    work_notes: str,
    close_code: str = None
) -> dict:
    """
    Update a ServiceNow RITM (Request Item) via Table API.
    Adjust table name if using sc_task or incident.
    """
    url = f"https://{instance}.service-now.com/api/now/table/sc_req_item/{ticket_id}"

    payload = {
        "state":       state,
        "work_notes":  work_notes,
    }
    if close_code:
        payload["close_code"] = close_code
        payload["close_notes"] = work_notes

    credentials = base64.b64encode(f"{user}:{password}".encode()).decode()
    data = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Basic {credentials}",
            "Content-Type":  "application/json",
            "Accept":        "application/json"
        },
        method="PATCH"
    )

    with urllib.request.urlopen(req, timeout=15) as response:
        result = json.loads(response.read().decode("utf-8"))
        logger.info("ServiceNow update result: %s", result.get("result", {}).get("number"))
        return result


def lambda_handler(event, context):
    """
    Event contains:
      status:          'success' | 'failure'
      ticket_id:       ServiceNow sys_id
      ticket_number:   RITM number (for logging)
      alb_dns_name:    ALB endpoint
      dashboard_url:   CloudWatch dashboard URL
      error:           Error details (on failure)
    """
    logger.info("Status updater event: %s", json.dumps(event, default=str))

    status        = event.get("status", "unknown")
    ticket_id     = event.get("ticket_id", "")
    ticket_number = event.get("ticket_number", "UNKNOWN")

    if not ticket_id:
        logger.warning("No ticket_id provided — skipping ServiceNow update")
        return {"message": "No ticket_id — skipped"}

    try:
        instance, user, password = get_sn_credentials()


        if status == "success":
            alb_dns      = event.get("alb_dns_name", "N/A")
            dashboard    = event.get("dashboard_url", "N/A")
            asg_name     = event.get("asg_name", "N/A")

            work_notes = (
                f"✅ Infrastructure provisioned successfully.\n\n"
                f"**Application Endpoint:** https://{alb_dns}\n"
                f"**CloudWatch Dashboard:** {dashboard}\n"
                f"**Auto Scaling Group:** {asg_name}\n\n"
                f"EC2 instances are healthy and serving traffic.\n"
                f"Deployed by: GitHub Actions (Terraform)"
            )

            update_servicenow_ticket(
                instance, user, password,
                ticket_id=ticket_id,
                state=SN_STATE_RESOLVED,
                work_notes=work_notes,
                close_code="Successful"
            )
            logger.info("Ticket %s resolved successfully", ticket_number)

        else:
            error_detail = event.get("error", "Unknown error during Terraform apply")
            work_notes = (
                f"❌ Infrastructure provisioning FAILED.\n\n"
                f"**Error:** {error_detail}\n\n"
                f"Please review GitHub Actions logs and contact Platform Engineering.\n"
                f"Ticket has been re-opened for investigation."
            )

            update_servicenow_ticket(
                instance, user, password,
                ticket_id=ticket_id,
                state=SN_STATE_IN_PROGRESS,  # Re-open for investigation
                work_notes=work_notes
            )
            logger.error("Ticket %s updated with failure: %s", ticket_number, error_detail)

        return {
            "message": f"ServiceNow ticket {ticket_number} updated",
            "status": status,
            "ticket_id": ticket_id
        }

    except urllib.error.URLError as e:
        # Network unreachable — log and continue so Step Functions is not blocked
        logger.warning("ServiceNow unreachable (network error): %s — skipping update", str(e))
        return {"message": f"ServiceNow update skipped (network error): {str(e)}", "ticket_id": ticket_id}
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        logger.error("ServiceNow API error %d: %s", e.code, error_body)
        return {"message": f"ServiceNow API error {e.code} — skipped", "ticket_id": ticket_id}
    except Exception as e:
        logger.exception("Failed to update ServiceNow ticket — skipping to avoid blocking flow")
        return {"message": f"ServiceNow update failed: {str(e)} — skipped", "ticket_id": ticket_id}
