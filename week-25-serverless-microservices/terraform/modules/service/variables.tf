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

# THE POOL IS NEVER THE NUMBER IN THE DOCS (added 2026-10-30)
#
# The account limit is 1,000 concurrent executions, and the experiment needed
# that pool exhausted. A single laptop cannot do it: asked for 1,200 concurrent
# requests it delivered 292, and checkout's apparent collapse was its own
# sockets failing, not Lambda throttling. CloudWatch recorded zero throttles
# through both attempts.
#
# So stop trying to fill the pool and shrink it instead -- which is what every
# real account looks like anyway. A reservation does not only cap the function
# that holds it; it is subtracted from the unreserved pool that every OTHER
# unreserved function shares. Reserve 900 here and AWS leaves exactly 100
# unreserved (it refuses to let you reserve the last 100), so one neighbour on
# its own is enough to exhaust what is left and starve checkout.
#
# Same mechanism as the original design, at a scale one client can actually
# reach, and it demonstrates the sharper point: your unreserved capacity is the
# account limit minus everyone else's reservations.
variable "neighbour_reservation" {
  description = "Map of neighbour name to reserved concurrency, e.g. {exports = 900}. Shrinks the unreserved pool the others share."
  type        = map(number)
  default     = {}
}
