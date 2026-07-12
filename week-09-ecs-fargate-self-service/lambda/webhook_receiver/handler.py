"""
webhook_receiver — validates HMAC-signed ServiceNow webhook and starts the
Fargate self-service provisioning Step Functions execution.
"""
import json
import hmac
import hashlib
import os
import re
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client("ssm")
sfn_client = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
HMAC_SECRET_PARAM = os.environ["HMAC_SECRET_PARAM"]
ENVIRONMENT       = os.environ["ENVIRONMENT"]

# ECR repo name, ECS resource names, and the ALB path prefix are all derived
# from service_name — keep it DNS/path safe.
SERVICE_NAME_RE    = re.compile(r"^[a-z][a-z0-9-]{2,31}$")
EXECUTION_NAME_RE  = re.compile(r"[^a-zA-Z0-9._-]")
VALID_FARGATE_CPU  = {256, 512, 1024, 2048, 4096}


def get_hmac_secret() -> str:
    resp = ssm_client.get_parameter(Name=HMAC_SECRET_PARAM, WithDecryption=True)
    return resp["Parameter"]["Value"]


def verify_hmac(body: str, signature: str, secret: str) -> bool:
    expected = hmac.new(secret.encode(), body.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    body      = event.get("body", "{}")
    signature = event.get("headers", {}).get("x-servicenow-hmac", "")

    try:
        secret = get_hmac_secret()
        if not verify_hmac(body, signature, secret):
            logger.warning("HMAC validation failed")
            return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized"})}
    except Exception as e:
        logger.error("HMAC check error: %s", e)
        return {"statusCode": 500, "body": json.dumps({"error": "Internal error"})}

    payload = json.loads(body)
    ticket_id      = payload.get("ticket_id", "UNKNOWN")
    ticket_sys_id  = payload.get("ticket_sys_id")
    service_name   = payload.get("service_name")
    image_uri      = payload.get("image_uri")
    container_port = payload.get("container_port")
    cpu            = int(payload.get("cpu", 256))
    memory         = int(payload.get("memory", 512))
    desired_count  = int(payload.get("desired_count", 1))

    if not ticket_sys_id:
        # Week 4's lesson: the ServiceNow Table API PATCH endpoint needs the
        # record's sys_id (GUID), not its display number (e.g. RITM0010023)
        # — status_notifier needs this to actually close the ticket.
        return {"statusCode": 400, "body": json.dumps({"error": "ticket_sys_id is required"})}

    if not service_name or not SERVICE_NAME_RE.match(service_name):
        return {"statusCode": 400, "body": json.dumps({
            "error": "service_name is required: lowercase letters/digits/hyphens, 3-32 chars, must start with a letter"
        })}

    if not image_uri:
        return {"statusCode": 400, "body": json.dumps({"error": "image_uri is required"})}

    if not container_port or not (1 <= int(container_port) <= 65535):
        return {"statusCode": 400, "body": json.dumps({"error": "container_port must be between 1 and 65535"})}

    if cpu not in VALID_FARGATE_CPU:
        return {"statusCode": 400, "body": json.dumps({"error": f"cpu must be one of {sorted(VALID_FARGATE_CPU)}"})}

    if desired_count < 1 or desired_count > 10:
        return {"statusCode": 400, "body": json.dumps({"error": "desired_count must be between 1 and 10"})}

    execution_input = {
        "ticket_id":      ticket_id,
        "ticket_sys_id":  ticket_sys_id,
        "service_name":   service_name,
        "image_uri":      image_uri,
        "container_port": int(container_port),
        "cpu":            cpu,
        "memory":         memory,
        "desired_count":  desired_count,
        "environment":    ENVIRONMENT,
    }

    safe_name = EXECUTION_NAME_RE.sub("-", ticket_id)
    resp = sfn_client.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        name=f"fargate-{safe_name}",
        input=json.dumps(execution_input),
    )
    logger.info("Started execution: %s", resp["executionArn"])

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message":       "Fargate self-service provisioning started",
            "ticket_id":     ticket_id,
            "execution_arn": resp["executionArn"],
        }),
    }
