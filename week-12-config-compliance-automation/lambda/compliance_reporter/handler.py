import json
import os

import boto3

config_client = boto3.client("config")
sns_client = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
CONFORMANCE_PACK_NAME = os.environ["CONFORMANCE_PACK_NAME"]
MAX_RESOURCES_LISTED = 10


def _non_compliant_resources(rule_name):
    resources = []
    paginator = config_client.get_paginator("get_compliance_details_by_config_rule")
    for page in paginator.paginate(ConfigRuleName=rule_name, ComplianceTypes=["NON_COMPLIANT"]):
        for result in page.get("EvaluationResults", []):
            qualifier = result["EvaluationResultIdentifier"]["EvaluationResultQualifier"]
            resources.append(f"{qualifier['ResourceType']}:{qualifier['ResourceId']}")
    return resources


def _rule_summary(rule_name, compliance_type):
    if compliance_type == "COMPLIANT":
        return f"{rule_name}: COMPLIANT"
    if compliance_type != "NON_COMPLIANT":
        return f"{rule_name}: {compliance_type} (no evaluations recorded yet)"

    non_compliant = _non_compliant_resources(rule_name)
    lines = [f"{rule_name}: {len(non_compliant)} non-compliant resource(s)"]
    for resource in non_compliant[:MAX_RESOURCES_LISTED]:
        lines.append(f"  - {resource}")
    if len(non_compliant) > MAX_RESOURCES_LISTED:
        lines.append(f"  ... and {len(non_compliant) - MAX_RESOURCES_LISTED} more")
    return "\n".join(lines)


def lambda_handler(event, context):
    # Rule names inside a conformance pack get AWS's own generated suffix
    # (e.g. "week12-required-tags-conformance-pack-<id>") -- discovering them
    # here instead of hardcoding avoids the reporter silently going stale if
    # that suffix ever changes.
    rules = config_client.describe_conformance_pack_compliance(
        ConformancePackName=CONFORMANCE_PACK_NAME
    )["ConformancePackRuleComplianceList"]

    lines = ["Week 12 Config Compliance Digest", ""]
    lines.extend(_rule_summary(rule["ConfigRuleName"], rule["ComplianceType"]) for rule in rules)
    message = "\n".join(lines)

    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="Week 12 Config Compliance Digest",
        Message=message,
    )

    return {"statusCode": 200, "body": json.dumps({"rules_checked": len(rules)})}
