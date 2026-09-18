output "namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}

output "chart_version" {
  value = helm_release.argocd.version
}

output "app_version" {
  description = "Argo CD version the pinned chart deploys"
  # helm provider 3.x made metadata an object; in 2.x this was metadata[0].
  value = helm_release.argocd.metadata.app_version
}

output "port_forward" {
  description = "No LoadBalancer on purpose -- see main.tf"
  value       = "kubectl port-forward -n ${kubernetes_namespace.argocd.metadata[0].name} svc/argocd-server 8080:80"
}
