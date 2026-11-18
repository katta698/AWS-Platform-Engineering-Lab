variable "primary_region" {
  description = "Where the writable database lives."
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "Where the read replica lives. Far enough that replication lag is measurable."
  type        = string
  default     = "us-west-2"
}

variable "engine_version" {
  description = "Orderable on db.t4g.micro in both regions, verified 2026-11-17."
  type        = string
  default     = "18.6"
}

variable "create_region_switch_plan" {
  description = <<-EOT
    A Region switch plan is $70/month, prorated. Everything else here is cents,
    so this is the one switch worth being able to turn off.
  EOT
  type        = bool
  default     = true
}
