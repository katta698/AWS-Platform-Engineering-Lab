output "capability_arn" {
  value = aws_eks_capability.argocd.arn
}

output "capability_role_arn" {
  description = "Empty of permissions on purpose -- see main.tf"
  value       = aws_iam_role.capability.arn
}

output "server_url" {
  description = "The managed Argo CD UI. AWS hosts it; there is no Service or Ingress in your cluster to expose."
  # Not wrapped in try(). The attribute path is documented, so if it stops
  # resolving that is a provider change worth failing on -- try() would turn it
  # into a silent null and the post would report a missing URL as a finding.
  value = aws_eks_capability.argocd.configuration[0].argo_cd[0].server_url
}

output "argocd_version" {
  description = "Which Argo CD AWS actually runs -- held against the chart version on the self-managed side"
  value       = aws_eks_capability.argocd.version
}

output "namespace" {
  value = var.namespace
}
