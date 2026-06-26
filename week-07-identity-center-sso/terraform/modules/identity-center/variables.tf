variable "identity_store_id" {
  description = "Identity Store ID behind the IAM Identity Center instance"
  type        = string
}

variable "instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  type        = string
}

variable "target_account_ids" {
  description = "Account IDs that permission sets/groups get assigned into"
  type        = list(string)
}

variable "groups" {
  description = "Groups to create, keyed by group name, with the AWS managed policy ARN their permission set attaches"
  type = map(object({
    description        = string
    managed_policy_arn = string
    session_duration    = string
  }))
}

variable "users" {
  description = "Test users to create and add to a group, keyed by username"
  type = map(object({
    given_name  = string
    family_name = string
    email       = string
    group       = string
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}
