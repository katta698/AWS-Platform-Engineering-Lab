variable "name_prefix" {
  description = "Prefix shared by every resource in the lab."
  type        = string
}

variable "label" {
  description = "What this principal is called: alpha, beta, or audit."
  type        = string
}

variable "tenant_id" {
  description = "Partition key value this principal is scoped to."
  type        = string
}

variable "guard" {
  description = <<-EOT
    true  -> the policy AWS documents: Null on LeadingKeys, Select pinned to
             SPECIFIC_ATTRIBUTES, no Scan.
    false -> the same policy with both guards removed and Scan added. Reads
             as restrictive, is not.
  EOT
  type        = bool
}

variable "allowed_attributes" {
  description = <<-EOT
    Attributes this principal may name in a request. Must include every key
    attribute of the table and of any index in the policy, or DynamoDB cannot
    perform the action.
  EOT
  type        = list(string)
}

variable "table_name" {
  type = string
}

variable "table_arn" {
  type = string
}

variable "dax_cluster_arn" {
  description = "Cluster the tenant is granted dax: actions on, unconditionally."
  type        = string
}

variable "dax_endpoint" {
  description = "Cluster endpoint for the amazondax client. Empty disables the DAX path."
  type        = string
  default     = ""
}

variable "package_path" {
  type = string
}

variable "package_hash" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
