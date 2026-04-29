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
  # When letsencrypt_dns01_azure_dns is supplied, cert-manager uses DNS-01
  # instead of HTTP-01. Required for wildcard ingress hosts.
  use_letsencrypt_dns01 = (
    local.use_letsencrypt &&
    var.letsencrypt_dns01_azure_dns != null
  )

  cluster_issuer_name  = "letsencrypt-prod"
  cert_manager_sa_name = "cert-manager"

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

  # AKS Standard LB defaults to enableFloatingIP=true (DSR), which delivers
  # packets to the node with the LB's destination IP and original port and
  # relies on kube-proxy iptables to DNAT to the pod. That handoff is
  # fragile in some configurations and produces silent timeouts. Disabling
  # floating IP forces traditional NAT (frontendPort → nodePort), which is
  # well-understood and works reliably. type=string is required because the
  # annotation value must be a literal "true"/"false" string.
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-disable-load-balancer-floating-ip"
    value = "true"
    type  = "string"
  }

  # Azure LB HTTP/HTTPS probes only consider HTTP 200 as healthy. nginx-ingress
  # returns 404 for `GET /` when no Ingress matches (and 308 for healthcheck
  # paths because of ssl-redirect). Both fail the probe and the LB marks the
  # backend unhealthy. TCP probes only check that the TCP connection succeeds,
  # which is sufficient — the workload's actual health is reflected in whether
  # nginx is up at all, not in the response body of an arbitrary path.
  #
  # cloud-provider-azure honors the per-port annotation reliably across AKS
  # versions; the global annotation form is sometimes ignored. Setting both to
  # be safe.
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-protocol"
    value = "tcp"
    type  = "string"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/port_80_health-probe_protocol"
    value = "tcp"
    type  = "string"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/port_443_health-probe_protocol"
    value = "tcp"
    type  = "string"
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

  # AFD connects to the origin IP. Without an SNI match, ingress-nginx presents
  # its generated self-signed default certificate, which AFD rejects even when
  # certificate subject-name checking is disabled. Use the proxy TLS secret as
  # nginx's default certificate so the origin still presents a trusted chain.
  dynamic "set" {
    for_each = local.proxy_tls_secret_name == null ? [] : [local.proxy_tls_secret_name]
    iterator = default_tls_secret

    content {
      name  = "controller.extraArgs.default-ssl-certificate"
      value = "${local.proxy_namespace}/${default_tls_secret.value}"
    }
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

  # Azure Workload Identity wiring for the DNS-01 solver. The controller's SA
  # gets the client-id annotation and the use=true label so the AAD webhook
  # injects a projected token. Pods need the matching label so the webhook
  # selects them. type=string is required because pod label values must be
  # strings; without it Helm coerces "true" to a bool and apiserver rejects
  # the Deployment.
  dynamic "set" {
    for_each = local.use_letsencrypt_dns01 ? [1] : []
    content {
      name  = "serviceAccount.labels.azure\\.workload\\.identity/use"
      value = "true"
      type  = "string"
    }
  }
  dynamic "set" {
    for_each = local.use_letsencrypt_dns01 ? [1] : []
    content {
      name  = "serviceAccount.annotations.azure\\.workload\\.identity/client-id"
      value = module.cert_manager_workload_identity[0].client_id
    }
  }
  dynamic "set" {
    for_each = local.use_letsencrypt_dns01 ? [1] : []
    content {
      name  = "podLabels.azure\\.workload\\.identity/use"
      value = "true"
      type  = "string"
    }
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

# Workload identity that cert-manager uses to write _acme-challenge TXT records
# into the Azure DNS zone during the DNS-01 challenge. Federated to the
# cert-manager controller's default service account; granted DNS Zone
# Contributor on just the target zone.
module "cert_manager_workload_identity" {
  count = local.use_letsencrypt_dns01 ? 1 : 0

  source = "./modules/workload-identity"

  name                 = "${local.name_prefix}-cert-manager"
  resource_group_name  = local.resource_group_name
  location             = var.location
  oidc_issuer_url      = module.aks.oidc_issuer_url
  namespace            = local.cert_manager_namespace
  service_account_name = local.cert_manager_sa_name
  tags                 = local.resource_tags
}

data "azurerm_dns_zone" "letsencrypt_dns01" {
  count = local.use_letsencrypt_dns01 ? 1 : 0

  name                = var.letsencrypt_dns01_azure_dns.zone_name
  resource_group_name = var.letsencrypt_dns01_azure_dns.zone_resource_group_name
}

resource "azurerm_role_assignment" "cert_manager_dns_contributor" {
  count = local.use_letsencrypt_dns01 ? 1 : 0

  scope                = data.azurerm_dns_zone.letsencrypt_dns01[0].id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = module.cert_manager_workload_identity[0].principal_id
}

resource "time_sleep" "wait_for_cert_manager_role_propagation" {
  count = local.use_letsencrypt_dns01 ? 1 : 0

  depends_on      = [azurerm_role_assignment.cert_manager_dns_contributor]
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

  # DNS-01 (azureDNS) solver — engaged when letsencrypt_dns01_azure_dns is
  # supplied. Required for wildcard ingress hosts. Auth is via the workload
  # identity created above; no static credentials are referenced here.
  set {
    name  = "issuer.dns01.enabled"
    value = local.use_letsencrypt_dns01 ? "true" : "false"
  }
  set {
    name  = "issuer.dns01.azureDNS.subscriptionID"
    value = local.use_letsencrypt_dns01 ? data.azurerm_client_config.current.subscription_id : ""
  }
  set {
    name  = "issuer.dns01.azureDNS.resourceGroupName"
    value = local.use_letsencrypt_dns01 ? var.letsencrypt_dns01_azure_dns.zone_resource_group_name : ""
  }
  set {
    name  = "issuer.dns01.azureDNS.hostedZoneName"
    value = local.use_letsencrypt_dns01 ? var.letsencrypt_dns01_azure_dns.zone_name : ""
  }
  set {
    name  = "issuer.dns01.azureDNS.managedIdentityClientID"
    value = local.use_letsencrypt_dns01 ? module.cert_manager_workload_identity[0].client_id : ""
  }

  lifecycle {
    precondition {
      condition = (
        !var.ingress_config.enable_ingress ||
        try(var.ingress_config.letsencrypt_email, null) == null ||
        !startswith(try(var.ingress_config.ingress_host, ""), "*.") ||
        var.letsencrypt_dns01_azure_dns != null
      )
      error_message = "Wildcard ingress_host (e.g. *.example.com) requires letsencrypt_dns01_azure_dns to be set, because Let's Encrypt only issues wildcard certs via DNS-01."
    }
  }

  depends_on = [
    time_sleep.wait_for_cert_manager_crds,
    time_sleep.wait_for_cert_manager_role_propagation,
  ]
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

  # tenantId is intentionally NOT set: when authType=WorkloadIdentity is used
  # with serviceAccountRef, ESO derives the tenant from the SA's
  # azure.workload.identity/tenant-id annotation. Setting it here too triggers
  # ESO's "multiple tenantID found" validation guard.

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

    # AFD health probes do not arrive with a customer wildcard Host header.
    # Keep a hostless probe route so the origin group can mark the AKS origin
    # healthy while the customer-facing wildcard rule still handles traffic.
    rule {
      http {
        path {
          path      = "/healthcheck"
          path_type = "Exact"
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

# ---------------------------------------------------------------------------
# Optional: Azure Front Door in front of the AKS LB.
#
# When ingress_config.front_door.enabled is true, AFD becomes the customer-
# facing endpoint and terminates TLS using a managed cert (DigiCert, with
# working OCSP). AFD forwards traffic to the AKS LB as origin, preserving
# the original Host header so the proxy's subdomain-based account routing
# keeps working. The LE cert on the AKS LB is no longer customer-facing —
# only AFD sees it, and AFD doesn't enforce strict OCSP for origins.
#
# Customer-side DNS work after this provisions:
#   1. CNAME <ingress_host>          → <front_door_endpoint_hostname>
#   2. TXT   _dnsauth.<ingress_host> → <front_door_custom_domain_validation_token>
# Both values are exposed as outputs of this module.
# ---------------------------------------------------------------------------

module "front_door" {
  count = try(var.ingress_config.front_door.enabled, false) ? 1 : 0

  source = "./modules/front-door"

  name_prefix         = local.name_prefix
  resource_group_name = local.resource_group_name
  sku_name            = try(var.ingress_config.front_door.sku_name, "Standard_AzureFrontDoor")
  custom_domain_host  = var.ingress_config.ingress_host
  origin_host         = azurerm_public_ip.ingress[0].ip_address
  health_probe_path   = "/healthcheck"
  tags                = local.resource_tags

  depends_on = [
    azurerm_public_ip.ingress,
    helm_release.ingress_nginx,
  ]
}
