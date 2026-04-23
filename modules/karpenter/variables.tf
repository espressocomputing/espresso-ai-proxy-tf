variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  type        = string
}

variable "cluster_ip_family" {
  description = "Cluster service IP family."
  type        = string
  default     = "ipv4"
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN used for IRSA trust."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnet IDs where Karpenter-launched nodes may run."
  type        = list(string)
}

variable "cluster_primary_security_group_id" {
  description = "Cluster primary security group used by Karpenter nodeclass discovery."
  type        = string
}

variable "instance_types" {
  description = "Allowed EC2 instance types for Karpenter nodes."
  type        = list(string)
  default     = ["c8i.2xlarge", "c8i.4xlarge"]
}

variable "capacity_types" {
  description = "Allowed Karpenter capacity types."
  type        = list(string)
  default     = ["on-demand"]
}

variable "cpu_limit" {
  description = "Total CPU limit for Karpenter node pool."
  type        = string
  default     = "64"
}

variable "memory_limit" {
  description = "Total memory limit for Karpenter node pool."
  type        = string
  default     = "256Gi"
}

variable "node_cap" {
  description = "Maximum number of nodes Karpenter may provision in the node pool."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
