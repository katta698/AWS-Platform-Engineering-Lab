variable "name" {
  description = "Name prefix for every resource in this module."
  type        = string
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR for the consumer VPC. Nothing else lives in it."
  type        = string
  default     = "10.23.0.0/16"
}

variable "subnet_count" {
  description = "Private subnets for the client Lambda. Two for AZ spread; there is no NAT and no internet gateway."
  type        = number
  default     = 2
}

variable "service_auth_type" {
  description = <<-DESC
    AWS_IAM or NONE, on the SERVICE.

    A variable rather than a constant because test 5 flips it to NONE while
    leaving the restrictive auth policy attached, to show that the policy is
    then skipped entirely and reports state Inactive. That is the failure mode
    worth the week: the policy applies cleanly, appears in the console, and
    enforces nothing.
  DESC
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.service_auth_type)
    error_message = "service_auth_type must be AWS_IAM or NONE."
  }
}

variable "lambda_dir" {
  description = "Path to the directory holding the backend/ and client/ Lambda sources."
  type        = string
}
