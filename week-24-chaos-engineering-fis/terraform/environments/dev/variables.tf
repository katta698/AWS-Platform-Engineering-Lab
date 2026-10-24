variable "region" {
  type    = string
  default = "us-east-1"
}

variable "desired_count" {
  type        = number
  description = "Four tasks. Stopping 50% then leaves two serving, so the service degrades rather than disappears -- which is the case worth measuring. With two tasks, 50% is a coin flip between degraded and down."
  default     = 4
}

variable "fault_percent" {
  type        = number
  description = "Share of tasks FIS stops."
  default     = 50
}
