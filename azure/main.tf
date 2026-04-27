data "azurerm_client_config" "current" {}

locals {
  name_prefix = var.aks_config.cluster_name
  enforced_tags = {
    Name     = local.name_prefix
    Service  = "Proxy"
    ENV      = "prod"
    CUSTOMER = var.customer
  }
  resource_tags = merge(var.tags, local.enforced_tags)

  api_key_secret_mode            = try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET")
  managed_api_key_secret_enabled = local.api_key_secret_mode == "MANAGED_AZURE_KEY_VAULT" # pragma: allowlist secret

  # Resolve VNet/subnet IDs from either the dedicated VNet module or
  # an existing VNet supplied by the caller.
  resolved_vnet_id = (
    var.create_dedicated_vnet ? module.vnet[0].vnet_id : var.existing_vnet_config.vnet_id
  )
  resolved_node_subnet_id = (
    var.create_dedicated_vnet ? module.vnet[0].node_subnet_id : var.existing_vnet_config.node_subnet_id
  )

  # The AKS-managed Standard LB lives in the node resource group; placing the
  # static ingress public IP there avoids extra cross-RG IAM.
  ingress_public_ip_name = "${local.name_prefix}-ingress"
  ingress_namespace      = "ingress-nginx"
  cert_manager_namespace = "cert-manager"
  external_secrets_ns    = "external-secrets"
  external_secrets_sa    = "external-secrets"
  proxy_namespace        = "proxy"

  # TLS provisioning mode. letsencrypt_email and tls_secret_name are mutually
  # exclusive; the variable validation enforces "exactly one".
  use_letsencrypt = (
    var.ingress_config.enable_ingress &&
    try(var.ingress_config.letsencrypt_email, null) != null &&
    trim(try(var.ingress_config.letsencrypt_email, ""), " ") != ""
  )
  use_byo_tls_secret = (
    var.ingress_config.enable_ingress &&
    try(var.ingress_config.tls_secret_name, null) != null &&
    trim(try(var.ingress_config.tls_secret_name, ""), " ") != ""
  )

  cluster_issuer_name = "letsencrypt-prod"

  # Name of the kubernetes.io/tls secret the Ingress consumes. In LE mode
  # cert-manager provisions and rotates this secret automatically; in BYO mode
  # the caller pre-creates it.
  proxy_tls_secret_name = (
    local.use_letsencrypt ? "proxy-tls" : (
      local.use_byo_tls_secret ? var.ingress_config.tls_secret_name : null
    )
  )

  dns_record_name = (
    var.dns_config.record_name != null ? var.dns_config.record_name : var.ingress_config.ingress_host
  )
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = var.resource_group_config.create ? 1 : 0

  name     = var.resource_group_config.name
  location = var.location
  tags     = local.resource_tags
}

data "azurerm_resource_group" "existing" {
  count = var.resource_group_config.create ? 0 : 1

  name = var.resource_group_config.name
}

locals {
  resource_group_name = (
    var.resource_group_config.create
    ? azurerm_resource_group.this[0].name
    : data.azurerm_resource_group.existing[0].name
  )
  resource_group_id = (
    var.resource_group_config.create
    ? azurerm_resource_group.this[0].id
    : data.azurerm_resource_group.existing[0].id
  )
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

module "vnet" {
  count = var.create_dedicated_vnet ? 1 : 0

  source = "./modules/vnet"

  vnet_name           = var.vnet_config.vnet_name
  address_space       = var.vnet_config.address_space
  node_subnet_cidr    = var.vnet_config.node_subnet_cidr
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.resource_tags
}

# ---------------------------------------------------------------------------
# AKS cluster
# ---------------------------------------------------------------------------

module "aks" {
  source = "./modules/aks"

  cluster_name                 = var.aks_config.cluster_name
  kubernetes_version           = var.aks_config.kubernetes_version
  resource_group_name          = local.resource_group_name
  location                     = var.location
  node_subnet_id               = local.resolved_node_subnet_id
  vm_size                      = var.aks_config.vm_size
  node_pool_min_count          = var.aks_config.node_pool_min_count
  node_pool_max_count          = var.aks_config.node_pool_max_count
  pod_cidr                     = var.aks_config.pod_cidr
  service_cidr                 = var.aks_config.service_cidr
  dns_service_ip               = var.aks_config.dns_service_ip
  api_server_authorized_ranges = var.aks_config.api_server_authorized_ranges
  enable_private_cluster       = var.aks_config.enable_private_cluster
  enable_log_analytics         = var.aks_config.enable_log_analytics
  log_analytics_retention_days = var.aks_config.log_analytics_retention_days
  tags                         = local.resource_tags
}

# ---------------------------------------------------------------------------
# Proxy namespace
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "proxy" {
  metadata {
    name = local.proxy_namespace
  }

  depends_on = [module.aks]
}

# ---------------------------------------------------------------------------
# Ingress: static public IP + nginx-ingress controller + Ingress resource
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "ingress" {
  count = var.ingress_config.enable_ingress ? 1 : 0

  name = local.ingress_public_ip_name
  # Place the PIP in the AKS node resource group so the cluster's managed
  # identity can attach it to the LB without extra role assignments.
  resource_group_name = module.aks.node_resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.resource_tags
}

resource "kubernetes_namespace" "ingress" {
  count = var.ingress_config.enable_ingress ? 1 : 0

  metadata {
    name = local.ingress_namespace
  }

  depends_on = [module.aks]
}

resource "helm_release" "ingress_nginx" {
  count = var.ingress_config.enable_ingress ? 1 : 0

  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.11.3"
  namespace  = kubernetes_namespace.ingress[0].metadata[0].name
  timeout    = 1200

  set {
    name  = "controller.service.loadBalancerIP"
    value = azurerm_public_ip.ingress[0].ip_address
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-resource-group"
    value = module.aks.node_resource_group
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-pip-name"
    value = azurerm_public_ip.ingress[0].name
  }

  # Keep the controller scoped to standard cloud LBs and avoid PROXY-protocol
  # surprises that some Azure LB configurations cause. controller.config
  # renders into a ConfigMap whose data values must be strings; force the type
  # so Helm doesn't auto-coerce "true" to a bool.
  set {
    name  = "controller.config.use-forwarded-headers"
    value = "true"
    type  = "string"
  }

  depends_on = [
    azurerm_public_ip.ingress,
    module.aks,
  ]
}

resource "time_sleep" "wait_for_ingress_nginx" {
  count = var.ingress_config.enable_ingress ? 1 : 0

  depends_on      = [helm_release.ingress_nginx]
  create_duration = "60s"
}

# ---------------------------------------------------------------------------
# TLS: cert-manager + Let's Encrypt ClusterIssuer (auto cert provisioning)
#
# Engaged when ingress_config.letsencrypt_email is set. cert-manager watches
# the proxy Ingress, sees the cert-manager.io/cluster-issuer annotation,
# completes an HTTP-01 challenge through nginx, and writes the resulting
# kubernetes.io/tls secret into the proxy namespace. Renewals are automatic.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "cert_manager" {
  count = local.use_letsencrypt ? 1 : 0

  metadata {
    name = local.cert_manager_namespace
  }

  depends_on = [module.aks]
}

resource "helm_release" "cert_manager" {
  count = local.use_letsencrypt ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.16.1"
  namespace  = kubernetes_namespace.cert_manager[0].metadata[0].name
  timeout    = 1200

  # Bundled CRDs install — avoids a manual `kubectl apply -f cert-manager.crds.yaml`.
  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [
    module.aks,
    time_sleep.wait_for_ingress_nginx,
  ]
}

resource "time_sleep" "wait_for_cert_manager_crds" {
  count = local.use_letsencrypt ? 1 : 0

  depends_on      = [helm_release.cert_manager]
  create_duration = "60s"
}

resource "helm_release" "letsencrypt_issuer" {
  count = local.use_letsencrypt ? 1 : 0

  name      = "letsencrypt-cluster-issuer"
  chart     = abspath("${path.module}/../charts/cert-manager-letsencrypt-issuer")
  namespace = kubernetes_namespace.cert_manager[0].metadata[0].name
  timeout   = 600

  set {
    name  = "issuer.name"
    value = local.cluster_issuer_name
  }

  set {
    name  = "issuer.email"
    value = var.ingress_config.letsencrypt_email
  }

  set {
    name = "issuer.server"
    value = (
      var.ingress_config.use_letsencrypt_staging
      ? "https://acme-staging-v02.api.letsencrypt.org/directory"
      : "https://acme-v02.api.letsencrypt.org/directory"
    )
  }

  set {
    name  = "issuer.ingressClass"
    value = "nginx"
  }

  depends_on = [time_sleep.wait_for_cert_manager_crds]
}

# ---------------------------------------------------------------------------
# Managed API key flow: Key Vault + ESO + ExternalSecret
# ---------------------------------------------------------------------------

resource "random_string" "key_vault_suffix" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_key_vault" "proxy_api_key" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  # Key Vault names must be globally unique and 3-24 chars; the random suffix
  # protects against name collisions on re-creates within the soft-delete window.
  # Layout: <up-to-17-char-cluster-name>-<6-char-random> = 24 chars max.
  name                       = "${substr(replace(local.name_prefix, "_", "-"), 0, 17)}-${random_string.key_vault_suffix[0].result}"
  resource_group_name        = local.resource_group_name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = local.resource_tags
}

# Allow the Terraform-running principal to manage secrets in the new vault.
resource "azurerm_role_assignment" "kv_admin_for_terraform" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  scope                = azurerm_key_vault.proxy_api_key[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_for_kv_role_propagation" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  depends_on      = [azurerm_role_assignment.kv_admin_for_terraform]
  create_duration = "60s"
}

resource "azurerm_key_vault_secret" "proxy_api_key" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  name         = var.proxy_config.api_key_azure_key_vault_secret
  value        = var.proxy_api_key_value
  key_vault_id = azurerm_key_vault.proxy_api_key[0].id

  depends_on = [time_sleep.wait_for_kv_role_propagation]
}

# Workload identity that ESO uses to read the Key Vault secret.
module "external_secrets_workload_identity" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  source = "./modules/workload-identity"

  name                 = "${local.name_prefix}-external-secrets"
  resource_group_name  = local.resource_group_name
  location             = var.location
  oidc_issuer_url      = module.aks.oidc_issuer_url
  namespace            = local.external_secrets_ns
  service_account_name = local.external_secrets_sa
  tags                 = local.resource_tags
}

resource "azurerm_role_assignment" "eso_kv_reader" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  scope                = azurerm_key_vault.proxy_api_key[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.external_secrets_workload_identity[0].principal_id
}

resource "kubernetes_namespace" "external_secrets" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  metadata {
    name = local.external_secrets_ns
  }

  depends_on = [module.aks]
}

resource "kubernetes_service_account_v1" "external_secrets" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  metadata {
    name      = local.external_secrets_sa
    namespace = kubernetes_namespace.external_secrets[0].metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = module.external_secrets_workload_identity[0].client_id
      "azure.workload.identity/tenant-id" = module.external_secrets_workload_identity[0].tenant_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }

  automount_service_account_token = true
}

resource "helm_release" "external_secrets" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace.external_secrets[0].metadata[0].name
  timeout    = 1200

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.external_secrets[0].metadata[0].name
  }

  # Workload Identity needs the controller pods to be labeled so the webhook
  # injects the projected token volume. type=string is required: without it,
  # Helm's set block auto-coerces "true" to a bool and Kubernetes rejects the
  # Deployment because pod-label values must be strings.
  set {
    name  = "podLabels.azure\\.workload\\.identity/use"
    value = "true"
    type  = "string"
  }

  depends_on = [
    kubernetes_service_account_v1.external_secrets,
    azurerm_role_assignment.eso_kv_reader,
  ]
}

resource "time_sleep" "wait_for_external_secrets_crds" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  depends_on      = [helm_release.external_secrets]
  create_duration = "90s"
}

resource "helm_release" "proxy_api_key_external_secret" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  name      = "proxy-api-key-external-secret"
  chart     = abspath("${path.module}/../charts/proxy-api-key-external-secret")
  namespace = kubernetes_namespace.external_secrets[0].metadata[0].name
  timeout   = 1200

  set {
    name  = "secretStore.provider"
    value = "azure"
  }

  set {
    name  = "secretStore.name"
    value = "${local.name_prefix}-azure-key-vault"
  }

  set {
    name  = "secretStore.azure.keyVaultUrl"
    value = azurerm_key_vault.proxy_api_key[0].vault_uri
  }

  set {
    name  = "secretStore.azure.tenantId"
    value = data.azurerm_client_config.current.tenant_id
  }

  set {
    name  = "secretStore.serviceAccountName"
    value = kubernetes_service_account_v1.external_secrets[0].metadata[0].name
  }

  set {
    name  = "secretStore.serviceAccountNamespace"
    value = kubernetes_namespace.external_secrets[0].metadata[0].name
  }

  set {
    name  = "externalSecret.name"
    value = "proxy-api-key"
  }

  set {
    name  = "externalSecret.namespace"
    value = local.proxy_namespace
  }

  set {
    name  = "externalSecret.refreshInterval"
    value = "1h"
  }

  set {
    name  = "externalSecret.targetSecretName"
    value = var.proxy_config.api_key_secret_name
  }

  set {
    name  = "externalSecret.targetSecretKey"
    value = "ESPRESSO_AI_API_KEY"
  }

  set {
    name  = "externalSecret.remoteKey"
    value = var.proxy_config.api_key_azure_key_vault_secret
  }

  depends_on = [
    kubernetes_namespace.proxy,
    time_sleep.wait_for_external_secrets_crds,
    azurerm_key_vault_secret.proxy_api_key,
  ]
}

resource "time_sleep" "wait_for_proxy_api_key_sync" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  depends_on      = [helm_release.proxy_api_key_external_secret]
  create_duration = "30s"
}

# ---------------------------------------------------------------------------
# Proxy workload (shared module)
# ---------------------------------------------------------------------------

module "proxy" {
  source = "../modules/proxy"

  proxy_image               = var.proxy_config.image
  proxy_replicas            = var.proxy_config.replicas
  proxy_port                = 5050
  proxy_api_key_secret_name = var.proxy_config.api_key_secret_name
  proxy_env = merge(
    local.enforced_tags,
    var.proxy_config.env_vars,
    {
      PROXY_HOST                  = var.proxy_config.proxy_host
      OTEL_EXPORTER_OTLP_ENDPOINT = var.proxy_config.otel_exporter_otlp_endpoint
      API_URL                     = "${var.proxy_config.api_url}/${var.customer}"
    }
  )

  enable_proxy_autoscaling                 = true
  proxy_autoscaling_min_replicas           = var.autoscaling_config.min_replicas
  proxy_autoscaling_max_replicas           = var.autoscaling_config.max_replicas
  proxy_autoscaling_target_cpu_utilization = var.autoscaling_config.target_cpu_utilization

  depends_on = [
    module.aks,
    kubernetes_namespace.proxy,
    time_sleep.wait_for_proxy_api_key_sync,
  ]
}

# ---------------------------------------------------------------------------
# Proxy Ingress (nginx) with TLS
# ---------------------------------------------------------------------------

resource "kubernetes_ingress_v1" "proxy" {
  count = var.ingress_config.enable_ingress ? 1 : 0

  metadata {
    name      = "proxy"
    namespace = local.proxy_namespace
    annotations = merge(
      {
        "nginx.ingress.kubernetes.io/ssl-redirect"     = "true"
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
      },
      local.use_letsencrypt ? {
        # Triggers cert-manager to provision and rotate the TLS secret
        # referenced in spec.tls.secret_name below.
        "cert-manager.io/cluster-issuer" = local.cluster_issuer_name
      } : {}
    )
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [var.ingress_config.ingress_host]
      secret_name = local.proxy_tls_secret_name
    }

    rule {
      host = var.ingress_config.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = module.proxy.proxy_service_name
              port {
                number = module.proxy.proxy_service_port
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    module.proxy,
    time_sleep.wait_for_ingress_nginx,
    # In LE mode the ClusterIssuer must exist before cert-manager will respond
    # to this Ingress's annotation. depends_on to a count=0 resource is a no-op.
    helm_release.letsencrypt_issuer,
  ]
}

# ---------------------------------------------------------------------------
# DNS A record pointing at the static ingress IP
# ---------------------------------------------------------------------------

module "proxy_dns_record" {
  source = "./modules/dns-record"

  create_record            = var.dns_config.create_record
  zone_name                = try(var.dns_config.zone_name, "")
  zone_resource_group_name = try(var.dns_config.zone_resource_group_name, "")
  record_name              = try(local.dns_record_name, "")
  target_ip                = try(azurerm_public_ip.ingress[0].ip_address, "")
  ttl                      = var.dns_config.ttl
  tags                     = local.resource_tags
}
