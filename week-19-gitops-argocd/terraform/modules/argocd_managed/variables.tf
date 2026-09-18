variable "cluster_name" {
  description = "EKS cluster the capability attaches to"
  type        = string
}

variable "capability_name" {
  description = "Name of the capability resource on the cluster"
  type        = string
  default     = "argocd"
}

variable "name_prefix" {
  description = "Prefix for IAM resources"
  type        = string
}

variable "idc_instance_arn" {
  description = <<-EOT
    AWS IAM Identity Center instance ARN. Hard prerequisite: the capability
    supports no other authentication method, so without an Identity Center
    instance in the account it cannot be created. Discover with
    `aws sso-admin list-instances`.
  EOT
  type        = string
}

variable "namespace" {
  description = "Namespace holding Argo CD's own custom resources"
  type        = string
  default     = "argocd"
}

variable "tags" {
  type    = map(string)
  default = {}
}
