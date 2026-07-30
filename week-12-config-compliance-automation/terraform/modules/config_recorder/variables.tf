variable "name_prefix" {
  description = "Prefix for named resources in this module."
  type        = string
}

variable "delivery_history_retention_days" {
  description = "Days to retain configuration history/snapshot objects in the delivery bucket before expiry -- Config history accumulates indefinitely otherwise."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags applied to every resource this module creates."
  type        = map(string)
}
