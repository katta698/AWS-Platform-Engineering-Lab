variable "sandbox_ou_id" {
  description = "OU ID to attach the Sandbox guardrail SCP to"
  type        = string
}

variable "allowed_regions" {
  description = "Regions allowed inside the Sandbox OU — everything else is denied"
  type        = list(string)
  default     = ["us-east-1"]
}

variable "denied_instance_types" {
  description = "EC2 instance type wildcards denied inside the Sandbox OU (cost control guardrail)"
  type        = list(string)
  default     = ["*.4xlarge", "*.8xlarge", "*.12xlarge", "*.16xlarge", "*.24xlarge", "*.metal"]
}
