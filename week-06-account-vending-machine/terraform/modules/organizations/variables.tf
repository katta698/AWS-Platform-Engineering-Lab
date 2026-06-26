variable "parent_id" {
  description = "Parent OU (or root) ID under which the vending OUs are created — should be an existing OU like Workloads-OU, not the Organization root, when the Organization already has other unrelated accounts/OUs at root"
  type        = string
}

variable "ou_names" {
  description = "Names of the Organizational Units to create under the root"
  type        = list(string)
  default     = ["Sandbox", "Production"]
}

variable "tags" {
  description = "Tags applied to every OU"
  type        = map(string)
  default     = {}
}
