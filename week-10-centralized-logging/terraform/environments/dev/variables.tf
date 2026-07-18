variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "week10-central-logging"
}

variable "source_account_id" {
  description = "Member account that produces logs (the spoke). Set in HCP workspace variables — not committed."
  type        = string
}

variable "source_role_name" {
  description = "Role in the source account the management account assumes to deploy spoke resources."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "alert_email" {
  description = "Email address subscribed to the error alarm topic. Set in HCP workspace variables — not committed."
  type        = string
  sensitive   = true
}

variable "log_group_base" {
  description = "Prefix for the platform's application log groups; the centralization rule copies everything under it."
  type        = string
  default     = "/platform-lab/week10"
}
