output "vnet_id" {
  description = "Dedicated VNet ID"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Dedicated VNet name"
  value       = azurerm_virtual_network.this.name
}

output "node_subnet_id" {
  description = "Subnet ID for AKS nodes"
  value       = azurerm_subnet.nodes.id
}
