output "proxy_namespace" {
  description = "Namespace where proxy is deployed"
  value       = local.proxy_namespace
}

output "proxy_service_name" {
  description = "Kubernetes service name for proxy"
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "proxy_service_load_balancer_hostname" {
  description = "Load balancer hostname for the proxy service, when available"
  value       = try(kubernetes_service_v1.this.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "proxy_ingress_load_balancer_hostname" {
  description = "ALB hostname for proxy ingress, when enabled"
  value       = try(kubernetes_ingress_v1.this[0].status[0].load_balancer[0].ingress[0].hostname, null)
}

output "proxy_ingress_load_balancer_zone_id" {
  description = "Hosted zone ID for ALB ingress alias records"
  value       = data.aws_lb_hosted_zone_id.ingress.id
}

output "proxy_hpa_name" {
  description = "Horizontal Pod Autoscaler name for proxy, when enabled"
  value       = try(kubernetes_horizontal_pod_autoscaler_v2.this[0].metadata[0].name, null)
}
