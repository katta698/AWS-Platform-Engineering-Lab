###############################################################################
# SSM Platform Module
# - Patch baselines (Amazon Linux 2023 + Windows Server)
# - Maintenance windows
# - Patch groups
# - State Manager associations (baseline config enforcement)
# - Inventory collection
# - Session Manager (logs to S3 + CloudWatch)
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── S3 bucket for Session Manager logs ───────────────────────────────────────
resource "aws_s3_bucket" "session_logs" {
  bucket        = "${var.project}-${var.environment}-session-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "${var.project}-${var.environment}-session-logs" }
}

resource "aws_s3_bucket_versioning" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "session_logs" {
  bucket                  = aws_s3_bucket.session_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── CloudWatch log group for Session Manager ──────────────────────────────────
resource "aws_cloudwatch_log_group" "sessions" {
  name              = "/aws/ssm/${var.project}-${var.environment}/sessions"
  retention_in_days = 90
}

# ── Session Manager preferences ───────────────────────────────────────────────
resource "aws_ssm_document" "session_preferences" {
  name            = "${var.project}-${var.environment}-session-preferences"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences - audit logging enabled"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = aws_s3_bucket.session_logs.id
      s3KeyPrefix                 = "sessions/"
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      shellProfile = {
        linux   = "exec bash\nexport HISTFILE=/var/log/.bash_history_ssm\nexport HISTTIMEFORMAT='%F %T '"
        windows = ""
      }
    }
  })
}

# ── Patch baseline — Amazon Linux 2023 ───────────────────────────────────────
resource "aws_ssm_patch_baseline" "amazon_linux" {
  name             = "${var.project}-${var.environment}-amazon-linux-baseline"
  description      = "Patch baseline for Amazon Linux 2023 - security and bugfix patches"
  operating_system = "AMAZON_LINUX_2023"

  approval_rule {
    approve_after_days  = 7
    compliance_level    = "HIGH"
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important", "Medium"]
    }
  }

  approved_patches_compliance_level    = "HIGH"
  rejected_patches_action              = "BLOCK"
  approved_patches_enable_non_security = false

  tags = { Name = "${var.project}-${var.environment}-al2023-baseline" }
}

# ── Patch baseline — Windows Server ──────────────────────────────────────────
resource "aws_ssm_patch_baseline" "windows" {
  name             = "${var.project}-${var.environment}-windows-baseline"
  description      = "Patch baseline for Windows Server - critical and security updates"
  operating_system = "WINDOWS"

  approval_rule {
    approve_after_days = 7
    compliance_level   = "HIGH"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["CriticalUpdates", "SecurityUpdates"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  approved_patches_compliance_level = "HIGH"
  rejected_patches_action           = "BLOCK"

  tags = { Name = "${var.project}-${var.environment}-windows-baseline" }
}

# ── Register baselines as default for their OS ────────────────────────────────
resource "aws_ssm_default_patch_baseline" "amazon_linux" {
  baseline_id      = aws_ssm_patch_baseline.amazon_linux.id
  operating_system = aws_ssm_patch_baseline.amazon_linux.operating_system
}

resource "aws_ssm_default_patch_baseline" "windows" {
  baseline_id      = aws_ssm_patch_baseline.windows.id
  operating_system = aws_ssm_patch_baseline.windows.operating_system
}

# ── Patch groups ──────────────────────────────────────────────────────────────
resource "aws_ssm_patch_group" "amazon_linux" {
  baseline_id = aws_ssm_patch_baseline.amazon_linux.id
  patch_group = "${var.project}-${var.environment}-linux"
}

resource "aws_ssm_patch_group" "windows" {
  baseline_id = aws_ssm_patch_baseline.windows.id
  patch_group = "${var.project}-${var.environment}-windows"
}

# ── Maintenance window — weekly Sunday 02:00 UTC ──────────────────────────────
resource "aws_ssm_maintenance_window" "weekly" {
  name              = "${var.project}-${var.environment}-weekly-patching"
  description       = "Weekly patch window - Sunday 02:00 UTC, 2 hour duration"
  schedule          = "cron(0 2 ? * SUN *)"
  duration          = 2
  cutoff            = 1
  allow_unassociated_targets = false

  tags = { Name = "${var.project}-${var.environment}-weekly-patch-window" }
}

# ── Maintenance window target — all managed instances in patch group ───────────
resource "aws_ssm_maintenance_window_target" "linux_fleet" {
  window_id     = aws_ssm_maintenance_window.weekly.id
  name          = "linux-fleet"
  description   = "All Linux instances in patch group"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${var.project}-${var.environment}-linux"]
  }
}

# ── Maintenance window task — run patch install ───────────────────────────────
resource "aws_ssm_maintenance_window_task" "patch_install" {
  window_id        = aws_ssm_maintenance_window.weekly.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = var.maintenance_window_role_arn
  max_concurrency  = "50%"
  max_errors       = "20%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.linux_fleet.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds  = 3600
      comment          = "Weekly patch install - ${var.project}-${var.environment}"
      output_s3_bucket = aws_s3_bucket.session_logs.id
      output_s3_key_prefix = "patch-logs/"

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

# ── State Manager — inventory collection every 30 min ────────────────────────
resource "aws_ssm_association" "inventory" {
  name             = "AWS-GatherSoftwareInventory"
  association_name = "${var.project}-${var.environment}-inventory"
  schedule_expression = "rate(30 minutes)"

  targets {
    key    = "tag:ManagedBy"
    values = ["${var.project}-${var.environment}"]
  }

  parameters = {
    applications                    = "Enabled"
    awsComponents                   = "Enabled"
    customInventory                 = "Enabled"
    instanceDetailedInformation     = "Enabled"
    networkConfig                   = "Enabled"
    services                        = "Enabled"
    windowsRoles                    = "Disabled"
    windowsUpdates                  = "Disabled"
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.session_logs.id
    s3_key_prefix  = "inventory/"
  }
}

# ── State Manager — enforce SSM agent is up to date ──────────────────────────
resource "aws_ssm_association" "update_ssm_agent" {
  name             = "AWS-UpdateSSMAgent"
  association_name = "${var.project}-${var.environment}-update-ssm-agent"
  schedule_expression = "rate(14 days)"

  targets {
    key    = "tag:ManagedBy"
    values = ["${var.project}-${var.environment}"]
  }
}

# ── SSM Automation document — instance onboarding ────────────────────────────
resource "aws_ssm_document" "onboard_instance" {
  name            = "${var.project}-${var.environment}-onboard-instance"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: '0.3'
    description: 'Onboard EC2 instance into SSM managed fleet - apply baseline config, enable inventory, tag instance'
    assumeRole: '{{ AutomationAssumeRole }}'
    parameters:
      InstanceId:
        type: String
        description: 'EC2 instance ID to onboard'
      Environment:
        type: String
        description: 'Environment name (dev/staging/prod)'
        default: '${var.environment}'
      AutomationAssumeRole:
        type: String
        description: 'IAM role ARN for the automation'
    mainSteps:
      - name: WaitForSSMAgent
        action: 'aws:waitForAwsResourceProperty'
        inputs:
          Service: ssm
          Api: DescribeInstanceInformation
          Filters:
            - Key: InstanceIds
              Values:
                - '{{ InstanceId }}'
          PropertySelector: '$.InstanceInformationList[0].PingStatus'
          DesiredValues:
            - Online
        timeoutSeconds: 300

      - name: ApplyPatchGroupTag
        action: 'aws:executeAwsApi'
        inputs:
          Service: ec2
          Api: CreateTags
          Resources:
            - '{{ InstanceId }}'
          Tags:
            - Key: PatchGroup
              Value: '${var.project}-${var.environment}-linux'
            - Key: ManagedBy
              Value: '${var.project}-${var.environment}'
            - Key: OnboardedAt
              Value: '{{ global:DATE_TIME }}'

      - name: RunBaselineConfig
        action: 'aws:runCommand'
        inputs:
          DocumentName: AWS-RunShellScript
          InstanceIds:
            - '{{ InstanceId }}'
          Parameters:
            commands:
              - 'sudo yum update -y --security'
              - 'sudo systemctl enable amazon-ssm-agent'
              - 'sudo systemctl start amazon-ssm-agent'
              - 'echo "Instance onboarded by SSM Fleet Manager at $(date)" | sudo tee /etc/ssm-onboarded'
          OutputS3BucketName: '${aws_s3_bucket.session_logs.id}'
          OutputS3KeyPrefix: 'onboarding/{{ InstanceId }}/'

      - name: RunPatchScan
        action: 'aws:runCommand'
        inputs:
          DocumentName: AWS-RunPatchBaseline
          InstanceIds:
            - '{{ InstanceId }}'
          Parameters:
            Operation: Scan
          OutputS3BucketName: '${aws_s3_bucket.session_logs.id}'
          OutputS3KeyPrefix: 'patch-scan/{{ InstanceId }}/'

      - name: GetComplianceSummary
        action: 'aws:executeAwsApi'
        inputs:
          Service: ssm
          Api: ListComplianceSummaries
          Filters:
            - Key: InstanceId
              Values:
                - '{{ InstanceId }}'
        outputs:
          - Name: ComplianceItems
            Selector: '$.ComplianceSummaryItems'
            Type: MapList
  YAML
}

# ── SSM Automation document — on-demand patch run ────────────────────────────
resource "aws_ssm_document" "patch_fleet" {
  name            = "${var.project}-${var.environment}-patch-fleet"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<-YAML
    schemaVersion: '0.3'
    description: 'Run patch scan or install across the managed fleet, return compliance summary'
    assumeRole: '{{ AutomationAssumeRole }}'
    parameters:
      Operation:
        type: String
        description: 'Scan or Install'
        default: 'Scan'
        allowedValues:
          - Scan
          - Install
      PatchGroup:
        type: String
        description: 'Patch group to target'
        default: '${var.project}-${var.environment}-linux'
      AutomationAssumeRole:
        type: String
        description: 'IAM role ARN for the automation'
    mainSteps:
      - name: RunPatchOperation
        action: 'aws:runCommand'
        inputs:
          DocumentName: AWS-RunPatchBaseline
          Targets:
            - Key: tag:PatchGroup
              Values:
                - '{{ PatchGroup }}'
          Parameters:
            Operation: '{{ Operation }}'
            RebootOption: RebootIfNeeded
          MaxConcurrency: '50%'
          MaxErrors: '20%'
          OutputS3BucketName: '${aws_s3_bucket.session_logs.id}'
          OutputS3KeyPrefix: 'patch-runs/{{ Operation }}/'
        outputs:
          - Name: PatchCommandId
            Selector: '$.CommandId'
            Type: String

      - name: GetPatchCompliance
        action: 'aws:executeAwsApi'
        inputs:
          Service: ssm
          Api: DescribeInstancePatchStatesForPatchGroup
          PatchGroup: '{{ PatchGroup }}'
        outputs:
          - Name: PatchStates
            Selector: '$.InstancePatchStates'
            Type: MapList
  YAML
}
