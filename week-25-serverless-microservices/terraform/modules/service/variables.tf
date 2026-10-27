variable "name" {
  description = "Name prefix for every resource in this week."
  type        = string
}

variable "tags" {
  description = "Tags applied to everything, so the teardown sweep can find it."
  type        = map(string)
  default     = {}
}

# Duration is the lever, not request rate.
#
# Concurrency = (requests per second) x (duration in seconds). A neighbour that
# holds its execution environment open for half a second consumes ten times the
# concurrency of one that returns in 50ms, at the same request rate. That is
# why the noisy services are slow rather than merely frequent.
variable "checkout_duration_ms" {
  description = "How long the service that matters takes to respond."
  type        = number
  default     = 50
}

variable "neighbour_duration_ms" {
  description = "How long each noisy neighbour holds an execution environment."
  type        = number
  default     = 500
}

variable "protect_checkout" {
  description = "Run 2 only: give checkout a reserved concurrency slice."
  type        = bool
  default     = false
}

variable "checkout_reserved_concurrency" {
  description = <<-EOT
    How much concurrency checkout reserves in run 2.

    Sized from the load, not guessed: checkout runs at 50ms, so each execution
    environment serves about 20 requests a second. Reserving 50 therefore
    covers roughly 1,000 requests a second of checkout traffic -- comfortably
    above what the load generator sends it, so any throttling in run 2 is a
    finding rather than an undersized reservation.
  EOT
  type        = number
  default     = 50
}
