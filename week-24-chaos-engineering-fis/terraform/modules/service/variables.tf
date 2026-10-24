variable "name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }

variable "image" {
  type        = string
  description = "Public image; the tasks have no NAT, so it must be pullable from a public subnet."
  default     = "public.ecr.aws/nginx/nginx:stable"
}

variable "container_port" {
  type    = number
  default = 80
}

variable "desired_count" {
  type        = number
  description = "Four, so FIS can stop a percentage and leave something serving. With two, stopping 50% is a coin flip between degraded and down."
  default     = 4
}

variable "tags" {
  type    = map(string)
  default = {}
}
