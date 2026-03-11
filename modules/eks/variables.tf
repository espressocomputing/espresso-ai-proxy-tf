variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "EKS cluster Kubernetes version"
  type        = string
}

variable "bootstrap_self_managed_addons" {
  description = "Whether to bootstrap self-managed addons on cluster creation"
  type        = bool
}

variable "cluster_endpoint_public_access" {
  description = "Expose EKS API endpoint publicly"
  type        = bool
}

variable "cluster_endpoint_private_access" {
  description = "Expose EKS API endpoint privately"
  type        = bool
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Allowed CIDR blocks for public access to the EKS API endpoint"
  type        = list(string)
}

variable "create_cloudwatch_log_group" {
  description = "Whether to create a CloudWatch log group for EKS control plane logs"
  type        = bool
  default     = false
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Retention period in days for the EKS CloudWatch log group"
  type        = number
  default     = 90
}

variable "vpc_id" {
  description = "VPC ID for EKS cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS control plane and nodes"
  type        = list(string)
}

variable "instance_types" {
  description = "Allowed EC2 instance types for the EKS managed node group"
  type        = list(string)
  default     = ["c8i.2xlarge", "c8i.4xlarge"]
}

variable "node_group_min_size" {
  description = "Minimum EKS node count"
  type        = number
}

variable "node_group_desired_size" {
  description = "Desired EKS node count"
  type        = number
}

variable "node_group_max_size" {
  description = "Maximum EKS node count"
  type        = number
}

variable "tags" {
  description = "Additional tags applied to AWS resources"
  type        = map(string)
  default     = {}
}
