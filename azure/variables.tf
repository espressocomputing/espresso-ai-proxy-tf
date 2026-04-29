variable "location" {
  description = "Azure region for the on-prem proxy deployment"
  type        = string
}

variable "customer" {
  description = "Customer identifier used for naming and API_URL construction"
  type        = string

  validation {
    condition     = trim(var.customer, " ") != ""
    error_message = "customer must be a non-empty string."
  }
}

variable "resource_group_config" {
  description = "Resource group configuration. When create=true a new RG is created; when false, an existing RG is used."
  type = object({
    create = optional(bool, true)
    name   = optional(string, "espresso-ai-proxy-rg")
  })
  default = {}

  validation {
    condition     = trim(var.resource_group_config.name, " ") != ""
    error_message = "resource_group_config.name must be a non-empty string."
  }
}

variable "create_dedicated_vnet" {
  description = "When true, provision a dedicated VNet. When false, use existing_vnet_config."
  type        = bool
  default     = true
}

variable "vnet_config" {
  description = "Dedicated VNet configuration used when create_dedicated_vnet is true."
  type = object({
    vnet_name        = optional(string, "espresso-ai-proxy-vnet")
    address_space    = optional(list(string), ["10.240.0.0/16"])
    node_subnet_cidr = optional(string, "10.240.0.0/22")
  })
  default = {}

  validation {
    condition = (
      !var.create_dedicated_vnet ||
      length(var.vnet_config.address_space) > 0
    )
    error_message = "vnet_config.address_space must include at least one CIDR block when create_dedicated_vnet is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vnet ||
      alltrue([for cidr in var.vnet_config.address_space : can(cidrnetmask(cidr))])
    )
    error_message = "vnet_config.address_space must contain valid CIDR blocks when create_dedicated_vnet is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vnet ||
      can(cidrnetmask(var.vnet_config.node_subnet_cidr))
    )
    error_message = "vnet_config.node_subnet_cidr must be a valid CIDR block when create_dedicated_vnet is true."
  }
}

variable "existing_vnet_config" {
  description = "Existing VNet configuration used when create_dedicated_vnet is false."
  type = object({
    vnet_id        = string
    node_subnet_id = string
  })
  default = null

  validation {
    condition = (
      var.create_dedicated_vnet ||
      var.existing_vnet_config != null
    )
    error_message = "existing_vnet_config must be provided when create_dedicated_vnet is false."
  }

  validation {
    condition = (
      var.existing_vnet_config == null ||
      trim(var.existing_vnet_config.vnet_id, " ") != ""
    )
    error_message = "existing_vnet_config.vnet_id must be a non-empty string."
  }

  validation {
    condition = (
      var.existing_vnet_config == null ||
      trim(var.existing_vnet_config.node_subnet_id, " ") != ""
    )
    error_message = "existing_vnet_config.node_subnet_id must be a non-empty string."
  }
}

variable "aks_config" {
  description = "AKS cluster and node pool configuration"
  type = object({
    cluster_name                 = optional(string, "espresso-ai-proxy")
    kubernetes_version           = optional(string, "1.35")
    api_server_authorized_ranges = optional(list(string), [])
    enable_private_cluster       = optional(bool, false)
    pod_cidr                     = optional(string, "10.244.0.0/16")
    service_cidr                 = optional(string, "10.245.0.0/16")
    dns_service_ip               = optional(string, "10.245.0.10")
    vm_size                      = optional(string, "Standard_D8s_v5")
    node_pool_min_count          = optional(number, 2)
    node_pool_max_count          = optional(number, 10)
    log_analytics_retention_days = optional(number, 90)
    enable_log_analytics         = optional(bool, false)
  })
  default = {}

  validation {
    condition     = var.aks_config.node_pool_max_count >= var.aks_config.node_pool_min_count
    error_message = "aks_config.node_pool_max_count must be greater than or equal to aks_config.node_pool_min_count."
  }

  validation {
    condition = (
      var.aks_config.enable_private_cluster ||
      length(var.aks_config.api_server_authorized_ranges) > 0
    )
    error_message = "aks_config.api_server_authorized_ranges must be set when the cluster is public (enable_private_cluster=false)."
  }

  validation {
    condition = alltrue([
      for cidr in var.aks_config.api_server_authorized_ranges : can(cidrnetmask(cidr))
    ])
    error_message = "aks_config.api_server_authorized_ranges must contain valid CIDR blocks."
  }
}

variable "proxy_config" {
  description = "Proxy application runtime configuration"
  type = object({
    image                          = string
    replicas                       = optional(number, 2)
    proxy_host                     = string
    otel_exporter_otlp_endpoint    = optional(string, "https://metrics.espressocomputing.com:443")
    api_key_secret_name            = optional(string, "espresso-ai")
    api_key_secret_mode            = optional(string, "BYO_K8S_SECRET")
    api_key_azure_key_vault_secret = optional(string, "espresso-ai-proxy-api-key")
    api_url                        = optional(string, "https://api.espressocomputing.com:25831")
    env_vars                       = optional(map(string), {})
  })

  validation {
    condition = (
      try(var.proxy_config.api_key_secret_name, null) == null ||
      trim(var.proxy_config.api_key_secret_name, " ") != ""
    )
    error_message = "proxy_config.api_key_secret_name must be null or a non-empty string."
  }

  validation {
    condition = contains(
      ["BYO_K8S_SECRET", "MANAGED_AZURE_KEY_VAULT"],
      try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET")
    )
    error_message = "proxy_config.api_key_secret_mode must be BYO_K8S_SECRET or MANAGED_AZURE_KEY_VAULT."
  }

  validation {
    condition = (
      try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET") != "MANAGED_AZURE_KEY_VAULT" ||
      (
        try(var.proxy_config.api_key_azure_key_vault_secret, null) != null &&
        trim(var.proxy_config.api_key_azure_key_vault_secret, " ") != ""
      )
    )
    error_message = "proxy_config.api_key_azure_key_vault_secret must be set when proxy_config.api_key_secret_mode is MANAGED_AZURE_KEY_VAULT."
  }

  validation {
    condition     = trim(var.proxy_config.proxy_host, " ") != ""
    error_message = "proxy_config.proxy_host must be set to a non-empty value."
  }

  validation {
    condition     = trim(var.proxy_config.otel_exporter_otlp_endpoint, " ") != ""
    error_message = "proxy_config.otel_exporter_otlp_endpoint must be non-empty."
  }

  validation {
    condition = alltrue([
      for key in keys(var.proxy_config.env_vars) : trim(key, " ") != ""
    ])
    error_message = "proxy_config.env_vars keys must be non-empty."
  }
}

variable "proxy_api_key_value" {
  description = "Value for ESPRESSO_AI_API_KEY when proxy_config.api_key_secret_mode is MANAGED_AZURE_KEY_VAULT."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition = (
      try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET") != "MANAGED_AZURE_KEY_VAULT" ||
      (var.proxy_api_key_value != null && trim(var.proxy_api_key_value, " ") != "")
    )
    error_message = "proxy_api_key_value must be set when proxy_config.api_key_secret_mode is MANAGED_AZURE_KEY_VAULT."
  }
}

variable "ingress_config" {
  description = "NGINX ingress configuration for the proxy"
  type = object({
    enable_ingress = optional(bool, true)
    ingress_host   = optional(string)

    # TLS provisioning on the AKS LB — choose ONE of:
    #   * letsencrypt_email: install cert-manager and auto-issue/renew the cert
    #     via Let's Encrypt HTTP-01. Default path; "just works" for any
    #     publicly-reachable cluster.
    #   * tls_secret_name: bring your own kubernetes.io/tls secret in the proxy
    #     namespace (e.g. synced from a Key Vault cert via the Secrets Store
    #     CSI driver, or managed by cert-manager outside this module).
    #
    # When front_door.enabled is true, the LE cert is no longer customer-facing
    # — it only secures the AFD-to-AKS-LB hop, and AFD presents its own
    # DigiCert-issued cert (which has working OCSP) to clients.
    letsencrypt_email       = optional(string)
    use_letsencrypt_staging = optional(bool, false)
    tls_secret_name         = optional(string)

    # Optional Azure Front Door fronting. When enabled, AFD terminates TLS for
    # clients with a DigiCert-issued managed cert (which has working OCSP),
    # and forwards traffic to the AKS LB as origin. Required when fronting
    # clients with strict OCSP behavior (e.g. Snowflake's connector) since
    # Let's Encrypt has phased out OCSP.
    front_door = optional(object({
      enabled  = optional(bool, false)
      sku_name = optional(string, "Standard_AzureFrontDoor")
    }), {})
  })
  default = {}

  validation {
    condition = (
      !var.ingress_config.enable_ingress ||
      (try(var.ingress_config.ingress_host, null) != null && trim(var.ingress_config.ingress_host, " ") != "")
    )
    error_message = "ingress_config.ingress_host must be set when ingress_config.enable_ingress is true."
  }

  validation {
    condition = (
      !var.ingress_config.enable_ingress ||
      (
        (try(var.ingress_config.letsencrypt_email, null) != null && trim(var.ingress_config.letsencrypt_email, " ") != "") ||
        (try(var.ingress_config.tls_secret_name, null) != null && trim(var.ingress_config.tls_secret_name, " ") != "")
      )
    )
    error_message = "ingress_config requires either letsencrypt_email (auto cert via cert-manager) or tls_secret_name (BYO TLS secret) when enable_ingress is true."
  }

  validation {
    condition = (
      !var.ingress_config.enable_ingress ||
      !(
        try(var.ingress_config.letsencrypt_email, null) != null && trim(var.ingress_config.letsencrypt_email, " ") != "" &&
        try(var.ingress_config.tls_secret_name, null) != null && trim(var.ingress_config.tls_secret_name, " ") != ""
      )
    )
    error_message = "ingress_config.letsencrypt_email and ingress_config.tls_secret_name are mutually exclusive."
  }
}

variable "dns_config" {
  description = "Azure DNS A-record configuration for proxy ingress"
  type = object({
    create_record            = optional(bool, false)
    zone_name                = optional(string)
    zone_resource_group_name = optional(string)
    record_name              = optional(string)
    ttl                      = optional(number, 300)
  })
  default = {}

  validation {
    condition = (
      !var.dns_config.create_record ||
      (var.dns_config.zone_name != null && trim(var.dns_config.zone_name, " ") != "")
    )
    error_message = "dns_config.zone_name must be set when dns_config.create_record is true."
  }

  validation {
    condition = (
      !var.dns_config.create_record ||
      (var.dns_config.zone_resource_group_name != null && trim(var.dns_config.zone_resource_group_name, " ") != "")
    )
    error_message = "dns_config.zone_resource_group_name must be set when dns_config.create_record is true."
  }
}

variable "autoscaling_config" {
  description = "Horizontal pod autoscaling configuration for proxy"
  type = object({
    min_replicas           = optional(number, 2)
    max_replicas           = optional(number, 10)
    target_cpu_utilization = optional(number, 70)
  })
  default = {}

  validation {
    condition     = var.autoscaling_config.max_replicas >= var.autoscaling_config.min_replicas
    error_message = "autoscaling_config.max_replicas must be greater than or equal to autoscaling_config.min_replicas."
  }

  validation {
    condition = (
      var.autoscaling_config.target_cpu_utilization >= 1 &&
      var.autoscaling_config.target_cpu_utilization <= 100
    )
    error_message = "autoscaling_config.target_cpu_utilization must be between 1 and 100."
  }
}

variable "letsencrypt_dns01_azure_dns" {
  description = <<-EOT
    Optional Azure DNS DNS-01 solver configuration for cert-manager. When set,
    cert-manager uses DNS-01 (which supports wildcard certs) instead of HTTP-01.
    Required when ingress_config.ingress_host is a wildcard (e.g.
    `*.example.com`), since Let's Encrypt only issues wildcards via DNS-01.

    The module provisions a user-assigned managed identity, federates it to
    cert-manager's controller service account, and grants it `DNS Zone
    Contributor` on the named zone. No static credentials are needed.
  EOT
  type = object({
    zone_name                = string
    zone_resource_group_name = string
  })
  default = null

  validation {
    condition = (
      var.letsencrypt_dns01_azure_dns == null ||
      (
        trim(var.letsencrypt_dns01_azure_dns.zone_name, " ") != "" &&
        trim(var.letsencrypt_dns01_azure_dns.zone_resource_group_name, " ") != ""
      )
    )
    error_message = "letsencrypt_dns01_azure_dns.zone_name and zone_resource_group_name must be non-empty when the object is provided."
  }
}

variable "tags" {
  description = "Additional tags applied to Azure resources"
  type        = map(string)
  default     = {}
}
