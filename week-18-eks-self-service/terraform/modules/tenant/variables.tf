variable "tenant" {
  description = "Tenant name. Used as the namespace name and in every resource name."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for AWS resource names."
  type        = string
  default     = "week18"
}

variable "account_id" {
  description = "Account id, appended to the bucket name to make it globally unique."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster this tenant lives in."
  type        = string
}

variable "compute" {
  description = "Where this tenant's pods run: ec2 or fargate. Recorded as a namespace label so it is visible in kubectl."
  type        = string

  validation {
    condition     = contains(["ec2", "fargate"], var.compute)
    error_message = "compute must be ec2 or fargate."
  }
}

variable "identity_mode" {
  description = "pod_identity (EC2 only) or irsa (works anywhere, required on Fargate)."
  type        = string

  validation {
    condition     = contains(["pod_identity", "irsa"], var.identity_mode)
    error_message = "identity_mode must be pod_identity or irsa."
  }
}

variable "service_account_name" {
  description = "Service account the tenant's pods run as."
  type        = string
  default     = "app"
}

variable "oidc_provider_arn" {
  description = "Cluster OIDC provider ARN. Only used when identity_mode is irsa."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "Cluster OIDC issuer without the scheme. Only used when identity_mode is irsa."
  type        = string
  default     = ""
}

variable "cpu_request_limit" {
  description = "Total CPU this namespace may request."
  type        = string
  default     = "1"
}

variable "cpu_limit" {
  description = "Total CPU ceiling for the namespace."
  type        = string
  default     = "2"
}

variable "memory_request_limit" {
  description = "Total memory this namespace may request."
  type        = string
  default     = "1Gi"
}

variable "memory_limit" {
  description = "Total memory ceiling for the namespace."
  type        = string
  default     = "2Gi"
}

variable "max_pods" {
  description = "Pod count ceiling. A quota without one still allows unlimited tiny pods."
  type        = string
  default     = "10"
}

variable "tags" {
  description = "Extra tags merged into every AWS resource."
  type        = map(string)
  default     = {}
}
