variable "bus_name" {
  description = "Name of the custom event bus. Deliberately not 'default' -- see main.tf."
  type        = string
}

variable "archive_retention_days" {
  description = <<-EOT
    Archive retention. 1 day is enough to prove replay works and keeps the only
    standing charge in this week (storage at $0.023/GB/month) at effectively zero.
    0 would mean indefinite, which is the wrong default for a lab.
  EOT
  type        = number
  default     = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
