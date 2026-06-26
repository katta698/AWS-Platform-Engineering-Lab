"""
webhook_receiver — validates HMAC-signed ServiceNow webhook and starts the
account-vending Step Functions execution.
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
OU_IDS            = json.loads(os.environ["OU_IDS_JSON"])

ALLOWED_OUS    = {"Sandbox", "Production"}
EXECUTION_NAME_RE = re.compile(r"[^a-zA-Z0-9._-]")


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
    ticket_id     = payload.get("ticket_id", "UNKNOWN")
    requested_by  = payload.get("requested_by", "unknown")
    account_name  = payload.get("account_name")
    account_email = payload.get("account_email")
    target_ou     = payload.get("target_ou", "Sandbox")

    if not account_name or not account_email:
        return {"statusCode": 400, "body": json.dumps({"error": "account_name and account_email are required"})}

    if target_ou not in ALLOWED_OUS:
        return {"statusCode": 400, "body": json.dumps({"error": f"target_ou must be one of {sorted(ALLOWED_OUS)}"})}

    execution_input = {
        "ticket_id":     ticket_id,
        "requested_by":  requested_by,
        "account_name":  account_name,
        "account_email": account_email,
        "target_ou":     target_ou,
        "ou_ids":        OU_IDS,
        "environment":   ENVIRONMENT,
    }

    safe_name = EXECUTION_NAME_RE.sub("-", ticket_id)
    resp = sfn_client.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        name=f"avm-{safe_name}",
        input=json.dumps(execution_input),
    )
    logger.info("Started execution: %s", resp["executionArn"])

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message":       "Account vending pipeline started",
            "ticket_id":     ticket_id,
            "execution_arn": resp["executionArn"],
        }),
    }
