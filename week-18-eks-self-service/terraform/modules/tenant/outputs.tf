output "namespace" {
  value = kubernetes_namespace.this.metadata[0].name
}

output "bucket" {
  description = "The one bucket this tenant may reach."
  value       = aws_s3_bucket.this.bucket
}

output "role_arn" {
  value = aws_iam_role.tenant.arn
}

output "service_account" {
  value = kubernetes_service_account.this.metadata[0].name
}

output "identity_mode" {
  value = var.identity_mode
}
