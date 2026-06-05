"""
webhook_receiver — validates HMAC-signed ServiceNow webhook and starts Step Functions execution.
"""
import json
import hmac
import hashlib
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client("ssm")
sfn_client = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
HMAC_SECRET_PARAM = os.environ["HMAC_SECRET_PARAM"]
ENVIRONMENT       = os.environ["ENVIRONMENT"]


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
    report_scope  = payload.get("report_scope", "all")   # all | patch | inventory

    execution_input = {
        "ticket_id":    ticket_id,
        "requested_by": requested_by,
        "report_scope": report_scope,
        "environment":  ENVIRONMENT,
    }

    resp = sfn_client.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        name=f"fleet-intel-{ticket_id}",
        input=json.dumps(execution_input),
    )
    logger.info("Started execution: %s", resp["executionArn"])

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message":      "Fleet intelligence pipeline started",
            "ticket_id":    ticket_id,
            "execution_arn": resp["executionArn"],
        }),
    }
