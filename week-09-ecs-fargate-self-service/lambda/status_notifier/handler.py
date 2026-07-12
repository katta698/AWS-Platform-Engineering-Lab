"""
status_notifier — closes the ServiceNow ticket with the newly provisioned
service's live URL, or the failure reason.
"""
import json
import os
import base64
import boto3
import urllib.request
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


def update_snow_ticket(instance: str, user: str, password: str, ticket_sys_id: str, status: str, notes: str):
    # Must be the record's sys_id (GUID), not its display number (RITM0010023)
    # — Week 4's documented lesson, re-learned the hard way here on 2026-07-12
    # via a real 404 from a live end-to-end test that used the number instead.
    url = f"https://{instance}.service-now.com/api/now/table/sc_req_item/{ticket_sys_id}"
    payload = json.dumps({
        "state":       "3",  # Closed Complete
        "close_notes": notes,
        "work_notes":  f"[ECS Fargate Self-Service] {status}",
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

    ticket_id     = event.get("ticket_id", "UNKNOWN")
    ticket_sys_id = event.get("ticket_sys_id") or ""
    succeeded     = event.get("succeeded", False)
    service_name  = event.get("service_name", "unknown")

    if succeeded:
        service_url = event.get("service_url", "unknown")
        notes = (
            f"ECS Fargate self-service provisioning completed successfully.\n\n"
            f"Service Name: {service_name}\n"
            f"Service URL:  {service_url}\n\n"
            f"Note: the URL may return a health-check error for the first 30-60 "
            f"seconds while the task starts and passes its first ALB health check.\n\n"
            f"Environment: {ENVIRONMENT}"
        )
        status = "Provisioning SUCCEEDED"
    else:
        failure_reason = event.get("failure_reason", "UNKNOWN")
        notes  = f"ECS Fargate self-service provisioning FAILED. Reason: {failure_reason}"
        status = "Provisioning FAILED"

    if not ticket_sys_id:
        # No real ServiceNow ticket to close - e.g. a manual test_webhook.sh
        # run exercising the AWS-side pipeline directly. Not an error.
        logger.info("No ticket_sys_id provided, skipping ServiceNow update (manual/test invocation)")
        return {**event, "snow_updated": False, "status": status}

    try:
        snow_instance = get_param(SNOW_INSTANCE_PARAM)
        snow_user     = get_param(SNOW_USER_PARAM)
        snow_password = get_param(SNOW_PASSWORD_PARAM)
        update_snow_ticket(snow_instance, snow_user, snow_password, ticket_sys_id, status, notes)
        logger.info("ServiceNow ticket %s updated", ticket_id)
    except Exception as e:
        logger.error("Failed to update ServiceNow: %s", e)
        raise

    return {**event, "snow_updated": True, "status": status}
