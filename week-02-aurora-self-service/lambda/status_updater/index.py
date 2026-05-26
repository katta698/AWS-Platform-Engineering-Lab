"""
status_updater — Week 2: Aurora Self-Service Platform

Updates the ServiceNow ticket with connection details after DB provisioning.
Called by Step Functions after db_provisioner succeeds.
"""
import json
import logging
import os
import urllib.request
import urllib.parse
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")

SERVICENOW_INSTANCE_PARAM = os.environ["SERVICENOW_INSTANCE_PARAM"]
SERVICENOW_USERNAME_PARAM = os.environ["SERVICENOW_USERNAME_PARAM"]
SERVICENOW_PASSWORD_PARAM = os.environ["SERVICENOW_PASSWORD_PARAM"]


def get_ssm(name: str) -> str:
    return ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]


def update_servicenow_ticket(instance_url: str, username: str, password: str,
                              ticket_id: str, work_notes: str, state: str = "3"):
    """Update a ServiceNow RITM/ticket with work notes and close it."""
    import base64

    table   = "sc_req_item" if ticket_id.startswith("RITM") else "incident"
    api_url = f"{instance_url}/api/now/table/{table}"

    # Find record by number
    query_url = f"{api_url}?sysparm_query=number={ticket_id}&sysparm_fields=sys_id"
    credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
    headers = {
        "Authorization": f"Basic {credentials}",
        "Content-Type":  "application/json",
        "Accept":        "application/json",
    }

    req = urllib.request.Request(query_url, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as resp:
        data    = json.loads(resp.read())
        results = data.get("result", [])

    if not results:
        logger.error(f"Ticket {ticket_id} not found in ServiceNow")
        raise ValueError(f"Ticket {ticket_id} not found")

    sys_id   = results[0]["sys_id"]
    patch_url = f"{api_url}/{sys_id}"
    payload   = json.dumps({
        "work_notes":    work_notes,
        "state":         state,   # 3 = Closed Complete
        "close_notes":   work_notes,
    }).encode()

    patch_req = urllib.request.Request(
        patch_url, data=payload, headers=headers, method="PATCH"
    )
    with urllib.request.urlopen(patch_req, timeout=10) as resp:
        resp_data = json.loads(resp.read())
        logger.info(f"ServiceNow ticket {ticket_id} updated: state={state}")
        return resp_data


def lambda_handler(event, context):
    logger.info(f"Updating ServiceNow for ticket: {event.get('ticket_id')}")

    ticket_id  = event["ticket_id"]
    db_name    = event["db_name"]
    username   = event["username"]
    host       = event["host"]
    port       = event.get("port", 5432)
    secret_name = event["secret_name"]
    reader_ep  = event.get("reader_endpoint", "same as writer")

    work_notes = f"""✅ Database provisioning complete!

🗄️ Database Details:
• Database Name : {db_name}
• Username      : {username}
• Writer Host   : {host}
• Reader Host   : {reader_ep}
• Port          : {port}
• Engine        : Aurora PostgreSQL 16 (Serverless v2)

🔑 Credentials:
Your credentials are stored in AWS Secrets Manager.
Secret Name: {secret_name}

To retrieve your connection string:
  aws secretsmanager get-secret-value --secret-id {secret_name}

🔄 Auto-Rotation:
Credentials rotate automatically every 30 days.
Your app should always retrieve the secret at startup — never cache passwords.

📊 Monitoring:
• CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home#dashboards
• Performance Insights: Available in RDS Console

⚠️ Important:
• Use the writer endpoint for writes, reader endpoint for read-only queries
• This is a shared Aurora cluster — your database is isolated by PostgreSQL permissions
• Max 50 connections per database (configurable — raise a ticket if needed)
"""

    try:
        instance_url = get_ssm(SERVICENOW_INSTANCE_PARAM)
        sn_username  = get_ssm(SERVICENOW_USERNAME_PARAM)
        sn_password  = get_ssm(SERVICENOW_PASSWORD_PARAM)

        update_servicenow_ticket(
            instance_url, sn_username, sn_password,
            ticket_id, work_notes
        )
    except Exception as e:
        logger.error(f"ServiceNow update failed: {e}")
        # Non-fatal for the overall workflow — DB is already provisioned
        # Step Functions can retry or alert

    # Send Step Functions callback if task token provided
    ticket_token = event.get("task_token", "")
    if ticket_token:
        sfn = boto3.client("stepfunctions")
        try:
            sfn.send_task_success(
                taskToken=ticket_token,
                output=json.dumps({
                    "status":      "success",
                    "db_name":     db_name,
                    "secret_name": secret_name,
                    "host":        host,
                }),
            )
        except Exception as e:
            logger.warning(f"Step Functions callback failed: {e}")

    return {
        "status":    "success",
        "ticket_id": ticket_id,
        "db_name":   db_name,
    }
