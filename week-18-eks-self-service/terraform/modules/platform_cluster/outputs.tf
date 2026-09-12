output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca" {
  description = "Base64 CA bundle, for configuring a Kubernetes client."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider for this cluster. IRSA needs it; Pod Identity does not."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "Issuer URL without the scheme, which is the form an IRSA trust policy wants."
  value       = replace(aws_iam_openid_connect_provider.this.url, "https://", "")
}

output "node_group_name" {
  value = aws_eks_node_group.this.node_group_name
}

output "fargate_profile_name" {
  value = aws_eks_fargate_profile.tenant.fargate_profile_name
}

output "vpc_id" {
  value = aws_vpc.this.id
}
