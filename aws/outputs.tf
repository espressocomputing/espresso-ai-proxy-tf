output "vpc_id" {
  description = "VPC ID used by the on-prem proxy"
  value       = local.resolved_vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the on-prem proxy"
  value       = local.resolved_public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the on-prem proxy"
  value       = local.resolved_private_subnet_ids
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "EKS control plane security group"
  value       = module.eks.cluster_security_group_id
}

output "proxy_namespace" {
  description = "Namespace where proxy is deployed"
  value       = module.proxy.proxy_namespace
}

output "proxy_service_name" {
  description = "Kubernetes service name for proxy"
  value       = module.proxy.proxy_service_name
}

output "proxy_service_load_balancer_hostname" {
  description = "Load balancer hostname for the proxy service, when available"
  value       = module.proxy.proxy_service_load_balancer_hostname
}

output "proxy_ingress_load_balancer_hostname" {
  description = "ALB hostname for proxy ingress, when enabled"
  value       = module.alb_ingress.load_balancer_hostname
}

output "proxy_hpa_name" {
  description = "Horizontal Pod Autoscaler name for proxy, when enabled"
  value       = module.proxy.proxy_hpa_name
}

output "proxy_dns_fqdn" {
  description = "Route53 record FQDN for proxy, when created"
  value       = module.proxy_dns_record.fqdn
}
