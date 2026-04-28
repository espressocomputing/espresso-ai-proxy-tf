output "resource_group_name" {
  description = "Resource group hosting the proxy infrastructure"
  value       = local.resource_group_name
}

output "vnet_id" {
  description = "VNet ID used by the on-prem proxy"
  value       = local.resolved_vnet_id
}

output "node_subnet_id" {
  description = "Subnet ID used by AKS nodes"
  value       = local.resolved_node_subnet_id
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = module.aks.cluster_name
}

output "aks_node_resource_group" {
  description = "Resource group AKS uses for cluster-managed infrastructure"
  value       = module.aks.node_resource_group
}

output "aks_oidc_issuer_url" {
  description = "AKS OIDC issuer URL (used for federated workload identity)"
  value       = module.aks.oidc_issuer_url
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet identity. Use as the principal_id when granting AcrPull on a container registry."
  value       = module.aks.kubelet_identity_object_id
}

output "proxy_namespace" {
  description = "Namespace where proxy is deployed"
  value       = module.proxy.proxy_namespace
}

output "proxy_service_name" {
  description = "Kubernetes service name for proxy"
  value       = module.proxy.proxy_service_name
}

output "proxy_ingress_public_ip" {
  description = "Static public IP fronting the nginx ingress, when enabled"
  value       = try(azurerm_public_ip.ingress[0].ip_address, null)
}

output "proxy_hpa_name" {
  description = "Horizontal Pod Autoscaler name for proxy, when enabled"
  value       = module.proxy.proxy_hpa_name
}

output "proxy_dns_fqdn" {
  description = "Azure DNS record FQDN for proxy, when created"
  value       = module.proxy_dns_record.fqdn
}

output "proxy_api_key_key_vault_name" {
  description = "Key Vault name holding the proxy API key, when MANAGED_AZURE_KEY_VAULT mode is enabled"
  value       = try(azurerm_key_vault.proxy_api_key[0].name, null)
}

output "front_door_endpoint_hostname" {
  description = "Default AFD endpoint hostname (<name>.<region>.azurefd.net). Point a CNAME from your custom domain at this. Only set when ingress_config.front_door.enabled is true."
  value       = try(module.front_door[0].endpoint_hostname, null)
}

output "front_door_custom_domain_validation_token" {
  description = "Validation token for the AFD custom domain. Publish a TXT record at _dnsauth.<ingress_host> with this value before AFD will issue the managed cert. Only set when ingress_config.front_door.enabled is true."
  value       = try(module.front_door[0].custom_domain_validation_token, null)
}
