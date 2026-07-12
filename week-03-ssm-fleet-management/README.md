# Week 3: SSM Fleet Management Platform

**52-Week AWS Platform Engineering Lab — Week 3 of 52**

A self-service fleet management platform where ops engineers submit a ServiceNow ticket to either onboard an EC2 instance into the managed fleet or trigger a patch run across an environment — with full compliance reporting, session audit logging, and zero manual AWS console involvement.

## Architecture

```
ServiceNow Ticket (onboard or patch)
      │
      ▼
API Gateway POST /fleet
      │
      ▼
Lambda: webhook_receiver  (validates HMAC, routes to Step Functions)
      │
      ▼
Step Functions — RouteRequest
      │
      ├─► [request_type=onboard]
      │     Lambda: fleet_onboarder
      │       ├── SSM Automation: onboard-instance document
      │       │     ├── Wait for SSM agent online
      │       │     ├── Tag instance (PatchGroup, ManagedBy)
      │       │     ├── Run baseline config via Run Command
      │       │     └── Run patch scan → collect compliance
      │       └── Returns compliance summary
      │
      └─► [request_type=patch]
            Lambda: patch_orchestrator
              ├── SSM Automation: patch-fleet document
              │     ├── Run Command: AWS-RunPatchBaseline (Scan or Install)
              │     ├── Target: all instances with PatchGroup tag
              │     └── Collect per-instance patch states
              └── Returns fleet compliance summary

Lambda: status_updater
  └── Closes ServiceNow ticket with compliance report

SSM Services Used:
  Fleet Manager   — visual fleet dashboard, instance details
  Patch Manager   — baselines, maintenance windows, compliance
  Run Command     — remote execution, no SSH
  Inventory       — software, network, OS details every 30 min
  Session Manager — audited shell access, logs to S3 + CloudWatch
  State Manager   — enforce SSM agent updates, inventory collection
  Automation      — custom onboarding and patching runbooks
```

## SSM Services Deep Dive

| Service | Purpose in this project |
|---|---|
| Fleet Manager | Visual dashboard — all instances, health status, OS details |
| Patch Manager | Baselines per OS, maintenance window (Sunday 02:00 UTC), compliance reports |
| Run Command | Execute commands across fleet without SSH — baseline config, patch operations |
| Inventory | Collect software inventory every 30 min — apps, network config, OS info |
| Session Manager | Audited shell access — every session logged to S3 + CloudWatch, no port 22 needed |
| State Manager | Associations enforce SSM agent is always up to date, inventory always running |
| Automation | Custom runbooks — onboard-instance and patch-fleet documents |

## Patch Baseline Configuration

| OS | Baseline | Classifications | Severity | Approve After |
|---|---|---|---|---|
| Amazon Linux 2023 | `fleet-mgmt-dev-amazon-linux-baseline` | Security, Bugfix | Critical, Important, Medium | 7 days |
| Windows Server | `fleet-mgmt-dev-windows-baseline` | CriticalUpdates, SecurityUpdates | Critical, Important | 7 days |

## Multi-Tenant Design

| Concern | Approach |
|---|---|
| Fleet isolation | Instances tagged with `PatchGroup` and `ManagedBy` for targeted operations |
| Session audit | Every session logged to S3 + CloudWatch with 90-day retention |
| Patch compliance | Per-instance compliance tracked in SSM, reported back to ServiceNow |
| Agent enforcement | State Manager keeps SSM agent updated every 14 days |
| Inventory | Software and network inventory collected every 30 minutes |

## Quick Start

### Prerequisites
- AWS CLI configured with admin permissions
- Terraform >= 1.10
- EC2 instances with `AmazonSSMManagedInstanceCore` IAM policy
- ServiceNow developer instance

---

### Step 1 — Configure tfvars
```bash
cd week-03-ssm-fleet-management
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars
# Edit terraform.tfvars with your values
```

---

### Step 2 — Deploy
```bash
sh scripts/deploy.sh
# EC2 instances appear in SSM Fleet Manager within ~5 min of launch
```

---

### Step 3 — Verify fleet is online (wait ~5 min after deploy)
```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,AgentVersion]" \
  --output table --region us-east-1
```

---

### Step 4 — Simulate ServiceNow patch scan request
```bash
export API_URL=$(cd terraform/environments/dev && terraform output -raw api_gateway_url)
export SECRET=$(grep webhook_secret terraform/environments/dev/terraform.tfvars | awk -F'"' '{print $2}')

BODY='{"ticket_id":"RITM0030001","request_type":"patch","patch_group":"fleet-mgmt-dev-linux","operation":"Scan","team":"platform-engineering","requested_by":"jay.katta"}'
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
curl -X POST "$API_URL" -H "Content-Type: application/json" -H "x-servicenow-signature: $SIG" -d "$BODY"
```

Wait ~2 min, then check Step Functions.

---

### Step 5 — Launch a manual EC2 (unmanaged — no PatchGroup tag)
```bash
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=fleet-mgmt-dev-private-*" \
  --query "Subnets[0].SubnetId" --output text --region us-east-1)

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=fleet-mgmt-dev-ec2-sg" \
  --query "SecurityGroups[0].GroupId" --output text --region us-east-1)

AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" \
  --output text --region us-east-1)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --iam-instance-profile Name=fleet-mgmt-dev-ec2-profile \
  --subnet-id $SUBNET_ID \
  --security-group-ids $SG_ID \
  --no-associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=manual-test-instance}]" \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --query "Instances[0].InstanceId" --output text --region us-east-1)

echo "Manual instance: $INSTANCE_ID"
```

---

### Step 6 — Simulate ServiceNow onboard request
Wait ~3 min for the manual instance to register with SSM, then run:

```bash
# Replace with your actual INSTANCE_ID from Step 5
BODY="{\"ticket_id\":\"RITM0030002\",\"request_type\":\"onboard\",\"instance_id\":\"$INSTANCE_ID\",\"team\":\"platform-engineering\",\"requested_by\":\"jay.katta\"}"
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
curl -X POST "$API_URL" -H "Content-Type: application/json" -H "x-servicenow-signature: $SIG" -d "$BODY"
```

Wait ~5 min for onboard automation to complete.

---

### Step 7 — Simulate ServiceNow patch install request
```bash
BODY='{"ticket_id":"RITM0030003","request_type":"patch","patch_group":"fleet-mgmt-dev-linux","operation":"Install","team":"platform-engineering","requested_by":"jay.katta"}'
SIG="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
curl -X POST "$API_URL" -H "Content-Type: application/json" -H "x-servicenow-signature: $SIG" -d "$BODY"
```

Wait ~10 min for patch install to complete across all instances.

---

### Step 8 — Verify compliance and check audit evidence
```bash
# Fleet-wide compliance summary
MSYS_NO_PATHCONV=1 aws ssm describe-instance-patch-states-for-patch-group \
  --patch-group fleet-mgmt-dev-linux \
  --query "InstancePatchStates[*].[InstanceId,MissingCount,InstalledCount,FailedCount]" \
  --output table --region us-east-1

# Per-instance patch detail
MSYS_NO_PATHCONV=1 aws ssm describe-instance-patches \
  --instance-id <INSTANCE_ID> \
  --filters "Key=State,Values=Installed" \
  --query "Patches[*].[Title,State,InstalledTime]" \
  --output table --region us-east-1 | head -30
```

---

### Step 9 — Start a Session Manager session (no SSH, no key pair)
```bash
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
# Type exit when done

# Check session logs in S3
aws s3 ls s3://fleet-mgmt-dev-session-logs-<YOUR_ACCOUNT_ID>/ --region us-east-1
```

---

### Step 10 — Wire ServiceNow to API Gateway

**Part A — Create Outbound REST Message**
1. Search → "Outbound REST Message" → New
2. Name: `AWS Fleet Management`
3. Endpoint: `<your api_gateway_url>`
4. Save → HTTP Methods → New
5. Name: `fleet`, HTTP Method: `POST`
6. Content-Type header: `application/json`
7. Leave the request body empty here — the Business Rule in Part C builds it
   dynamically and sets it via `setRequestBody()`, because the HMAC signature
   (added below, fixed 2026-07-12) must be computed over the *exact* bytes
   sent. A statically templated body here could serialize slightly
   differently than the script-computed HMAC expects, breaking signature
   validation on the Lambda side.
8. Search → "System Properties" → New. Name: `x_platform_lab.webhook_secret`
   (shared across every ServiceNow-driven week — only set this once, ever;
   skip this step if it already exists from another week),
   Type: `password (2 way encrypted)`, Value: the same secret you set as
   `webhook_secret`/`WEBHOOK_SECRET` for this week's deploy config. The
   Business Rule in Part C reads this via `gs.getProperty()` — never
   hardcode the secret directly in the script.

**Part B — Create Service Catalog Item**
1. Catalog Builder → New Item
2. Name: `Fleet Management Request`
3. Set Catalogs → Service Catalog, Category → Infrastructure
4. Add Questions (use Choice/Dropdown for request_type and operation, Text for the rest):

| Question Label | Name | Type | Mandatory |
|---|---|---|---|
| Request Type | `request_type` | Choice — `onboard`, `patch` | Yes |
| Instance ID | `instance_id` | Text | No |
| Patch Group | `patch_group` | Text | No |
| Operation | `operation` | Choice — `Scan`, `Install` | No |
| Team | `team` | Text | Yes |

**Part C — Create Business Rule**

> **Fixed 2026-07-12**: this script previously sent the request unsigned —
> `webhook_receiver`'s HMAC validation would have rejected every real
> submission with `401 Unauthorized`. **Fixed again same day**: the first fix
> used `HexUtil.convertByteArrayToHex()`, which turned out not to actually
> exist in this scripting context — confirmed via a real `"HexUtil" is not
> defined` error hit while testing Week 9's identical script against a live
> instance. Replaced with a plain-JavaScript byte-to-hex loop that doesn't
> depend on any ServiceNow-specific class. Also updated to the shared
> `x_platform_lab.webhook_secret` system property instead of a
> per-week-namespaced one.

1. Search → Business Rules → New
2. Name: `Trigger Fleet Management`
3. Table: `sc_req_item`, When: `after`, Insert: `true`
4. Condition: `current.cat_item.name == 'Fleet Management Request'`
5. Script:
```javascript
(function executeRule(current, previous) {
  try {
    var body = JSON.stringify({
      ticket_id:    current.number.toString(),
      request_type: current.variables.request_type.toString(),
      instance_id:  current.variables.instance_id.toString(),
      patch_group:  current.variables.patch_group.toString(),
      operation:    current.variables.operation.toString() || 'Scan',
      team:         current.variables.team.toString(),
      requested_by: current.opened_by.user_name.toString()
    });

    var secret = gs.getProperty('x_platform_lab.webhook_secret');

    var mac = new GlideCertificateEncryption();
    var keyBase64 = GlideStringUtil.base64Encode(secret);
    var macBase64 = mac.generateMac(keyBase64, 'HmacSHA256', body);
    var macBytes  = GlideStringUtil.base64DecodeAsBytes(macBase64);

    var macHex = '';
    for (var i = 0; i < macBytes.length; i++) {
      var b = macBytes[i] & 0xFF;
      macHex += (b < 16 ? '0' : '') + b.toString(16);
    }
    var signature = 'sha256=' + macHex;

    var r = new sn_ws.RESTMessageV2('AWS Fleet Management', 'fleet');
    r.setRequestBody(body);
    r.setRequestHeader('x-servicenow-hmac', signature);
    var response = r.execute();
    gs.info('Fleet management triggered: ' + response.getStatusCode());
  } catch(ex) {
    gs.error('Fleet management failed: ' + ex.message);
  }
})(current, previous);
```

### Step 11 — Set up GitHub Actions secrets
```bash
# All secrets already set from Week 2 — these are new/updated for Week 3
gh secret set AWS_ROLE_ARN            --body "arn:aws:iam::<YOUR_ACCOUNT_ID>:role/github-actions-dev-deploy-role"
gh secret set WEBHOOK_SECRET          --body "your_webhook_secret"
gh secret set SERVICENOW_INSTANCE_URL --body "https://devXXXXX.service-now.com"
gh secret set SERVICENOW_USERNAME     --body "admin"
gh secret set SERVICENOW_PASSWORD     --body "your_sn_password"
gh secret set ALERT_EMAIL             --body "your-email@example.com"
```

### Cleanup
```bash
sh scripts/cleanup.sh
# Destroys all infrastructure including EC2 fleet, SSM documents, session logs bucket
```

## Cost

| Resource | Cost/month (if left running) |
|---|---|
| EC2 t3.micro x2 | ~$17 |
| SSM (no charge for core features) | $0 |
| S3 session logs | ~$0.02 |
| Lambda (minimal traffic) | ~$0 |
| CloudWatch | ~$2 |
| VPC endpoints x4 | ~$29 |
| **Total** | **~$48/month** |
| **Destroyed between sessions** | **$0** |

> Note: VPC endpoints are the biggest cost driver. For the lab you can remove them and use a NAT Gateway instead, but VPC endpoints are the enterprise pattern — no internet route for SSM traffic.

## Security Patterns

- **No SSH anywhere** — Session Manager is the only shell access, every session is logged
- **IMDSv2 enforced** — Launch template requires HTTP tokens (prevents SSRF attacks)
- **Least-privilege IAM** — Lambda can only call SSM actions, scoped to this project's resources
- **Patch baselines** — Only approved patch classifications allowed, reject action blocks all others
- **Session audit trail** — S3 + CloudWatch logs retained 90 days for compliance
- **State Manager** — Configuration drift corrected automatically, agent always current
- **OIDC for CI/CD** — No static AWS credentials in GitHub

## Troubleshooting

### SSM / Fleet

| Error | Cause | Fix |
|---|---|---|
| Instance not appearing in Fleet Manager | SSM agent not running or IAM role missing | Verify `AmazonSSMManagedInstanceCore` attached to EC2 role; check `systemctl status amazon-ssm-agent` via console |
| `TargetNotConnected` on Run Command | Instance offline or SSM agent stopped | Check Fleet Manager → instance status; restart agent via EC2 user data |
| VPC endpoint not resolving | Private DNS not enabled on endpoint | Ensure `private_dns_enabled = true` on interface endpoints |
| Session Manager session times out after 20 min | Idle timeout set in session preferences | Configured intentionally — re-connect or increase `idleSessionTimeout` |
| Patch compliance shows `Unknown` | Scan not run yet | Run `Scan` operation first before checking compliance |
| `PatchGroup` tag not found | EC2 instance launched before tag was applied | Re-tag instance or terminate and let ASG launch fresh instance |

### Terraform

| Error | Cause | Fix |
|---|---|---|
| `InvalidDocument` on SSM document | YAML formatting issue in Automation document | Check indentation — SSM Automation YAML is strict |
| `EntityAlreadyExists` on patch baseline | Previous deploy left baseline | Run cleanup first or import existing baseline into state |
| `default_patch_baseline` conflict | AWS has default baselines per OS | Terraform may need `terraform import` if baselines already exist |
| SSM Parameter path rejected — `can't be prefixed with "ssm"` | Project name starts with `ssm` — AWS rejects `/ssm-*/` parameter paths | Project renamed to `fleet-mgmt` — never use `ssm` as project name prefix |
| VPC endpoint AZ error — `does not support the availability zone` | Some us-east-1 AZs (e.g. us-east-1e) don't support SSM interface endpoints | Use `aws_vpc_endpoint_service` data source to filter supported AZs before creating subnets |
| API Gateway 400 — `AWS ARN for integration must contain path or action` | `AWS_PROXY` uri was set to raw Lambda ARN | URI must be `arn:aws:apigateway:{region}:lambda:path/2015-03-31/functions/{lambda_arn}/invocations` |
| Lambda Permission 404 — `Function not found` | API Gateway module ran before Lambda was created | Add `depends_on = [module.lambda]` to the `api_gateway` module call in `main.tf` |
| SSM Automation document — `CommandId is conflicting with reserved output names` | `CommandId` is reserved in SSM Automation | Rename custom output to `PatchCommandId` |
| ASG launch fails — `Volume of size 20GB is smaller than snapshot, expect size >= 30GB` | AL2023 AMI snapshot requires minimum 30GB | Set `volume_size = 30` in launch template block device mapping |
| Step Functions — `AccessDeniedException: not authorized to access the Log Destination` | Step Functions role missing full CloudWatch log delivery permissions | Add all log delivery actions: `GetLogDelivery`, `UpdateLogDelivery`, `DeleteLogDelivery`, `ListLogDeliveries`, `PutResourcePolicy` |
| `terraform destroy` fails mid-run — state lock stuck | Internet dropped during destroy, lock file left in S3 | Run `terraform force-unlock -force <LOCK_ID>` — get lock ID from `aws s3 cp s3://jay-terraformstate-bucket/.../terraform.tfstate.tflock -` |
| `DependencyViolation` on security group during destroy | Manually created EC2 still running in the subnet | Terminate manual EC2 instances first: `aws ec2 terminate-instances --instance-ids <id>` then re-run destroy |
| HCL semicolons — `The ";" character is not valid` | Terraform variables written with semicolons as separators | HCL requires newlines between attributes — each attribute on its own line |

### GitHub Actions

| Error | Cause | Fix |
|---|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | OIDC trust policy wrong repo or environment | See Week 2 troubleshooting — same fix applies |
| `Unsupported argument: use_lockfile` | Terraform < 1.10 | Workflow uses 1.10.5 — check TF_VERSION in workflow file |
