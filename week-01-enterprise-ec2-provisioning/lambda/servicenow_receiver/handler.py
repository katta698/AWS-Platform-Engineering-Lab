"""
Lambda: ServiceNow Webhook Receiver
────────────────────────────────────
Triggered by: API Gateway (POST /provision)
Purpose:
  1. Validate the incoming ServiceNow webhook (HMAC signature)
  2. Parse the catalog request payload
  3. Start the Step Functions workflow
  4. Return 200 immediately so ServiceNow doesn't retry

Environment Variables:
  STEP_FUNCTION_ARN    - ARN of the provisioning state machine
  WEBHOOK_SECRET_PARAM - SSM parameter path for HMAC secret
  ENVIRONMENT          - dev | staging | prod
"""

import json
import os
import hmac
import hashlib
import boto3
import logging
import uuid
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn_client   = boto3.client("stepfunctions")
ssm_client   = boto3.client("ssm")

STEP_FUNCTION_ARN    = os.environ["STATE_MACHINE_ARN"]
WEBHOOK_SECRET_PARAM = os.environ["WEBHOOK_SECRET_PARAM"]
ENVIRONMENT          = os.environ.get("ENVIRONMENT", "dev")


def get_webhook_secret() -> str:
    """Retrieve HMAC secret from SSM Parameter Store."""
    response = ssm_client.get_parameter(
        Name=WEBHOOK_SECRET_PARAM,
        WithDecryption=True
    )
    return response["Parameter"]["Value"]


def validate_signature(body: str, signature: str, secret: str) -> bool:
    """Validate ServiceNow HMAC-SHA256 webhook signature."""
    expected = hmac.new(
        secret.encode("utf-8"),
        body.encode("utf-8"),
        hashlib.sha256
    ).hexdigest()

    return hmac.compare_digest(f"sha256={expected}", signature)


def parse_servicenow_payload(body: dict) -> dict:
    """
    Map ServiceNow Business Rule webhook payload to infrastructure parameters.
    Business Rule sends a flat JSON payload (not nested ServiceNow API format).
    """
    return {
        "ticket_id":        body.get("ticket_id", ""),
        "ticket_number":    body.get("ticket_id", ""),
        "requested_by":     body.get("requested_by", ""),
        "requester_email":  body.get("requested_by", ""),
        "environment":      body.get("environment", "dev"),
        "instance_type":    body.get("instance_type", "t3.medium"),
        "desired_capacity": int(body.get("desired_capacity", 1)),
        "cost_center":      body.get("cost_center", ""),
        "project_name":     body.get("project_name", "selfservice-ec2"),
        "purpose":          body.get("justification", ""),
        "approved_by":      "",
        "request_timestamp": datetime.utcnow().isoformat(),
    }


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event, default=str))

    try:
        # ── 1. Parse body ─────────────────────────────────────────────────
        body_str = event.get("body", "{}")
        if event.get("isBase64Encoded"):
            import base64
            body_str = base64.b64decode(body_str).decode("utf-8")
        body = json.loads(body_str)

        # ── 2. Validate HMAC signature ────────────────────────────────────
        signature = event.get("headers", {}).get("x-servicenow-signature", "")
        if ENVIRONMENT != "dev":  # Skip in dev for easier testing
            secret = get_webhook_secret()
            if not validate_signature(body_str, signature, secret):
                logger.warning("Invalid webhook signature — rejecting request")
                return {"statusCode": 401, "body": json.dumps({"error": "Invalid signature"})}

        # ── 3. Parse ServiceNow payload ───────────────────────────────────
        params = parse_servicenow_payload(body)
        logger.info("Parsed parameters: %s", json.dumps(params))

        # ── 4. Start Step Functions execution ────────────────────────────
        execution_name = f"sn-{params['ticket_number']}-{uuid.uuid4().hex[:8]}"
        response = sfn_client.start_execution(
            stateMachineArn=STEP_FUNCTION_ARN,
            name=execution_name,
            input=json.dumps(params)
        )

        logger.info("Started Step Functions execution: %s", response["executionArn"])

        return {
            "statusCode": 202,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "message": "Provisioning workflow started",
                "execution_arn": response["executionArn"],
                "ticket_id": params["ticket_id"],
            })
        }

    except json.JSONDecodeError as e:
        logger.error("Invalid JSON payload: %s", str(e))
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid JSON"})}
    except Exception as e:
        logger.exception("Unexpected error in receiver Lambda")
        return {"statusCode": 500, "body": json.dumps({"error": "Internal error"})}
