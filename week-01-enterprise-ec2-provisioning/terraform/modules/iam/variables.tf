variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "artifact_bucket_name" {
  type = string
}

variable "tf_state_bucket" {
  type = string
}

variable "tf_lock_table" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "create_github_oidc_provider" {
  type    = bool
  default = true
}

variable "existing_oidc_provider_arn" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
