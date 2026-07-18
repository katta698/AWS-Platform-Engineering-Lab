variable "name" {
  type = string
}

variable "organization_id" {
  description = "AWS Organizations ID allowed to link to the sink"
  type        = string
}
