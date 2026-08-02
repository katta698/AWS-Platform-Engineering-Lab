variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for named resources across the stack."
  type        = string
  default     = "week12-cfgcompliance"
}
