resource "azurerm_log_analytics_workspace" "this" {
  count = var.enable_log_analytics ? 1 : 0

  name                = "${var.cluster_name}-logs"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  kubernetes_version  = var.kubernetes_version
  dns_prefix          = var.cluster_name
  node_resource_group = "${var.cluster_name}-nodes"

  private_cluster_enabled           = var.enable_private_cluster
  role_based_access_control_enabled = true
  workload_identity_enabled         = true
  oidc_issuer_enabled               = true
  local_account_disabled            = false

  default_node_pool {
    name                 = "system"
    vm_size              = var.vm_size
    vnet_subnet_id       = var.node_subnet_id
    auto_scaling_enabled = true
    min_count            = var.node_pool_min_count
    max_count            = var.node_pool_max_count
    orchestrator_version = var.kubernetes_version
    os_sku               = "Ubuntu"
    type                 = "VirtualMachineScaleSets"

    upgrade_settings {
      max_surge = "33%"
    }

    tags = var.tags
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
  }

  api_server_access_profile {
    authorized_ip_ranges = var.enable_private_cluster ? null : var.api_server_authorized_ranges
  }

  dynamic "oms_agent" {
    for_each = var.enable_log_analytics ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      # AKS auto-rotates kubelet identities and CSI tokens out-of-band; ignoring
      # these prevents harmless plan diffs after Microsoft-side maintenance.
      kubelet_identity,
      microsoft_defender,
    ]
  }
}
