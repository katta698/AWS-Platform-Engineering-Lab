"""
fargate_provisioner — creates everything a self-service ticket needs to run:
ECR repo, CloudWatch log group, task definition, ALB target group + path
rule, ECS service, and an auto-scaling target. Mirrors Week 2's db_provisioner
pattern: the platform baseline (cluster, ALB, IAM) is static Terraform, but
per-tenant resources are created imperatively via boto3 at request time.
"""
import json
import os
import logging

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs   = boto3.client("ecs")
ecr   = boto3.client("ecr")
elbv2 = boto3.client("elbv2")
aas   = boto3.client("application-autoscaling")
logs  = boto3.client("logs")

PROJECT_NAME        = os.environ["PROJECT_NAME"]
CLUSTER_NAME         = os.environ["CLUSTER_NAME"]
PRIVATE_SUBNET_IDS   = json.loads(os.environ["PRIVATE_SUBNET_IDS_JSON"])
ECS_TASKS_SG_ID       = os.environ["ECS_TASKS_SG_ID"]
EXECUTION_ROLE_ARN    = os.environ["EXECUTION_ROLE_ARN"]
ALB_LISTENER_ARN      = os.environ["ALB_LISTENER_ARN"]
ALB_DNS_NAME          = os.environ["ALB_DNS_NAME"]
VPC_ID                = os.environ["VPC_ID"]


def ensure_ecr_repo(service_name: str) -> None:
    repo_name = f"{PROJECT_NAME}-{service_name}"
    try:
        ecr.create_repository(
            repositoryName=repo_name,
            imageScanningConfiguration={"scanOnPush": True},
            imageTagMutability="IMMUTABLE",
        )
        logger.info("Created ECR repo %s", repo_name)
    except ClientError as e:
        if e.response["Error"]["Code"] != "RepositoryAlreadyExistsException":
            raise
        logger.info("ECR repo %s already exists, reusing", repo_name)


def ensure_log_group(log_group_name: str) -> None:
    try:
        logs.create_log_group(logGroupName=log_group_name)
        logs.put_retention_policy(logGroupName=log_group_name, retentionInDays=14)
    except ClientError as e:
        if e.response["Error"]["Code"] != "ResourceAlreadyExistsException":
            raise


def register_task_definition(service_name: str, image_uri: str, container_port: int,
                              cpu: int, memory: int, log_group_name: str) -> str:
    resp = ecs.register_task_definition(
        family=f"{PROJECT_NAME}-{service_name}",
        networkMode="awsvpc",
        requiresCompatibilities=["FARGATE"],
        cpu=str(cpu),
        memory=str(memory),
        executionRoleArn=EXECUTION_ROLE_ARN,
        containerDefinitions=[{
            "name": service_name,
            "image": image_uri,
            "portMappings": [{"containerPort": container_port, "protocol": "tcp"}],
            "essential": True,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": log_group_name,
                    "awslogs-region": boto3.session.Session().region_name,
                    "awslogs-stream-prefix": service_name,
                },
            },
        }],
    )
    return resp["taskDefinition"]["taskDefinitionArn"]


def create_target_group(service_name: str, container_port: int) -> str:
    tg_name = f"{service_name}-tg"[:32]
    resp = elbv2.create_target_group(
        Name=tg_name,
        Port=container_port,
        Protocol="HTTP",
        VpcId=VPC_ID,
        TargetType="ip",
        HealthCheckPath="/",
        HealthCheckIntervalSeconds=30,
        HealthyThresholdCount=2,
        UnhealthyThresholdCount=3,
    )
    return resp["TargetGroups"][0]["TargetGroupArn"]


def next_rule_priority() -> int:
    resp = elbv2.describe_rules(ListenerArn=ALB_LISTENER_ARN)
    priorities = [int(r["Priority"]) for r in resp["Rules"] if r["Priority"] != "default"]
    return (max(priorities) + 1) if priorities else 1


def create_path_rule(service_name: str, target_group_arn: str) -> None:
    elbv2.create_rule(
        ListenerArn=ALB_LISTENER_ARN,
        Priority=next_rule_priority(),
        Conditions=[{"Field": "path-pattern", "Values": [f"/{service_name}/*", f"/{service_name}"]}],
        Actions=[{"Type": "forward", "TargetGroupArn": target_group_arn}],
    )


def create_ecs_service(service_name: str, task_definition_arn: str, target_group_arn: str,
                        container_port: int, desired_count: int) -> None:
    ecs.create_service(
        cluster=CLUSTER_NAME,
        serviceName=f"{PROJECT_NAME}-{service_name}",
        taskDefinition=task_definition_arn,
        desiredCount=desired_count,
        launchType="FARGATE",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": PRIVATE_SUBNET_IDS,
                "securityGroups": [ECS_TASKS_SG_ID],
                "assignPublicIp": "DISABLED",
            }
        },
        loadBalancers=[{
            "targetGroupArn": target_group_arn,
            "containerName": service_name,
            "containerPort": container_port,
        }],
    )


def enable_autoscaling(service_name: str, desired_count: int) -> None:
    resource_id = f"service/{CLUSTER_NAME}/{PROJECT_NAME}-{service_name}"
    aas.register_scalable_target(
        ServiceNamespace="ecs",
        ResourceId=resource_id,
        ScalableDimension="ecs:service:DesiredCount",
        MinCapacity=desired_count,
        MaxCapacity=max(desired_count * 4, 4),
    )
    aas.put_scaling_policy(
        ServiceNamespace="ecs",
        ResourceId=resource_id,
        ScalableDimension="ecs:service:DesiredCount",
        PolicyName=f"{PROJECT_NAME}-{service_name}-cpu-tracking",
        PolicyType="TargetTrackingScaling",
        TargetTrackingScalingPolicyConfiguration={
            "TargetValue": 50.0,
            "PredefinedMetricSpecification": {"PredefinedMetricType": "ECSServiceAverageCPUUtilization"},
            "ScaleInCooldown": 60,
            "ScaleOutCooldown": 60,
        },
    )


def lambda_handler(event, context):
    logger.info("Provisioning request: %s", json.dumps(event))

    service_name   = event["service_name"]
    image_uri      = event["image_uri"]
    container_port = int(event["container_port"])
    cpu            = int(event["cpu"])
    memory         = int(event["memory"])
    desired_count  = int(event["desired_count"])

    log_group_name = f"/ecs/{PROJECT_NAME}-{service_name}"

    ensure_ecr_repo(service_name)
    ensure_log_group(log_group_name)

    task_definition_arn = register_task_definition(
        service_name, image_uri, container_port, cpu, memory, log_group_name
    )
    target_group_arn = create_target_group(service_name, container_port)
    create_path_rule(service_name, target_group_arn)
    create_ecs_service(service_name, task_definition_arn, target_group_arn, container_port, desired_count)
    enable_autoscaling(service_name, desired_count)

    service_url = f"http://{ALB_DNS_NAME}/{service_name}/"
    logger.info("Provisioned %s at %s", service_name, service_url)

    return {
        "service_url": service_url,
        "task_definition_arn": task_definition_arn,
    }
