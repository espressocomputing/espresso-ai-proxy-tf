output "cluster_name" {
  description = "EKS cluster name"
  value       = module.this.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.this.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS API server certificate authority data"
  value       = module.this.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "EKS control plane security group"
  value       = module.this.cluster_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "Primary EKS cluster security group ID"
  value       = module.this.cluster_primary_security_group_id
}

output "cluster_ip_family" {
  description = "Cluster service IP family"
  value       = module.this.cluster_ip_family
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA integrations"
  value       = module.this.oidc_provider_arn
}
