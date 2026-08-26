variable "aws_region" {
  description = <<-EOT
    Region for the build.

    DevOps Agent is not available everywhere. At GA (2026-03-31) it launched in
    six regions: us-east-1, us-west-2, eu-central-1, eu-west-1, ap-southeast-2
    and ap-northeast-1. us-east-1 is used here because that is where the rest of
    this lab's estate lives, including Week 15's organization trail, which is
    the ground truth the agent's conclusions get graded against.
  EOT
  type        = string
  default     = "us-east-1"

  validation {
    condition = contains([
      "us-east-1", "us-west-2", "eu-central-1",
      "eu-west-1", "ap-southeast-2", "ap-northeast-1",
    ], var.aws_region)
    error_message = "DevOps Agent is only available in the six GA regions; pick one of those."
  }
}

variable "environment" {
  description = "Environment name, used in tags."
  type        = string
  default     = "dev"
}

variable "servicenow_instance_url" {
  description = <<-EOT
    ServiceNow instance the agent files findings into.

    Must match ^https://[a-zA-Z0-9-]+\.service-now\.com/?$ -- that pattern is
    enforced by the CloudFormation schema, not just by convention.

    A ServiceNow developer instance HIBERNATES after roughly ten days without
    use and stops answering. Wake it before an apply, or the service
    registration fails in a way that looks like a credentials problem.
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://[a-zA-Z0-9-]+\\.service-now\\.com/?$", var.servicenow_instance_url))
    error_message = "Must be https://<instance>.service-now.com with no path."
  }
}

variable "servicenow_oauth_client_id" {
  description = <<-EOT
    OAuth client ID from ServiceNow.

    Created in ServiceNow, not in AWS: System OAuth > Application Registry >
    Create an OAuth API endpoint for external clients. There is no Terraform
    path for this -- it is a documented manual prerequisite, the same shape as
    Week 6's SCP policy-type enablement and Week 15's CloudTrail trusted access.
  EOT
  type        = string
}

variable "servicenow_oauth_client_secret" {
  description = "OAuth client secret from the same ServiceNow application registry entry."
  type        = string
  sensitive   = true
}

variable "servicenow_instance_id" {
  description = <<-EOT
    SHORT ServiceNow instance name -- "dev388443", not the full URL.

    Carried separately from servicenow_instance_url on purpose. Registration
    takes the URL and the association takes the bare name, and passing the URL
    to the association fails with

      400 GeneralServiceException: instanceId '<url>' does not match the
      registered ServiceNow instance

    which reads as a mismatch between two things that do in fact match. Deriving
    one from the other in Terraform would work, but keeping them as two explicit
    inputs is what makes the asymmetry visible to whoever reads this next.
  EOT
  type        = string
}

variable "idc_instance_arn" {
  description = <<-EOT
    IAM Identity Center instance ARN for Operator App sign-in.

    Null uses IAM auth, which is the shorter path and what AWS's sample does.
    Supplying the Week 7 Identity Center instance switches to SSO, so agent
    actions are attributable to named people rather than to a role.
  EOT
  type        = string
  default     = null
}
