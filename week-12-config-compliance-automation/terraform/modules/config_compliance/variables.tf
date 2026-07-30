variable "name_prefix" {
  description = "Prefix for named resources in this module."
  type        = string
}

variable "remediation_tag_key" {
  description = "Opt-in tag key gating auto-remediation of the two S3 rules."
  type        = string
}

variable "remediation_tag_value" {
  description = "Opt-in tag value gating auto-remediation of the two S3 rules."
  type        = string
}

variable "required_tag_keys" {
  description = "Exactly 3 tag keys the required-tags rule enforces."
  type        = list(string)

  validation {
    condition     = length(var.required_tag_keys) == 3
    error_message = "required_tag_keys must contain exactly 3 keys -- the conformance pack template hardcodes tag1Key/tag2Key/tag3Key."
  }
}

variable "tags" {
  description = "Common tags applied to every resource this module creates."
  type        = map(string)
}
