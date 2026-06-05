###############################################################################
# Step Functions — SSM Fleet Management
# Two paths based on request_type:
#   onboard → FleetOnboarder → StatusUpdater → Done
#   patch   → PatchOrchestrator → StatusUpdater → Done
###############################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${var.project}-${var.environment}-fleet-management"
  retention_in_days = 30
}

resource "aws_sfn_state_machine" "fleet_management" {
  name     = "${var.project}-${var.environment}-fleet-management"
  role_arn = var.sfn_role_arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  definition = jsonencode({
    Comment = "SSM Fleet Management - onboard or patch workflow"
    StartAt = "RouteRequest"

    States = {
      RouteRequest = {
        Type    = "Choice"
        Choices = [
          {
            Variable     = "$.request_type"
            StringEquals = "onboard"
            Next         = "OnboardInstance"
          },
          {
            Variable     = "$.request_type"
            StringEquals = "patch"
            Next         = "PatchFleet"
          }
        ]
        Default = "PatchFleet"
      }

      OnboardInstance = {
        Type     = "Task"
        Resource = var.fleet_onboarder_arn
        ResultPath = "$.onboard_result"
        Retry = [{
          ErrorEquals   = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 5
          MaxAttempts   = 2
          BackoffRate   = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "OnboardFailed"
          ResultPath  = "$.error"
        }]
        Next = "MergeOnboardResult"
      }

      MergeOnboardResult = {
        Type = "Pass"
        Parameters = {
          "ticket_id.$"          = "$.ticket_id"
          "request_type.$"       = "$.request_type"
          "instance_id.$"        = "$.instance_id"
          "automation_status.$"  = "$.onboard_result.automation_status"
          "execution_id.$"       = "$.onboard_result.execution_id"
          "compliant_count.$"    = "$.onboard_result.compliant_count"
          "non_compliant_count.$" = "$.onboard_result.non_compliant_count"
          "onboard_success.$"    = "$.onboard_result.onboard_success"
        }
        Next = "UpdateServiceNow"
      }

      PatchFleet = {
        Type     = "Task"
        Resource = var.patch_orchestrator_arn
        ResultPath = "$.patch_result"
        Retry = [{
          ErrorEquals   = ["Lambda.ServiceException", "Lambda.AWSLambdaException"]
          IntervalSeconds = 5
          MaxAttempts   = 2
          BackoffRate   = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PatchFailed"
          ResultPath  = "$.error"
        }]
        Next = "MergePatchResult"
      }

      MergePatchResult = {
        Type = "Pass"
        Parameters = {
          "ticket_id.$"         = "$.ticket_id"
          "request_type.$"      = "$.request_type"
          "patch_group.$"       = "$.patch_group"
          "operation.$"         = "$.operation"
          "automation_status.$" = "$.patch_result.automation_status"
          "execution_id.$"      = "$.patch_result.execution_id"
          "total_instances.$"   = "$.patch_result.total_instances"
          "compliant.$"         = "$.patch_result.compliant"
          "non_compliant.$"     = "$.patch_result.non_compliant"
          "missing_patches.$"   = "$.patch_result.missing_patches"
          "installed_patches.$" = "$.patch_result.installed_patches"
          "failed_patches.$"    = "$.patch_result.failed_patches"
          "compliance_pct.$"    = "$.patch_result.compliance_pct"
          "patch_success.$"     = "$.patch_result.patch_success"
        }
        Next = "UpdateServiceNow"
      }

      UpdateServiceNow = {
        Type     = "Task"
        Resource = var.status_updater_arn
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException"]
          IntervalSeconds = 5
          MaxAttempts     = 3
          BackoffRate     = 2
        }]
        Next = "Done"
      }

      OnboardFailed = {
        Type = "Pass"
        Parameters = {
          "ticket_id.$"     = "$.ticket_id"
          "request_type.$"  = "$.request_type"
          "instance_id.$"   = "$.instance_id"
          "onboard_success" = false
          "automation_status" = "Failed"
          "execution_id"    = "unknown"
          "compliant_count" = 0
          "non_compliant_count" = 0
        }
        Next = "UpdateServiceNow"
      }

      PatchFailed = {
        Type = "Pass"
        Parameters = {
          "ticket_id.$"   = "$.ticket_id"
          "request_type.$" = "$.request_type"
          "patch_group.$" = "$.patch_group"
          "operation.$"   = "$.operation"
          "patch_success" = false
          "automation_status" = "Failed"
          "execution_id"  = "unknown"
          "total_instances" = 0
          "compliant"     = 0
          "non_compliant" = 0
          "missing_patches" = 0
          "installed_patches" = 0
          "failed_patches" = 0
          "compliance_pct" = 0
        }
        Next = "UpdateServiceNow"
      }

      Done = {
        Type = "Succeed"
      }
    }
  })

  tags = { Name = "${var.project}-${var.environment}-fleet-management" }
}
