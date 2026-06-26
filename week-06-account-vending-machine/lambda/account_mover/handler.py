"""
account_mover — moves a newly vended account out of the Organization root
and into its target OU, then tags it.
"""
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

orgs = boto3.client("organizations")

ROOT_ID     = os.environ["ROOT_ID"]
ENVIRONMENT = os.environ["ENVIRONMENT"]


def lambda_handler(event, context):
    account_id = event["account_id"]
    target_ou  = event["target_ou"]
    ou_id      = event["ou_ids"][target_ou]
    ticket_id  = event.get("ticket_id", "unknown")

    logger.info("Moving account %s into OU %s (%s)", account_id, target_ou, ou_id)
    orgs.move_account(
        AccountId=account_id,
        SourceParentId=ROOT_ID,
        DestinationParentId=ou_id,
    )

    orgs.tag_resource(
        ResourceId=account_id,
        Tags=[
            {"Key": "ManagedBy", "Value": "account-vending-machine"},
            {"Key": "Environment", "Value": ENVIRONMENT},
            {"Key": "TicketId", "Value": ticket_id},
            {"Key": "TargetOU", "Value": target_ou},
        ],
    )
    logger.info("Account %s moved and tagged", account_id)

    return {**event, "moved": True, "ou_id": ou_id}
