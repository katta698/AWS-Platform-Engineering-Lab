import json
import os

import boto3
from botocore.exceptions import ClientError

config_client = boto3.client("configservice")
sns_client = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
CONFIG_RULE_NAMES = [name.strip() for name in os.environ["CONFIG_RULE_NAMES"].split(",")]
MAX_RESOURCES_LISTED = 10


def _non_compliant_resources(rule_name):
    resources = []
    paginator = config_client.get_paginator("get_compliance_details_by_config_rule")
    for page in paginator.paginate(ConfigRuleName=rule_name, ComplianceTypes=["NON_COMPLIANT"]):
        for result in page.get("EvaluationResults", []):
            qualifier = result["EvaluationResultIdentifier"]["EvaluationResultQualifier"]
            resources.append(f"{qualifier['ResourceType']}:{qualifier['ResourceId']}")
    return resources


def _rule_summary(rule_name):
    try:
        non_compliant = _non_compliant_resources(rule_name)
    except ClientError as err:
        if err.response["Error"]["Code"] == "NoSuchConfigRuleException":
            return f"{rule_name}: rule not found yet (conformance pack may still be deploying)"
        raise

    if not non_compliant:
        return f"{rule_name}: COMPLIANT (0 non-compliant resources)"

    lines = [f"{rule_name}: {len(non_compliant)} non-compliant resource(s)"]
    for resource in non_compliant[:MAX_RESOURCES_LISTED]:
        lines.append(f"  - {resource}")
    if len(non_compliant) > MAX_RESOURCES_LISTED:
        lines.append(f"  ... and {len(non_compliant) - MAX_RESOURCES_LISTED} more")
    return "\n".join(lines)


def lambda_handler(event, context):
    lines = ["Week 12 Config Compliance Digest", ""]
    lines.extend(_rule_summary(rule_name) for rule_name in CONFIG_RULE_NAMES)
    message = "\n".join(lines)

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Week 12 Config Compliance Digest",
        Message=message,
    )

    return {"statusCode": 200, "body": json.dumps({"rules_checked": len(CONFIG_RULE_NAMES)})}
