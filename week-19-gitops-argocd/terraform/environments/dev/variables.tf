variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "week19-gitops"
}

variable "kubernetes_version" {
  description = "1.36 is in standard support until Aug 2027. Extended support costs $0.60/hr, six times standard."
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = <<-EOT
    t3.medium, not Week 18's t3.small. Upstream Argo CD runs seven pods in the
    cluster and does not fit beside kube-system in 2 GB. The managed capability
    needs none of this -- that node delta is the comparison.
  EOT
  type        = string
  default     = "t3.medium"
}

variable "managed_namespace" {
  description = "Namespace the EKS capability owns for its own custom resources"
  type        = string
  default     = "argocd"
}

variable "selfmanaged_namespace" {
  type    = string
  default = "argocd-self"
}

variable "argocd_chart_version" {
  description = "10.9.1 ships Argo CD v3.5.3 (2026-09-14)"
  type        = string
  default     = "10.9.1"
}

variable "log_retention_days" {
  type    = number
  default = 1
}

variable "cluster_admin_role_arns" {
  description = "Principals granted cluster-admin via EKS access entries. Set this or be locked out."
  type        = list(string)
  default     = []
}
