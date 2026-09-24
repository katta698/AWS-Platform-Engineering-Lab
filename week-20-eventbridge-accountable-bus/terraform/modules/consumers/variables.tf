variable "name_prefix" {
  type = string
}

variable "bus_name" {
  description = "The custom bus these rules attach to. Rules on a custom bus MUST pass event_bus_name on both the rule and the target -- omit it and they silently attach to 'default'."
  type        = string
}

variable "event_source" {
  description = "The `source` value the publisher sets. Matched exactly by the orders rule."
  type        = string
  default     = "platform.orders"
}

variable "handled_detail_type" {
  description = "The detail-type this platform actually handles."
  type        = string
  default     = "order.created"
}

variable "poison_detail_type" {
  description = "Routed to the consumer, which fails on purpose, so the DLQ is proven by a real failed delivery."
  type        = string
  default     = "order.poison"
}

variable "log_retention_days" {
  description = "Set explicitly. An implicitly-created Lambda log group never expires, which is a standing charge nobody looks for."
  type        = number
  default     = 1
}

variable "alert_email" {
  description = "Supplied org-wide by the shared-alert-email HCP variable set. Empty means no subscription."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
