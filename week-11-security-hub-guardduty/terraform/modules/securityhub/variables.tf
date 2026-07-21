variable "name_prefix" {
  description = "Prefix for named Security Hub resources (e.g. automation rule name)."
  type        = string
}

variable "production_tag_key" {
  description = "Tag key that marks a resource as production, for severity escalation."
  type        = string
  default     = "environment"
}

variable "production_tag_value" {
  description = "Tag value that marks a resource as production."
  type        = string
  default     = "production"
}
