variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "service_auth_type" {
  description = <<-DESC
    Flipped to NONE by test 5, with the restrictive auth policy left in place,
    to show the policy is then skipped and reports state Inactive.
  DESC
  type        = string
  default     = "AWS_IAM"
}
