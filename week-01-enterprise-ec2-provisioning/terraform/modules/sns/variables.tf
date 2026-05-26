variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
