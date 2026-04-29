output "fqdn" {
  description = "Fully-qualified DNS name of the created record, when present"
  value       = try(azurerm_dns_a_record.this[0].fqdn, null)
}
