output "endpoint_hostname" {
  description = "Default AFD endpoint hostname (<name>.<region>.azurefd.net). Customers point a CNAME at this for the custom domain."
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name

  # Callers commonly use this output to create the public CNAME. Azure Front
  # Door expects the route/domain association to exist before traffic DNS is
  # published, otherwise CNAME validation can race AFD propagation.
  depends_on = [azurerm_cdn_frontdoor_custom_domain_association.this]
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

output "route_id" {
  description = "AFD route resource ID."
  value       = azurerm_cdn_frontdoor_route.this.id
}

output "custom_domain_id" {
  description = "AFD custom domain resource ID."
  value       = azurerm_cdn_frontdoor_custom_domain.this.id
}

output "custom_domain_association_id" {
  description = "AFD custom domain association resource ID."
  value       = azurerm_cdn_frontdoor_custom_domain_association.this.id
}
