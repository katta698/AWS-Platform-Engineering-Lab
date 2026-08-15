variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to subscribe. A VPC-level subscription covers every ENI in the VPC, including ones created later."
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket to create for flow logs."
  type        = string
}

variable "log_format" {
  description = <<-EOT
    The custom flow log format string, e.g. "$${version} $${account-id} ...".

    Passed in from the root module rather than defined here, because the exact
    field ORDER has to match the Glue table's column order character for character.
    Defining it in one place and handing it to both modules is what stops the two
    drifting apart -- and a drift here produces wrong values in the right columns,
    not an error.
  EOT
  type        = string
}

variable "tag_keys" {
  description = <<-EOT
    Instance tag keys whose VALUES get embedded into each flow log record, in order.

    Requires flow log record version 11. The first key here populates the
    $${instance-tag} field, the second populates $${instance-tag-2}.
  EOT
  type        = list(string)
  default     = ["Team"]
}

variable "traffic_type" {
  description = <<-EOT
    ACCEPT, REJECT, or ALL.

    ALL is required here: REJECT alone would capture the port-scan signal but lose
    every accepted flow, and accepted flows are what top-talker and NAT cost
    attribution are computed from.
  EOT
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.traffic_type)
    error_message = "traffic_type must be one of ACCEPT, REJECT, or ALL."
  }
}

variable "max_aggregation_interval" {
  description = <<-EOT
    Maximum aggregation interval in seconds: 60 or 600.

    600 is the default and produces fewer, larger records. 60 gives tighter incident
    timelines at the cost of more records and therefore more GB billed at $0.25/GB.

    Note that this is a MAXIMUM, not a guarantee: ENIs attached to Nitro-based
    instances always aggregate at 1 minute or less regardless of this setting, so on
    a modern fleet the knob does less than it appears to.
  EOT
  type        = number
  default     = 600

  validation {
    condition     = contains([60, 600], var.max_aggregation_interval)
    error_message = "max_aggregation_interval must be either 60 or 600."
  }
}

variable "log_retention_days" {
  description = <<-EOT
    Days before raw flow log objects are expired from S3.

    Flow logs are append-only and never stop. Without this expiry the bucket grows
    without bound at $0.023/GB-month forever -- which is how a logging build quietly
    becomes a recurring bill nobody attributes to anything.
  EOT
  type        = number
  default     = 30
}
