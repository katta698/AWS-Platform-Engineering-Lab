# Week 03 — SSM Fleet Management: Command Reference

All commands for testing, validating, and operating the fleet management platform.
Set these variables once per session before running any commands below.

```bash
# ── Session variables — set these first ───────────────────────────────────────
export AWS_REGION="us-east-1"
export STATE_MACHINE_ARN="arn:aws:states:us-east-1:684346483786:stateMachine:fleet-mgmt-dev-fleet-management"
export WINDOW_ID="mw-0a0c3026327390e0f"
export API_URL="https://h42fgi4und.execute-api.us-east-1.amazonaws.com/dev/fleet"
export PATCH_GROUP="fleet-mgmt-dev-linux"
export PROJECT="fleet-mgmt"
export ENV="dev"

cd week-03-ssm-fleet-management/terraform/environments/dev
export SECRET=$(grep webhook_secret terraform.tfvars | awk -F'"' '{print $2}')
```

---

## 1. Fleet Visibility

### List all managed instances
```bash
aws ssm describe-instance-information \
  --filters "Key=tag:ManagedBy,Values=${PROJECT}-${ENV}" \
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,AgentVersion]" \
  --output table --region $AWS_REGION
```

### List ALL instances SSM knows about (including unmanaged)
```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,ComputerName]" \
  --output table --region $AWS_REGION
```

### Check a specific instance SSM status
```bash
INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,AgentVersion]" \
  --output table --region $AWS_REGION
```

### Check instance tags
```bash
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$INSTANCE_ID" \
  --query "Tags[*].[Key,Value]" \
  --output table --region $AWS_REGION
```

### List all EC2 instances with their state
```bash
aws ec2 describe-instances \
  --filters "Name=tag:ManagedBy,Values=${PROJECT}-${ENV}" \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name,LaunchTime,PrivateIpAddress]" \
  --output table --region $AWS_REGION
```

---

## 2. Patch Compliance

### Fleet-wide compliance summary (all instances in patch group)
```bash
aws ssm describe-instance-patch-states-for-patch-group \
  --patch-group $PATCH_GROUP \
  --query "InstancePatchStates[*].[InstanceId,PatchGroup,MissingCount,InstalledCount,FailedCount,ComplianceProfile]" \
  --output table --region $AWS_REGION
```

### Compliance summary including reboot info
```bash
aws ssm describe-instance-patch-states-for-patch-group \
  --patch-group $PATCH_GROUP \
  --query "InstancePatchStates[*].[InstanceId,MissingCount,InstalledCount,FailedCount,RebootOption,LastNoRebootInstallOperationTime]" \
  --output table --region $AWS_REGION
```

### Per-instance patch detail (every patch name, state, install time)
```bash
aws ssm describe-instance-patches \
  --instance-id $INSTANCE_ID \
  --query "Patches[*].[Title,State,InstalledTime,Severity]" \
  --output table --region $AWS_REGION
```

### Show only MISSING patches for an instance
```bash
aws ssm describe-instance-patches \
  --instance-id $INSTANCE_ID \
  --filters "Key=State,Values=Missing" \
  --query "Patches[*].[Title,Severity,Classification]" \
  --output table --region $AWS_REGION
```

### Show only FAILED patches for an instance
```bash
aws ssm describe-instance-patches \
  --instance-id $INSTANCE_ID \
  --filters "Key=State,Values=Failed" \
  --query "Patches[*].[Title,Severity]" \
  --output table --region $AWS_REGION
```

### Check patch compliance state for a single instance
```bash
aws ssm describe-instance-patch-states \
  --instance-ids $INSTANCE_ID \
  --region $AWS_REGION
```

---

## 3. Simulate ServiceNow Requests (curl tests)

### Patch — Scan (compliance check only, no changes)
```bash
BODY="{\"ticket_id\":\"RITM00300XX\",\"request_type\":\"patch\",\"patch_group\":\"${PATCH_GROUP}\",\"operation\":\"Scan\",\"team\":\"platform-engineering\",\"requested_by\":\"jay.katta\"}"
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "x-servicenow-signature: $SIG" \
  -d "$BODY"
```

### Patch — Install (actually patches all instances, may reboot)
```bash
BODY="{\"ticket_id\":\"RITM00300XX\",\"request_type\":\"patch\",\"patch_group\":\"${PATCH_GROUP}\",\"operation\":\"Install\",\"team\":\"platform-engineering\",\"requested_by\":\"jay.katta\"}"
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "x-servicenow-signature: $SIG" \
  -d "$BODY"
```

### Onboard — bring a new/manual instance into the fleet
```bash
BODY="{\"ticket_id\":\"RITM00300XX\",\"request_type\":\"onboard\",\"instance_id\":\"$INSTANCE_ID\",\"team\":\"platform-engineering\",\"requested_by\":\"jay.katta\"}"
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "x-servicenow-signature: $SIG" \
  -d "$BODY"
```

> **Note:** Change `RITM00300XX` to a unique ticket number each time — Step Functions rejects duplicate execution names.

---

## 4. Step Functions

### List all executions (audit trail)
```bash
aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE_ARN \
  --query "executions[*].[name,status,startDate]" \
  --output table --region $AWS_REGION
```

### Check status of a specific execution
```bash
EXECUTION_ARN="arn:aws:states:us-east-1:684346483786:execution:fleet-mgmt-dev-fleet-management:patch-RITM0030001"
aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --query "[status, startDate, stopDate]" \
  --output table --region $AWS_REGION
```

### Get full output of a completed execution (compliance report)
```bash
aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --query "output" \
  --output text --region $AWS_REGION
```

### Get execution history (step by step detail)
```bash
aws stepfunctions get-execution-history \
  --execution-arn $EXECUTION_ARN \
  --query "events[-5:].{type:type,details:stateExitedEventDetails}" \
  --output json --region $AWS_REGION
```

---

## 5. Manual SSM Commands (without ServiceNow)

### Manually trigger patch scan on specific instance
```bash
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name AWS-RunPatchBaseline \
  --parameters Operation=Scan \
  --region $AWS_REGION \
  --query "Command.CommandId" \
  --output text
```

### Manually trigger patch scan across entire patch group
```bash
aws ssm send-command \
  --targets "Key=tag:PatchGroup,Values=${PATCH_GROUP}" \
  --document-name AWS-RunPatchBaseline \
  --parameters Operation=Scan \
  --region $AWS_REGION \
  --query "Command.CommandId" \
  --output text
```

### Manually trigger patch install across entire patch group
```bash
aws ssm send-command \
  --targets "Key=tag:PatchGroup,Values=${PATCH_GROUP}" \
  --document-name AWS-RunPatchBaseline \
  --parameters Operation=Install \
  --region $AWS_REGION \
  --query "Command.CommandId" \
  --output text
```

### Check Run Command result
```bash
COMMAND_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
aws ssm get-command-invocation \
  --command-id $COMMAND_ID \
  --instance-id $INSTANCE_ID \
  --query "[Status,StatusDetails,ResponseCode]" \
  --output table --region $AWS_REGION
```

### Run arbitrary shell command on an instance (no SSH)
```bash
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name AWS-RunShellScript \
  --parameters commands=["uptime","df -h","free -m"] \
  --query "Command.CommandId" \
  --output text --region $AWS_REGION
```

### Start interactive Session Manager session (no SSH, no key pair)
```bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --region $AWS_REGION
```

---

## 6. SSM Inventory

### List software installed on an instance
```bash
aws ssm list-inventory-entries \
  --instance-id $INSTANCE_ID \
  --type-name "AWS:Application" \
  --query "Entries[*].[Name,Version,Publisher]" \
  --output table --region $AWS_REGION
```

### Check network config inventory
```bash
aws ssm list-inventory-entries \
  --instance-id $INSTANCE_ID \
  --type-name "AWS:Network" \
  --output table --region $AWS_REGION
```

### List all inventory types available for an instance
```bash
aws ssm list-inventory-entries \
  --instance-id $INSTANCE_ID \
  --type-name "AWS:InstanceInformation" \
  --output json --region $AWS_REGION
```

---

## 7. Maintenance Window

### Check maintenance window details
```bash
aws ssm describe-maintenance-windows \
  --filters "Key=Name,Values=${PROJECT}-${ENV}-weekly-patching" \
  --query "WindowIdentities[*].[WindowId,Name,Schedule,Duration,NextExecutionTime]" \
  --output table --region $AWS_REGION
```

### Check maintenance window execution history
```bash
WINDOW_ID="mw-0a0c3026327390e0f"
aws ssm describe-maintenance-window-executions \
  --window-id $WINDOW_ID \
  --query "WindowExecutions[*].[WindowExecutionId,Status,StartTime,EndTime]" \
  --output table --region $AWS_REGION
```

### Check which instances are targeted by the maintenance window
```bash
aws ssm describe-maintenance-window-targets \
  --window-id $WINDOW_ID \
  --query "Targets[*].[WindowTargetId,ResourceType,Targets]" \
  --output json --region $AWS_REGION
```

---

## 8. Patch Logs in S3

### List patch run logs
```bash
aws s3 ls s3://fleet-mgmt-dev-session-logs-684346483786/patch-runs/ \
  --region $AWS_REGION
```

### List session logs
```bash
aws s3 ls s3://fleet-mgmt-dev-session-logs-684346483786/sessions/ \
  --region $AWS_REGION
```

### List onboarding logs
```bash
aws s3 ls s3://fleet-mgmt-dev-session-logs-684346483786/onboarding/ \
  --region $AWS_REGION
```

---

## 9. Lambda

### Check Lambda function configuration
```bash
aws lambda get-function-configuration \
  --function-name ${PROJECT}-${ENV}-patch-orchestrator \
  --query "[FunctionName,Runtime,Timeout,MemorySize,LastModified]" \
  --output table --region $AWS_REGION
```

### Tail Lambda logs live
```bash
aws logs tail /aws/lambda/${PROJECT}-${ENV}-patch-orchestrator \
  --follow --region $AWS_REGION
```

### Get recent Lambda log events
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/${PROJECT}-${ENV}-patch-orchestrator \
  --start-time $(date -d '1 hour ago' +%s000) \
  --query "events[*].[timestamp,message]" \
  --output text --region $AWS_REGION
```

---

## 10. Create a Manual EC2 for Testing

### Get subnet and security group
```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${PROJECT}-${ENV}-private-*" \
  --query "Subnets[0].SubnetId" \
  --output text --region $AWS_REGION

aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=${PROJECT}-${ENV}-ec2-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text --region $AWS_REGION
```

### Launch manual test instance
```bash
SUBNET_ID="subnet-xxxxxxxxxxxxxxxxx"
SG_ID="sg-xxxxxxxxxxxxxxxxx"

aws ec2 run-instances \
  --image-id $(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
    --query "sort_by(Images,&CreationDate)[-1].ImageId" \
    --output text --region $AWS_REGION) \
  --instance-type t3.micro \
  --iam-instance-profile Name=${PROJECT}-${ENV}-ec2-profile \
  --subnet-id $SUBNET_ID \
  --security-group-ids $SG_ID \
  --no-associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=manual-test-instance}]" \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --query "Instances[0].InstanceId" \
  --output text --region $AWS_REGION
```

### Terminate a test instance when done
```bash
aws ec2 terminate-instances \
  --instance-ids $INSTANCE_ID \
  --region $AWS_REGION
```

---

## 11. Cleanup

### Destroy all Week 03 infrastructure
```bash
cd week-03-ssm-fleet-management
sh scripts/cleanup.sh
```

### Redeploy from scratch
```bash
sh scripts/deploy.sh
```
