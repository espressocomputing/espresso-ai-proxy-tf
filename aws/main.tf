locals {
  name_prefix = var.eks_config.cluster_name
  enforced_tags = {
    Name     = local.name_prefix
    Service  = "Proxy"
    ENV      = "prod"
    CUSTOMER = var.customer
  }
  resource_tags = merge(var.tags, local.enforced_tags)
  resolved_vpc_id = (
    var.create_dedicated_vpc ? module.vpc[0].vpc_id : var.existing_vpc_config.vpc_id
  )
  resolved_public_subnet_ids = (
    var.create_dedicated_vpc ? module.vpc[0].public_subnet_ids : var.existing_vpc_config.public_subnet_ids
  )
  resolved_private_subnet_ids = (
    var.create_dedicated_vpc ? module.vpc[0].private_subnet_ids : var.existing_vpc_config.private_subnet_ids
  )
  api_key_secret_mode            = try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET")
  managed_api_key_secret_enabled = local.api_key_secret_mode == "MANAGED_AWS_SECRETS_MANAGER" # pragma: allowlist secret
}

resource "kubernetes_namespace" "proxy" {
  metadata {
    name = "proxy"
  }

  depends_on = [module.eks]
}

module "vpc" {
  count = var.create_dedicated_vpc ? 1 : 0

  source = "./modules/vpc"

  vpc_name             = var.vpc_config.vpc_name
  vpc_cidr             = var.vpc_config.cidr
  public_subnet_cidrs  = var.vpc_config.public_subnet_cidrs
  private_subnet_cidrs = var.vpc_config.private_subnet_cidrs
  availability_zones   = var.vpc_config.availability_zones
  tags                 = local.resource_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name                           = var.eks_config.cluster_name
  cluster_version                        = var.eks_config.cluster_version
  bootstrap_self_managed_addons          = var.eks_config.bootstrap_self_managed_addons
  cluster_endpoint_public_access         = var.eks_config.cluster_endpoint_public_access
  cluster_endpoint_private_access        = var.eks_config.cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs   = var.eks_config.cluster_endpoint_public_access_cidrs
  create_cloudwatch_log_group            = var.eks_config.create_cloudwatch_log_group
  cloudwatch_log_group_retention_in_days = var.eks_config.cloudwatch_log_group_retention_in_days

  vpc_id             = local.resolved_vpc_id
  private_subnet_ids = local.resolved_private_subnet_ids

  instance_types          = var.eks_config.instance_types
  node_group_min_size     = var.eks_config.node_group_min_size
  node_group_desired_size = var.eks_config.node_group_desired_size
  node_group_max_size     = var.eks_config.node_group_max_size
  tags                    = local.resource_tags
}

module "alb_controller_irsa" {
  source = "./modules/alb-controller-irsa"

  role_name            = "${local.name_prefix}-alb-controller"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  tags                 = local.resource_tags
}

resource "kubernetes_service_account_v1" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.iam_role_arn
    }
  }

  automount_service_account_token = true

  depends_on = [module.eks, module.alb_controller_irsa]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  timeout    = 1200

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = local.resolved_vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.alb_controller.metadata[0].name
  }

  depends_on = [kubernetes_service_account_v1.alb_controller]
}

resource "time_sleep" "wait_for_aws_load_balancer_controller_webhook" {
  # ALB controller registers an admission webhook during install; endpoint
  # readiness can lag briefly and cause transient service-creation failures.
  depends_on = [helm_release.aws_load_balancer_controller]

  create_duration = "90s"
}

module "karpenter" {
  source = "./modules/karpenter"

  cluster_name                      = module.eks.cluster_name
  cluster_endpoint                  = module.eks.cluster_endpoint
  cluster_ip_family                 = module.eks.cluster_ip_family
  oidc_provider_arn                 = module.eks.oidc_provider_arn
  private_subnet_ids                = local.resolved_private_subnet_ids
  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  instance_types                    = var.karpenter_config.instance_types
  capacity_types                    = var.karpenter_config.capacity_types
  cpu_limit                         = var.karpenter_config.cpu_limit
  memory_limit                      = var.karpenter_config.memory_limit
  node_cap                          = var.karpenter_config.node_cap
  tags                              = local.resource_tags

  depends_on = [
    module.eks,
    time_sleep.wait_for_aws_load_balancer_controller_webhook,
  ]
}

resource "aws_secretsmanager_secret" "proxy_api_key" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  name = var.proxy_config.api_key_aws_secret_name

  recovery_window_in_days = 0
  tags                    = local.resource_tags
}

resource "aws_secretsmanager_secret_version" "proxy_api_key" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.proxy_api_key[0].id
  secret_string = jsonencode({
    ESPRESSO_AI_API_KEY = var.proxy_api_key_value
  })
}

resource "aws_iam_policy" "external_secrets_read_proxy_api_key" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  name        = "${local.name_prefix}-external-secrets-read-proxy-api-key"
  description = "Allows External Secrets Operator to read proxy API key secret"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = aws_secretsmanager_secret.proxy_api_key[0].arn
      }
    ]
  })
  tags = local.resource_tags
}

module "external_secrets_irsa" {
  count  = local.managed_api_key_secret_enabled ? 1 : 0
  source = "./modules/external-secrets-irsa"

  role_name            = "${local.name_prefix}-external-secrets"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  namespace            = "external-secrets"
  service_account_name = "external-secrets"
  role_policy_arns = {
    secrets = aws_iam_policy.external_secrets_read_proxy_api_key[0].arn
  }
  tags = local.resource_tags
}

resource "kubernetes_namespace" "external_secrets" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  metadata {
    name = "external-secrets"
  }

  depends_on = [
    module.eks,
    time_sleep.wait_for_aws_load_balancer_controller_webhook,
  ]
}

resource "kubernetes_service_account_v1" "external_secrets" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace.external_secrets[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.external_secrets_irsa[0].iam_role_arn
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

  depends_on = [
    kubernetes_service_account_v1.external_secrets,
    time_sleep.wait_for_aws_load_balancer_controller_webhook,
  ]
}

resource "time_sleep" "wait_for_external_secrets_crds" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  depends_on = [helm_release.external_secrets]

  create_duration = "90s"
}

resource "helm_release" "proxy_api_key_external_secret" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  name      = "proxy-api-key-external-secret"
  chart     = abspath("${path.module}/../charts/proxy-api-key-external-secret")
  namespace = kubernetes_namespace.external_secrets[0].metadata[0].name
  timeout   = 1200

  set {
    name  = "secretStore.name"
    value = "${local.name_prefix}-aws-secrets-manager"
  }

  set {
    name  = "secretStore.awsRegion"
    value = var.region
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
    value = "proxy"
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
    name  = "externalSecret.awsSecretName"
    value = var.proxy_config.api_key_aws_secret_name
  }

  depends_on = [
    kubernetes_namespace.proxy,
    time_sleep.wait_for_external_secrets_crds,
    aws_secretsmanager_secret_version.proxy_api_key,
  ]
}

resource "time_sleep" "wait_for_proxy_api_key_sync" {
  count = local.managed_api_key_secret_enabled ? 1 : 0

  depends_on = [helm_release.proxy_api_key_external_secret]

  create_duration = "30s"
}

module "proxy" {
  source = "../modules/proxy"

  region                    = var.region
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
  enable_alb_ingress      = var.alb_config.enable_ingress
  alb_certificate_arn     = var.alb_config.certificate_arn
  proxy_ingress_host      = var.alb_config.ingress_host
  alb_scheme              = var.alb_config.scheme
  alb_ingress_annotations = {}

  enable_proxy_autoscaling                 = true
  proxy_autoscaling_min_replicas           = var.autoscaling_config.min_replicas
  proxy_autoscaling_max_replicas           = var.autoscaling_config.max_replicas
  proxy_autoscaling_target_cpu_utilization = var.autoscaling_config.target_cpu_utilization

  depends_on = [
    module.vpc,
    module.eks,
    kubernetes_namespace.proxy,
    time_sleep.wait_for_aws_load_balancer_controller_webhook,
    time_sleep.wait_for_proxy_api_key_sync,
  ]
}

locals {
  proxy_dns_target = (
    module.proxy.proxy_ingress_load_balancer_hostname != null
  ) ? module.proxy.proxy_ingress_load_balancer_hostname : module.proxy.proxy_service_load_balancer_hostname
  proxy_dns_alias_name    = local.proxy_dns_target
  proxy_dns_alias_zone_id = module.proxy.proxy_ingress_load_balancer_zone_id

  proxy_dns_name = var.dns_config.record_name != null ? var.dns_config.record_name : var.alb_config.ingress_host
}

module "proxy_dns_record" {
  source = "./modules/dns-record"

  create_record          = var.dns_config.create_record
  zone_id                = var.dns_config.zone_id
  record_name            = local.proxy_dns_name
  load_balancer_dns_name = local.proxy_dns_alias_name
  load_balancer_zone_id  = local.proxy_dns_alias_zone_id
}
