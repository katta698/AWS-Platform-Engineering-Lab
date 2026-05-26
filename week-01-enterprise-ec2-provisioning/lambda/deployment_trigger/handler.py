"""
Lambda: Deployment Trigger
──────────────────────────
Triggered by: Step Functions (sync:2 — waits for callback token)
Purpose:
  1. Receive infrastructure parameters + Step Functions task token
  2. Trigger GitHub Actions workflow via repository_dispatch API
  3. Pass the callback token to GitHub Actions as an input
  4. GitHub Actions runs Terraform and sends the token back via send_task_success

Environment Variables:
  GITHUB_TOKEN_PARAM   - SSM path for GitHub PAT or App token
  GITHUB_ORG           - GitHub organization
  GITHUB_REPO          - Repository name
  GITHUB_WORKFLOW      - Workflow filename (e.g. deploy.yml)
"""

import json
import os
import boto3
import logging
import urllib.request
import urllib.error

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client("ssm")

GITHUB_TOKEN_PARAM = os.environ["GITHUB_TOKEN_PARAM"]
GITHUB_ORG         = os.environ["GITHUB_ORG"]
GITHUB_REPO        = os.environ["GITHUB_REPO"]
GITHUB_WORKFLOW    = os.environ.get("GITHUB_WORKFLOW", "deploy.yml")


def get_github_token() -> str:
    response = ssm_client.get_parameter(
        Name=GITHUB_TOKEN_PARAM,
        WithDecryption=True
    )
    return response["Parameter"]["Value"]


def trigger_github_workflow(token: str, payload: dict) -> dict:
    """
    Trigger GitHub Actions via repository_dispatch event.
    The task_token is embedded so GA can callback to Step Functions.
    """
    url = f"https://api.github.com/repos/{GITHUB_ORG}/{GITHUB_REPO}/dispatches"
    data = json.dumps({
        "event_type": "provision-infrastructure",
        "client_payload": payload
    }).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept":        "application/vnd.github+json",
            "Content-Type":  "application/json",
            "X-GitHub-Api-Version": "2022-11-28"
        },
        method="POST"
    )

    with urllib.request.urlopen(req, timeout=10) as response:
        status = response.status
        logger.info("GitHub dispatch response status: %d", status)
        return {"status": status}


def lambda_handler(event, context):
    """
    Input event contains:
      - All infrastructure parameters from ServiceNow
      - TaskToken from Step Functions (injected by SF integration pattern)
    """
    logger.info("Deployment trigger event: %s", json.dumps(event, default=str))

    task_token = event.get("TaskToken")  # Injected by Step Functions
    params     = event.get("input", event)  # Infrastructure parameters

    if not task_token:
        raise ValueError("TaskToken is required — ensure Step Functions uses .waitForTaskToken")

    try:
        token = get_github_token()

        # Build GitHub Actions workflow input
        workflow_payload = {
            "task_token":    task_token,  # Step Functions callback token
            "ticket_id":     params.get("ticket_id"),
            "ticket_number": params.get("ticket_number"),
            "environment":   params.get("environment", "dev"),
            "instance_type": params.get("instance_type", "t3.medium"),
            "desired_capacity": str(params.get("desired_capacity", 2)),
            "cost_center":   params.get("cost_center", ""),
            "project_name":  params.get("project_name", "selfservice-ec2"),
            "requested_by":  params.get("requested_by", ""),
        }

        result = trigger_github_workflow(token, workflow_payload)
        logger.info("GitHub Actions triggered successfully: %s", result)

        # Note: We do NOT return success here.
        # Step Functions is waiting for GitHub Actions to call SendTaskSuccess.
        return {
            "status": "workflow_dispatched",
            "ticket_id": params.get("ticket_id"),
            "github_dispatch_status": result["status"]
        }

    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        logger.error("GitHub API error %d: %s", e.code, error_body)
        raise RuntimeError(f"GitHub API error {e.code}: {error_body}")
    except Exception as e:
        logger.exception("Failed to trigger GitHub Actions")
        raise
