variable "name_prefix" {
  description = "Prefix for every resource name in this module, so teardown verification can match on it."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource here."
  type        = map(string)
  default     = {}
}
