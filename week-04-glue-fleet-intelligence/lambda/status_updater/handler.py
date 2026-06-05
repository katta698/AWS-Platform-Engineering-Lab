"""
status_updater — closes ServiceNow ticket with fleet intelligence report details.
"""
import json
import os
import boto3
import urllib.request
import urllib.parse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")

SNOW_INSTANCE_PARAM  = os.environ["SNOW_INSTANCE_PARAM"]
SNOW_USER_PARAM      = os.environ["SNOW_USER_PARAM"]
SNOW_PASSWORD_PARAM  = os.environ["SNOW_PASSWORD_PARAM"]
ATHENA_WORKGROUP     = os.environ["ATHENA_WORKGROUP"]
ENVIRONMENT          = os.environ["ENVIRONMENT"]


def get_param(name: str) -> str:
    return ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]


def update_snow_ticket(instance: str, user: str, password: str, ticket_id: str, status: str, notes: str):
    url = f"https://{instance}.service-now.com/api/now/table/sc_req_item/{ticket_id}"
    payload = json.dumps({
        "state":            "3",  # Closed Complete
        "close_notes":      notes,
        "work_notes":       f"[Fleet Intelligence] {status}",
    }).encode()

    credentials = urllib.parse.quote(f"{user}:{password}")
    req = urllib.request.Request(
        url,
        data=payload,
        method="PATCH",
        headers={
            "Content-Type":  "application/json",
            "Accept":        "application/json",
            "Authorization": f"Basic {__import__('base64').b64encode(f'{user}:{password}'.encode()).decode()}",
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        logger.info("ServiceNow response: %s", resp.status)


def lambda_handler(event, context):
    logger.info("Event: %s", json.dumps(event))

    ticket_id  = event.get("ticket_id", "UNKNOWN")
    succeeded  = event.get("pipeline_succeeded", False)
    job_run_id = event.get("job_run_id", "unknown")

    athena_console = (
        f"https://us-east-1.console.aws.amazon.com/athena/home"
        f"?region=us-east-1#/query-editor"
    )

    if succeeded:
        notes = (
            f"Fleet intelligence pipeline completed successfully.\n\n"
            f"Glue ETL Job Run ID: {job_run_id}\n"
            f"Athena Workgroup: {ATHENA_WORKGROUP}\n\n"
            f"Query your fleet data at:\n{athena_console}\n\n"
            f"Pre-built queries available:\n"
            f"- fleet-patch-compliance-summary\n"
            f"- fleet-non-compliant-instances\n"
            f"- fleet-os-inventory\n\n"
            f"Environment: {ENVIRONMENT}"
        )
        status = "Pipeline SUCCEEDED"
    else:
        notes  = f"Fleet intelligence pipeline FAILED. Check CloudWatch logs. Job Run ID: {job_run_id}"
        status = "Pipeline FAILED"

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
