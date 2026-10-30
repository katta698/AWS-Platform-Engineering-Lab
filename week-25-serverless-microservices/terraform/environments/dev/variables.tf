variable "region" {
  description = <<-EOT
    us-east-2, not us-east-1.

    Lambda concurrency is a per-account, per-REGION pool. us-east-1 in this
    account holds 13 functions from other projects that share it; this week
    deliberately exhausts the pool, so running there would throttle them.
    us-east-2 has none, and its own full 1,000-unit quota.
  EOT
  type        = string
  default     = "us-east-2"
}

variable "checkout_duration_ms" {
  type    = number
  default = 50
}

variable "neighbour_duration_ms" {
  type    = number
  default = 500
}

variable "protect_checkout" {
  description = "false for run 1, true for run 2. The only thing that changes."
  type        = bool
  default     = false
}

variable "checkout_reserved_concurrency" {
  type    = number
  default = 50
}

variable "neighbour_reservation" {
  description = "Reserved concurrency per neighbour. {exports = 900} leaves 100 unreserved for reports and checkout to fight over."
  type        = map(number)
  default     = {}
}
