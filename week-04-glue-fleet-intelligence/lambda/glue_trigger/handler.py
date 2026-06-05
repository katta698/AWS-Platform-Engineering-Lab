"""
glue_trigger — starts the Glue crawler and/or ETL job, and polls their status.
Called from Step Functions as a task Lambda (action-based pattern).
"""
import json
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

glue = boto3.client("glue")

CRAWLER_NAME = os.environ["CRAWLER_NAME"]
JOB_NAME     = os.environ["JOB_NAME"]
ENVIRONMENT  = os.environ["ENVIRONMENT"]


def start_crawler(event, context):
    """Start Glue crawler. Returns immediately — Step Functions polls status."""
    logger.info("Starting crawler: %s", CRAWLER_NAME)
    try:
        glue.start_crawler(Name=CRAWLER_NAME)
        logger.info("Crawler started")
    except glue.exceptions.CrawlerRunningException:
        logger.info("Crawler already running — continuing")
    return {"crawler_name": CRAWLER_NAME, "action": "started"}


def get_crawler_status(event, context):
    """Return crawler state for Step Functions wait loop."""
    resp = glue.get_crawler(Name=CRAWLER_NAME)
    state = resp["Crawler"]["State"]
    logger.info("Crawler state: %s", state)
    return {
        "crawler_name": CRAWLER_NAME,
        "state":        state,
        "ready":        state == "READY",
    }


def start_etl_job(event, context):
    """Start the Glue ETL job."""
    ticket_id    = event.get("ticket_id", "unknown")
    report_scope = event.get("report_scope", "all")

    logger.info("Starting ETL job: %s", JOB_NAME)
    resp = glue.start_job_run(
        JobName=JOB_NAME,
        Arguments={
            "--TICKET_ID":    ticket_id,
            "--REPORT_SCOPE": report_scope,
        },
    )
    run_id = resp["JobRunId"]
    logger.info("ETL job run started: %s", run_id)
    return {"job_name": JOB_NAME, "job_run_id": run_id}


def get_job_status(event, context):
    """Return ETL job run state for Step Functions wait loop."""
    job_run_id = event.get("job_run_id")
    resp = glue.get_job_run(JobName=JOB_NAME, RunId=job_run_id)
    state = resp["JobRun"]["JobRunState"]
    logger.info("ETL job state: %s", state)
    return {
        "job_run_id": job_run_id,
        "state":      state,
        "succeeded":  state == "SUCCEEDED",
        "failed":     state in ("FAILED", "ERROR", "TIMEOUT"),
    }


def lambda_handler(event, context):
    """
    Dispatch based on 'action' key sent by Step Functions.
    Actions: start_crawler | get_crawler_status | start_etl_job | get_job_status
    """
    action = event.get("action", "start_crawler")
    logger.info("Action: %s", action)

    dispatch = {
        "start_crawler":      start_crawler,
        "get_crawler_status": get_crawler_status,
        "start_etl_job":      start_etl_job,
        "get_job_status":     get_job_status,
    }

    handler_fn = dispatch.get(action)
    if not handler_fn:
        raise ValueError(f"Unknown action: {action}")

    result = handler_fn(event, context)
    return {**event, **result}
