locals {
  discovery_tag_key   = "karpenter.sh/discovery"
  discovery_tag_value = var.cluster_name
  private_subnet_id_map = {
    for idx, subnet_id in var.private_subnet_ids : tostring(idx) => subnet_id
  }
}

module "iam" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name                    = var.cluster_name
  cluster_ip_family               = var.cluster_ip_family
  enable_irsa                     = true
  enable_pod_identity             = false
  enable_v1_permissions           = true
  irsa_oidc_provider_arn          = var.oidc_provider_arn
  irsa_namespace_service_accounts = ["kube-system:karpenter"]
  create_pod_identity_association = false
  create_instance_profile         = false
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "KarpenterNodeRole-${var.cluster_name}"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  iam_policy_statements = [
    {
      sid       = "AllowListInstanceProfiles"
      actions   = ["iam:ListInstanceProfiles"]
      resources = ["*"]
    }
  ]
  tags = var.tags
}

resource "aws_ec2_tag" "discovery_subnets" {
  for_each = local.private_subnet_id_map

  resource_id = each.value
  key         = local.discovery_tag_key
  value       = local.discovery_tag_value
}

resource "aws_ec2_tag" "discovery_cluster_sg" {
  resource_id = var.cluster_primary_security_group_id
  key         = local.discovery_tag_key
  value       = local.discovery_tag_value
}

resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  namespace  = "kube-system"
  wait       = false
  timeout    = 300
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  namespace  = "kube-system"
  wait       = false
  timeout    = 300

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam.iam_role_arn
  }

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = var.cluster_endpoint
  }

  set {
    name  = "settings.interruptionQueue"
    value = module.iam.queue_name
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "250m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "512Mi"
  }

  depends_on = [
    module.iam,
    helm_release.karpenter_crd,
  ]
}

resource "time_sleep" "wait_for_crd_registration" {
  create_duration = "30s"

  depends_on = [
    helm_release.karpenter_crd,
    helm_release.karpenter,
  ]
}

resource "helm_release" "karpenter_resources" {
  name      = "karpenter-resources"
  chart     = "${path.module}/charts/karpenter-resources"
  namespace = "kube-system"
  wait      = false
  timeout   = 300

  values = [
    yamlencode({
      discoveryTagKey   = local.discovery_tag_key
      discoveryTagValue = local.discovery_tag_value
      role              = module.iam.node_iam_role_name
      capacityTypes     = var.capacity_types
      instanceTypes     = var.instance_types
      cpuLimit          = var.cpu_limit
      memoryLimit       = var.memory_limit
      nodeCap           = var.node_cap
      tags = merge(var.tags, {
        (local.discovery_tag_key) = local.discovery_tag_value
      })
    })
  ]

  depends_on = [
    time_sleep.wait_for_crd_registration,
    aws_ec2_tag.discovery_subnets,
    aws_ec2_tag.discovery_cluster_sg,
  ]
}
