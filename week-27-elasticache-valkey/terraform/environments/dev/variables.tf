variable "region" {
  description = "A serverless cache is reachable only from its own VPC, so this is where the whole lab lives."
  type        = string
  default     = "us-east-1"
}
