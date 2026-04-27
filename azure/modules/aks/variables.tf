variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS control plane"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group hosting the AKS cluster"
  type        = string
}

variable "location" {
  description = "Azure region for the AKS cluster"
  type        = string
}

variable "node_subnet_id" {
  description = "Subnet ID where AKS nodes are deployed"
  type        = string
}

variable "vm_size" {
  description = "VM SKU for the default node pool"
  type        = string
}

variable "node_pool_min_count" {
  description = "Minimum node count for the default node pool autoscaler"
  type        = number
}

variable "node_pool_max_count" {
  description = "Maximum node count for the default node pool autoscaler"
  type        = number
}

variable "pod_cidr" {
  description = "CIDR allocated for pods (CNI Overlay; not part of the VNet)"
  type        = string
}

variable "service_cidr" {
  description = "CIDR allocated for ClusterIP services"
  type        = string
}

variable "dns_service_ip" {
  description = "DNS service IP (must lie within service_cidr)"
  type        = string
}

variable "api_server_authorized_ranges" {
  description = "CIDRs allowed to reach the AKS API server"
  type        = list(string)
}

variable "enable_private_cluster" {
  description = "When true, the API server has only a private endpoint"
  type        = bool
}

variable "enable_log_analytics" {
  description = "When true, attach a Log Analytics workspace and enable Container Insights"
  type        = bool
}

variable "log_analytics_retention_days" {
  description = "Retention in days for the Log Analytics workspace"
  type        = number
}

variable "tags" {
  description = "Tags applied to AKS resources"
  type        = map(string)
  default     = {}
}
