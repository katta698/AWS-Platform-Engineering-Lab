variable "cluster_name" {
  description = "Name of the EKS cluster and prefix for everything around it."
  type        = string
  default     = "week18-platform"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version. Stay in standard support: extended support costs $0.60/hr against $0.10/hr."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "CIDR for the cluster VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "public_access_cidrs" {
  description = "Who may reach the Kubernetes API endpoint. Left open for a same-day lab; narrow this anywhere real."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  description = "Instance type for the single managed node. It exists so the Pod Identity agent has somewhere to run."
  type        = string
  default     = "t3.small"
}

variable "fargate_namespace" {
  description = "Namespace whose pods land on Fargate. Pod Identity does not work there, so this tenant uses IRSA."
  type        = string
}

variable "log_retention_days" {
  description = "Control plane log retention. Short: these logs die with the week."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}

variable "cluster_admin_role_arns" {
  description = "Roles granted cluster admin through EKS access entries. The creator role is already admin; this is for everyone else, including the human who owns the account."
  type        = list(string)
  default     = []
}
