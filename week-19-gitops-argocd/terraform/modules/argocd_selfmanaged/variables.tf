variable "namespace" {
  description = "Namespace for the self-managed install. Deliberately not 'argocd', which the managed capability owns in this cluster."
  type        = string
  default     = "argocd-self"
}

variable "chart_version" {
  description = "argo-cd Helm chart version. 10.9.1 ships Argo CD v3.5.3 (2026-09-14)."
  type        = string
  default     = "10.9.1"
}
