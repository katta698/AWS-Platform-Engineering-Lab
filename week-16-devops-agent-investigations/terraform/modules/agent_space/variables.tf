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
