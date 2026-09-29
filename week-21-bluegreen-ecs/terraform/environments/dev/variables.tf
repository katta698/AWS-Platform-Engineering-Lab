variable "region" {
  type    = string
  default = "us-east-1"
}

# These three are what a deployment actually changes. Flipping app_version is a
# good release; flipping serve_root to false is the bad one.
variable "app_version" {
  type    = string
  default = "v1"
}

variable "serve_root" {
  type    = bool
  default = true
}

variable "bake_time_in_minutes" {
  type    = number
  default = 5
}
