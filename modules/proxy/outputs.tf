output "proxy_namespace" {
  description = "Namespace where proxy is deployed"
  value       = local.proxy_namespace
}

output "proxy_service_name" {
  description = "Kubernetes service name for proxy"
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "proxy_service_port" {
  description = "Kubernetes service port for proxy"
  value       = var.proxy_port
}

output "proxy_service_load_balancer_hostname" {
  description = "Load balancer hostname for the proxy service, when available"
  value       = try(kubernetes_service_v1.this.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "proxy_hpa_name" {
  description = "Horizontal Pod Autoscaler name for proxy, when enabled"
  value       = try(kubernetes_horizontal_pod_autoscaler_v2.this[0].metadata[0].name, null)
}
