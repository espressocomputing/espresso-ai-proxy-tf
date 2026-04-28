output "endpoint_hostname" {
  description = "Default AFD endpoint hostname (<name>.<region>.azurefd.net). Customers point a CNAME at this for the custom domain."
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "custom_domain_validation_token" {
  description = "AFD-issued validation token. The customer must publish a TXT record at _dnsauth.<custom_domain_host> with this value before AFD will issue the managed certificate."
  value       = azurerm_cdn_frontdoor_custom_domain.this.validation_token
}

output "profile_id" {
  description = "AFD profile resource ID."
  value       = azurerm_cdn_frontdoor_profile.this.id
}

output "endpoint_id" {
  description = "AFD endpoint resource ID."
  value       = azurerm_cdn_frontdoor_endpoint.this.id
}
