resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = var.address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = var.node_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_cidr]

  # AKS with CNI Overlay attaches nodes (not pods) to this subnet, so the
  # service-endpoint footprint is minimal. Storage endpoint helps mounted
  # volumes and image pulls from azure storage stay on the Azure backbone.
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
  ]
}
