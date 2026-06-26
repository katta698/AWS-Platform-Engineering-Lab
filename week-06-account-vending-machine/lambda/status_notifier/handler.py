"""
status_notifier — closes the ServiceNow ticket with the vended account's
details (account ID, OU, region) or the failure reason.
"""
import json
import os
import base64
import boto3
import urllib.request
import urllib.parse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")

SNOW_INSTANCE_PARAM = os.environ["SNOW_INSTANCE_PARAM"]
SNOW_USER_PARAM     = os.environ["SNOW_USER_PARAM"]
SNOW_PASSWORD_PARAM = os.environ["SNOW_PASSWORD_PARAM"]
ENVIRONMENT         = os.environ["ENVIRONMENT"]


def get_param(name: str) -> str:
    return ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]


def update_snow_ticket(instance: str, user: str, password: str, ticket_id: str, status: str, notes: str):
    url = f"https://{instance}.service-now.com/api/now/table/sc_req_item/{ticket_id}"
    payload = json.dumps({
        "state":       "3",  # Closed Complete
        "close_notes": notes,
        "work_notes":  f"[Account Vending Machine] {status}",
    }).encode()

    credentials = base64.b64encode(f"{user}:{password}".encode()).decode()
    req = urllib.request.Request(
        url,
        data=payload,
        method="PATCH",
        headers={
            "Content-Type":  "application/json",
            "Accept":        "application/json",
            "Authorization": f"Basic {credentials}",
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        logger.info("ServiceNow response: %s", resp.status)


def lambda_handler(event, context):
    logger.info("Event: %s", json.dumps(event))

    ticket_id    = event.get("ticket_id", "UNKNOWN")
    succeeded    = event.get("succeeded", False)
    account_id   = event.get("account_id", "unknown")
    account_name = event.get("account_name", "unknown")
    target_ou    = event.get("target_ou", "unknown")

    if succeeded:
        notes = (
            f"Account vending pipeline completed successfully.\n\n"
            f"Account Name: {account_name}\n"
            f"Account ID:   {account_id}\n"
            f"Target OU:    {target_ou}\n\n"
            f"This account now inherits the SCP guardrails attached to the {target_ou} OU.\n\n"
            f"Environment: {ENVIRONMENT}"
        )
        status = "Account vending SUCCEEDED"
    else:
        failure_reason = event.get("failure_reason", "UNKNOWN")
        notes  = f"Account vending pipeline FAILED. Reason: {failure_reason}"
        status = "Account vending FAILED"

    try:
        snow_instance = get_param(SNOW_INSTANCE_PARAM)
        snow_user     = get_param(SNOW_USER_PARAM)
        snow_password = get_param(SNOW_PASSWORD_PARAM)
        update_snow_ticket(snow_instance, snow_user, snow_password, ticket_id, status, notes)
        logger.info("ServiceNow ticket %s updated", ticket_id)
    except Exception as e:
        logger.error("Failed to update ServiceNow: %s", e)
        raise

    return {**event, "snow_updated": True, "status": status}
