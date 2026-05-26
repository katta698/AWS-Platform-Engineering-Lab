"""
webhook_receiver — Week 2: Aurora Self-Service Platform
Receives ServiceNow webhook, validates HMAC-SHA256 signature,
starts Step Functions execution for database provisioning.
"""
import hashlib
import hmac
import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn = boto3.client("stepfunctions")
ssm = boto3.client("ssm")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
WEBHOOK_SECRET_PARAM = os.environ["WEBHOOK_SECRET_PARAM"]


def get_webhook_secret() -> str:
    resp = ssm.get_parameter(Name=WEBHOOK_SECRET_PARAM, WithDecryption=True)
    return resp["Parameter"]["Value"]


def validate_hmac(body: str, signature: str, secret: str) -> bool:
    expected = hmac.new(
        secret.encode(), body.encode(), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)


def lambda_handler(event, context):
    logger.info("Received webhook event")

    # Validate HMAC
    body = event.get("body", "")
    sig  = event.get("headers", {}).get("x-servicenow-signature", "")

    try:
        secret = get_webhook_secret()
        if sig and not validate_hmac(body, sig, secret):
            logger.warning("HMAC validation failed")
            return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized"})}
    except Exception as e:
        logger.error(f"HMAC check error: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": "Auth check failed"})}

    # Parse payload
    try:
        payload = json.loads(body) if isinstance(body, str) else body
    except json.JSONDecodeError:
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid JSON"})}

    # Validate required fields
    required = ["ticket_id", "db_name", "team", "requested_by"]
    missing  = [f for f in required if not payload.get(f)]
    if missing:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": f"Missing fields: {missing}"}),
        }

    # Sanitize db_name: lowercase, alphanumeric + underscores only, max 63 chars
    db_name_raw = payload["db_name"].lower().replace("-", "_").replace(" ", "_")
    db_name     = "".join(c for c in db_name_raw if c.isalnum() or c == "_")[:63]
    if not db_name:
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid db_name"})}

    sfn_input = {
        "ticket_id":    payload["ticket_id"],
        "db_name":      db_name,
        "team":         payload["team"],
        "requested_by": payload["requested_by"],
        "task_token":   payload.get("task_token", ""),
    }

    # Start Step Functions execution
    execution_name = f"db-{db_name}-{payload['ticket_id']}"[:80]
    try:
        resp = sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=execution_name,
            input=json.dumps(sfn_input),
        )
        logger.info(f"Started execution: {resp['executionArn']}")
    except sfn.exceptions.ExecutionAlreadyExists:
        logger.warning(f"Execution {execution_name} already exists — idempotent OK")
    except Exception as e:
        logger.error(f"Failed to start execution: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": "Failed to start workflow"})}

    return {
        "statusCode": 202,
        "body": json.dumps({
            "message":   "Database provisioning workflow started",
            "ticket_id": payload["ticket_id"],
            "db_name":   db_name,
        }),
    }
