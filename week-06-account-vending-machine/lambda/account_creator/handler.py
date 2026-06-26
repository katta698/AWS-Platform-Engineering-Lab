"""
account_creator — calls organizations:CreateAccount and polls its status.
Called from Step Functions as an action-dispatch task Lambda, same pattern
as Week 4's glue_trigger.

NOTE: organizations.create_account creates a REAL AWS account in the
Organization. There is no instant delete — closed accounts go through a
~90 day suspension window. Only invoke this with intent.
"""
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

orgs = boto3.client("organizations")

ENVIRONMENT = os.environ["ENVIRONMENT"]


def create_account(event, context):
    """Submit the account creation request. Returns immediately — Step Functions polls status."""
    account_name  = event["account_name"]
    account_email = event["account_email"]

    logger.info("Requesting new account: %s (%s)", account_name, account_email)
    resp = orgs.create_account(AccountName=account_name, Email=account_email)
    request_id = resp["CreateAccountStatus"]["Id"]
    logger.info("CreateAccount request submitted: %s", request_id)
    return {"create_account_request_id": request_id}


def get_account_status(event, context):
    """Return CreateAccount request state for Step Functions wait loop."""
    request_id = event["create_account_request_id"]
    resp = orgs.describe_create_account_status(CreateAccountRequestId=request_id)
    status = resp["CreateAccountStatus"]
    state = status["State"]
    logger.info("CreateAccount state: %s", state)

    result = {
        "create_account_request_id": request_id,
        "state":     state,
        "succeeded": state == "SUCCEEDED",
        "failed":    state == "FAILED",
    }
    if state == "SUCCEEDED":
        result["account_id"] = status["AccountId"]
    elif state == "FAILED":
        result["failure_reason"] = status.get("FailureReason", "UNKNOWN")
    return result


def lambda_handler(event, context):
    """
    Dispatch based on 'action' key sent by Step Functions.
    Actions: create_account | get_account_status
    """
    action = event.get("action", "create_account")
    logger.info("Action: %s", action)

    dispatch = {
        "create_account":     create_account,
        "get_account_status": get_account_status,
    }

    handler_fn = dispatch.get(action)
    if not handler_fn:
        raise ValueError(f"Unknown action: {action}")

    result = handler_fn(event, context)
    return {**event, **result}
