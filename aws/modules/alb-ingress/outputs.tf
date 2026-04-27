output "load_balancer_hostname" {
  description = "ALB hostname for proxy ingress, when enabled"
  value       = try(kubernetes_ingress_v1.this[0].status[0].load_balancer[0].ingress[0].hostname, null)
}

output "load_balancer_zone_id" {
  description = "Hosted zone ID for ALB ingress alias records"
  value       = data.aws_lb_hosted_zone_id.ingress.id
}
