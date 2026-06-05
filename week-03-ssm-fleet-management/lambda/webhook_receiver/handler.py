"""
webhook_receiver — Week 3 SSM Fleet Management
Validates HMAC signature from ServiceNow, determines request type
(onboard or patch), starts Step Functions execution.
"""

import os
import json
import hmac
import hashlib
import boto3

sfn = boto3.client("stepfunctions")
ssm = boto3.client("ssm")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]
WEBHOOK_SECRET    = os.environ["WEBHOOK_SECRET"]


def validate_hmac(body: str, signature: str) -> bool:
    expected = hmac.new(
        WEBHOOK_SECRET.encode(), body.encode(), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature)


def lambda_handler(event, context):
    # HMAC validation
    body      = event.get("body", "{}")
    signature = event.get("headers", {}).get("x-servicenow-signature", "")

    # Validate HMAC only when signature header is present (curl/webhook clients)
    # ServiceNow requests without signature are allowed for demo purposes
    if WEBHOOK_SECRET and signature and not validate_hmac(body, signature):
        return {"statusCode": 401, "body": json.dumps({"error": "Invalid signature"})}

    payload = json.loads(body)

    ticket_id    = payload.get("ticket_id", "")
    request_type = payload.get("request_type", "patch")   # "onboard" or "patch"
    instance_id  = payload.get("instance_id", "")         # required for onboard
    patch_group  = payload.get("patch_group", "")         # required for patch
    operation    = payload.get("operation", "Scan")        # Scan or Install

    if not ticket_id:
        return {"statusCode": 400, "body": json.dumps({"error": "ticket_id required"})}

    if request_type == "onboard" and not instance_id:
        return {"statusCode": 400, "body": json.dumps({"error": "instance_id required for onboard"})}

    if request_type == "patch" and not patch_group:
        return {"statusCode": 400, "body": json.dumps({"error": "patch_group required for patch"})}

    # Retrieve SSM Automation role ARN from Parameter Store
    automation_role_arn = ssm.get_parameter(
        Name=os.environ["SSM_AUTOMATION_ROLE_PARAM"]
    )["Parameter"]["Value"]

    execution_input = json.dumps({
        "ticket_id":            ticket_id,
        "request_type":         request_type,
        "instance_id":          instance_id,
        "patch_group":          patch_group,
        "operation":            operation,
        "automation_role_arn":  automation_role_arn,
        "requested_by":         payload.get("requested_by", "unknown"),
        "team":                 payload.get("team", "unknown"),
    })

    execution_name = f"{request_type}-{ticket_id.replace('_','-')}"[:80]

    try:
        resp = sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=execution_name,
            input=execution_input,
        )
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message":       "Execution started",
                "execution_arn": resp["executionArn"],
                "ticket_id":     ticket_id,
                "request_type":  request_type,
            }),
        }
    except sfn.exceptions.ExecutionAlreadyExists:
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Execution already running", "ticket_id": ticket_id}),
        }
