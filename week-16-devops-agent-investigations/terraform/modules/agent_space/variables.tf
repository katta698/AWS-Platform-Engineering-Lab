variable "name" {
  description = "Name of the agent space. The only required property on the resource."
  type        = string
}

variable "description" {
  description = <<-EOT
    What this agent space is for.

    Worth filling in rather than leaving blank: an agent space is a standing
    grant of visibility over part of an estate, and the next person to find it
    should be able to tell why it exists without reading the Terraform.
  EOT
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = <<-EOT
    Customer-managed KMS key for encrypting agent space data.

    CREATE-ONLY: CloudFormation lists /properties/KmsKeyArn under
    createOnlyProperties, so changing it replaces the agent space rather than
    updating it in place. Null means AWS-owned encryption.
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the agent space, as a normal Terraform map (converted to the key/value list awscc expects)."
  type        = map(string)
  default     = {}
}

variable "operator_app_role_arn" {
  description = <<-EOT
    Role the Operator App assumes on behalf of a signed-in human.

    Required in practice even though the schema marks operator_app optional:
    without an operator app there is no way to talk to the agent. The CLI can
    create a chat execution but has no operation for sending it a message --
    verified against the API on 2026-08-26, create-chat accepts only
    agentSpaceId, userId and userType. Interaction happens in the web UI.
  EOT
  type        = string
}

variable "idc_instance_arn" {
  description = <<-EOT
    IAM Identity Center instance ARN, to authenticate Operator App users through
    SSO instead of IAM.

    Null selects IAM auth, which is what AWS's own Terraform sample uses and the
    shorter path. Setting this selects IDC, which is what a real team would want:
    named humans signing in through the same directory they use everywhere else,
    so an agent action is attributable to a person. Week 7 built the Identity
    Center instance this would point at.
  EOT
  type        = string
  default     = null
}
