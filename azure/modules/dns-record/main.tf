resource "azurerm_dns_a_record" "this" {
  count = var.create_record ? 1 : 0

  name                = var.record_name
  zone_name           = var.zone_name
  resource_group_name = var.zone_resource_group_name
  ttl                 = var.ttl
  records             = [var.target_ip]
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = try(trim(var.zone_name, " ") != "", false)
      error_message = "dns_config.zone_name must be set when dns_config.create_record is true."
    }

    precondition {
      condition     = try(trim(var.zone_resource_group_name, " ") != "", false)
      error_message = "dns_config.zone_resource_group_name must be set when dns_config.create_record is true."
    }

    precondition {
      condition     = try(trim(var.record_name, " ") != "", false)
      error_message = "dns_config.record_name (or ingress_config.ingress_host) must resolve to a non-empty value when dns_config.create_record is true."
    }

    precondition {
      condition     = try(trim(var.target_ip, " ") != "", false)
      error_message = "Could not resolve a target IP for the DNS record. The ingress controller may not have provisioned a public IP yet."
    }
  }
}
