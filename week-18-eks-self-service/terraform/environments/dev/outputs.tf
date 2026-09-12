output "cluster_name" {
  value = module.platform.cluster_name
}

output "kubeconfig_command" {
  description = "Point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --name ${module.platform.cluster_name} --region ${var.aws_region}"
}

output "tenant_a" {
  description = "EC2 tenant, identity via Pod Identity."
  value = {
    namespace     = module.tenant_a.namespace
    bucket        = module.tenant_a.bucket
    role_arn      = module.tenant_a.role_arn
    identity_mode = module.tenant_a.identity_mode
  }
}

output "tenant_b" {
  description = "Fargate tenant, identity via IRSA."
  value = {
    namespace     = module.tenant_b.namespace
    bucket        = module.tenant_b.bucket
    role_arn      = module.tenant_b.role_arn
    identity_mode = module.tenant_b.identity_mode
  }
}
