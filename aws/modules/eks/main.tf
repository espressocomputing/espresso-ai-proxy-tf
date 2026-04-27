
module "this" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                  = var.cluster_name
  cluster_version               = var.cluster_version
  bootstrap_self_managed_addons = var.bootstrap_self_managed_addons

  cluster_endpoint_public_access         = var.cluster_endpoint_public_access
  cluster_endpoint_private_access        = var.cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs   = var.cluster_endpoint_public_access_cidrs
  create_cloudwatch_log_group            = var.create_cloudwatch_log_group
  cloudwatch_log_group_retention_in_days = var.cloudwatch_log_group_retention_in_days

  enable_cluster_creator_admin_permissions = true

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  cluster_addons = {
    coredns = { most_recent = true }

    kube-proxy = { most_recent = true }

    vpc-cni = {
      before_compute = true
      most_recent    = true
    }
  }

  eks_managed_node_groups = {
    espresso-ai-proxy = {
      instance_types = var.instance_types

      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      tags = var.tags
    }
  }

  tags = var.tags
}
