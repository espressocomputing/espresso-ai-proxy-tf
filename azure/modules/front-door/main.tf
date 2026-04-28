locals {
  # AFD custom domain "name" (the resource name, not the host_name) must be
  # alphanumeric or hyphens, 1-260 chars. For a wildcard host like
  # `*.example.com` we render `wildcard-example-com`.
  custom_domain_name = replace(replace(var.custom_domain_host, "*.", "wildcard-"), ".", "-")
}

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.name_prefix}-fd"
  resource_group_name = var.resource_group_name
  sku_name            = var.sku_name
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.name_prefix}-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "default"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    path                = var.health_probe_path
    protocol            = "Https"
    request_type        = "GET"
    interval_in_seconds = 30
  }

  session_affinity_enabled = false
}

resource "azurerm_cdn_frontdoor_origin" "this" {
  name                          = "default"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id

  enabled    = true
  host_name  = var.origin_host
  http_port  = var.origin_http_port
  https_port = var.origin_https_port

  # Pass the original client Host header through to the origin so the proxy's
  # subdomain-based account routing keeps working. (azurerm_cdn_frontdoor_origin
  # passes through when origin_host_header is null/unset.)
  origin_host_header = null

  priority = 1
  weight   = 1000

  # The origin presents an LE cert with a CN that matches the customer-facing
  # wildcard, not the IP we connect to. Disabling the name check lets AFD
  # connect over HTTPS without trying to validate hostname == IP.
  certificate_name_check_enabled = false
}

resource "azurerm_cdn_frontdoor_custom_domain" "this" {
  name                     = local.custom_domain_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  host_name                = var.custom_domain_host

  tls {
    certificate_type = "ManagedCertificate"
  }
}

resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "default"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this.id]

  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true # also responds on <ep>.azurefd.net for testing

  cdn_frontdoor_custom_domain_ids = [azurerm_cdn_frontdoor_custom_domain.this.id]
}
