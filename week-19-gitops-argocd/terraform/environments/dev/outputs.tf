output "cluster_name" {
  value = module.platform.cluster_name
}

output "managed_argocd_url" {
  description = "AWS-hosted, Identity Center in front of it. No Ingress in the cluster."
  value       = module.argocd_managed.server_url
}

output "managed_capability_arn" {
  value = module.argocd_managed.capability_arn
}

output "managed_argocd_version" {
  description = "AWS chooses this; you do not pin it"
  value       = module.argocd_managed.argocd_version
}

output "selfmanaged_argocd_version" {
  description = "Read from the chart rather than asserted"
  value       = module.argocd_selfmanaged.app_version
}

output "selfmanaged_access" {
  description = "ClusterIP on purpose -- a LoadBalancer would add cost and expose the API for the life of the lab"
  value       = module.argocd_selfmanaged.port_forward
}

output "kubeconfig" {
  value = "aws eks update-kubeconfig --name ${module.platform.cluster_name} --region ${var.aws_region}"
}
