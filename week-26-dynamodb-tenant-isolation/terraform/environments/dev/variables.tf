variable "region" {
  description = "A DAX cluster can only read tables in its own Region."
  type        = string
  default     = "us-east-1"
}

variable "dax_node_type" {
  description = <<-EOT
    dax.t3.small is the smallest current-generation node. T-type nodes are
    burstable and AWS does not recommend them for production workloads that
    need sustained CPU; for a lab measuring an authorisation boundary rather
    than throughput, that does not matter.
  EOT
  type        = string
  default     = "dax.t3.small"
}

variable "dax_nodes" {
  description = <<-EOT
    Three: one primary and two read replicas, one per AZ. AWS requires three
    for fault tolerance. This is the cost of the week at ~$0.04/node/hour.
  EOT
  type        = number
  default     = 3

  validation {
    condition     = var.dax_nodes >= 1 && var.dax_nodes <= 11
    error_message = "A DAX cluster supports 1 to 11 nodes (primary plus up to 10 replicas)."
  }
}
