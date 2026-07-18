variable "function_name" {
  type = string
}

variable "log_group_name" {
  description = "App log group the generator writes to (must sit under the centralization rule's prefix)"
  type        = string
}
