variable "region" {
  description = "AWS region for the on-prem proxy deployment"
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

variable "create_dedicated_vpc" {
  description = "When true, provision a dedicated VPC. When false, use existing_vpc_config."
  type        = bool
  default     = true
}

variable "vpc_config" {
  description = "Dedicated VPC configuration used when create_dedicated_vpc is true."
  type = object({
    vpc_name             = optional(string, "espresso-ai-proxy-vpc")
    cidr                 = optional(string)
    public_subnet_cidrs  = optional(list(string), [])
    private_subnet_cidrs = optional(list(string), [])
    availability_zones   = optional(list(string), [])
  })
  default = {}

  validation {
    condition = (
      !var.create_dedicated_vpc ||
      length(var.vpc_config.public_subnet_cidrs) > 0
    )
    error_message = "At least one public subnet CIDR block is required when create_dedicated_vpc is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vpc ||
      length(var.vpc_config.private_subnet_cidrs) > 0
    )
    error_message = "At least one private subnet CIDR block is required when create_dedicated_vpc is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vpc ||
      length(var.vpc_config.private_subnet_cidrs) ==
      length(var.vpc_config.public_subnet_cidrs)
    )
    error_message = "Private and public subnet CIDR counts must match when create_dedicated_vpc is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vpc ||
      length(var.vpc_config.availability_zones) == length(var.vpc_config.private_subnet_cidrs)
    )
    error_message = "vpc_config.availability_zones must match the number of private subnets when create_dedicated_vpc is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vpc ||
      length(var.vpc_config.availability_zones) > 0
    )
    error_message = "At least one availability zone is required in vpc_config.availability_zones when create_dedicated_vpc is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vpc ||
      try(var.vpc_config.cidr, null) != null
    )
    error_message = "vpc_config.cidr must be set when create_dedicated_vpc is true."
  }

  validation {
    condition = (
      !var.create_dedicated_vpc ||
      can(cidrnetmask(var.vpc_config.cidr))
    )
    error_message = "vpc_config.cidr must be a valid CIDR block when create_dedicated_vpc is true."
  }

  validation {
    condition = (
      try(var.vpc_config.vpc_name, null) == null ||
      trim(var.vpc_config.vpc_name, " ") != ""
    )
    error_message = "vpc_config.vpc_name must be null or a non-empty string."
  }
}

variable "existing_vpc_config" {
  description = "Existing VPC configuration used when create_dedicated_vpc is false."
  type = object({
    vpc_id             = string
    private_subnet_ids = list(string)
    public_subnet_ids  = optional(list(string), [])
  })
  default = null

  validation {
    condition = (
      var.create_dedicated_vpc ||
      var.existing_vpc_config != null
    )
    error_message = "existing_vpc_config must be provided when create_dedicated_vpc is false."
  }

  validation {
    condition = (
      var.existing_vpc_config == null ||
      trim(var.existing_vpc_config.vpc_id, " ") != ""
    )
    error_message = "existing_vpc_config.vpc_id must be a non-empty string."
  }

  validation {
    condition = (
      var.existing_vpc_config == null ||
      length(var.existing_vpc_config.private_subnet_ids) > 0
    )
    error_message = "existing_vpc_config.private_subnet_ids must include at least one subnet ID."
  }
}

variable "eks_config" {
  description = "EKS cluster and node group configuration"
  type = object({
    cluster_name                           = optional(string, "espresso-ai-proxy")
    cluster_version                        = optional(string, "1.35")
    bootstrap_self_managed_addons          = optional(bool, false)
    cluster_endpoint_public_access         = optional(bool, true)
    cluster_endpoint_private_access        = optional(bool, true)
    cluster_endpoint_public_access_cidrs   = optional(list(string), [])
    create_cloudwatch_log_group            = optional(bool, false)
    cloudwatch_log_group_retention_in_days = optional(number, 90)
    instance_types                         = optional(list(string), ["c8i.2xlarge", "c8i.4xlarge"])
    node_group_min_size                    = optional(number, 2)
    node_group_desired_size                = optional(number, 2)
    node_group_max_size                    = optional(number, 10)
  })
  default = {}

  validation {
    condition = (
      var.eks_config.node_group_desired_size >= var.eks_config.node_group_min_size
    )
    error_message = "eks_config.node_group_desired_size must be greater than or equal to eks_config.node_group_min_size."
  }

  validation {
    condition = (
      var.eks_config.node_group_max_size >= var.eks_config.node_group_desired_size
    )
    error_message = "eks_config.node_group_max_size must be greater than or equal to eks_config.node_group_desired_size."
  }

  validation {
    condition = (
      !var.eks_config.cluster_endpoint_public_access ||
      length(var.eks_config.cluster_endpoint_public_access_cidrs) > 0
    )
    error_message = "eks_config.cluster_endpoint_public_access_cidrs must be set when eks_config.cluster_endpoint_public_access is true."
  }

  validation {
    condition = alltrue([
      for cidr in var.eks_config.cluster_endpoint_public_access_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "eks_config.cluster_endpoint_public_access_cidrs must contain valid CIDR blocks."
  }

  validation {
    condition     = length(var.eks_config.instance_types) > 0
    error_message = "eks_config.instance_types must include at least one instance type."
  }
}

variable "karpenter_config" {
  description = "Karpenter NodePool tuning configuration."
  type = object({
    instance_types = optional(list(string), ["c8i.2xlarge", "c8i.4xlarge"])
    capacity_types = optional(list(string), ["on-demand"])
    cpu_limit      = optional(string, "64")
    memory_limit   = optional(string, "256Gi")
    node_cap       = optional(number, 10)
  })
  default = {}

  validation {
    condition     = try(var.karpenter_config.node_cap, 10) > 0
    error_message = "karpenter_config.node_cap must be greater than 0."
  }
}

variable "proxy_config" {
  description = "Proxy application runtime configuration"
  type = object({
    image                       = string
    replicas                    = optional(number, 2)
    proxy_host                  = string
    otel_exporter_otlp_endpoint = optional(string, "https://metrics.espressocomputing.com:443")
    api_key_secret_name         = optional(string, "espresso-ai")
    api_key_secret_mode         = optional(string, "BYO_K8S_SECRET")
    api_key_aws_secret_name     = optional(string, "/espresso-ai/proxy/api-key")
    api_url                     = optional(string, "https://api.espressocomputing.com:25831")
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
      ["BYO_K8S_SECRET", "MANAGED_AWS_SECRETS_MANAGER"],
      try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET")
    )
    error_message = "proxy_config.api_key_secret_mode must be BYO_K8S_SECRET or MANAGED_AWS_SECRETS_MANAGER."
  }

  validation {
    condition = (
      try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET") != "MANAGED_AWS_SECRETS_MANAGER" ||
      (
        try(var.proxy_config.api_key_aws_secret_name, null) != null &&
        trim(var.proxy_config.api_key_aws_secret_name, " ") != ""
      )
    )
    error_message = "proxy_config.api_key_aws_secret_name must be set when proxy_config.api_key_secret_mode is MANAGED_AWS_SECRETS_MANAGER."
  }

  validation {
    condition     = trim(var.proxy_config.proxy_host, " ") != ""
    error_message = "proxy_config.proxy_host must be set to a non-empty value."
  }

  validation {
    condition     = trim(var.proxy_config.otel_exporter_otlp_endpoint, " ") != ""
    error_message = "proxy_config.otel_exporter_otlp_endpoint must be non-empty."
  }
}

variable "proxy_api_key_value" {
  description = "Value for ESPRESSO_AI_API_KEY when proxy_config.api_key_secret_mode is MANAGED_AWS_SECRETS_MANAGER."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition = (
      try(var.proxy_config.api_key_secret_mode, "BYO_K8S_SECRET") != "MANAGED_AWS_SECRETS_MANAGER" ||
      (var.proxy_api_key_value != null && trim(var.proxy_api_key_value, " ") != "")
    )
    error_message = "proxy_api_key_value must be set when proxy_config.api_key_secret_mode is MANAGED_AWS_SECRETS_MANAGER."
  }
}

variable "alb_config" {
  description = "ALB ingress configuration for the proxy"
  type = object({
    enable_ingress  = optional(bool, true)
    certificate_arn = optional(string)
    ingress_host    = optional(string)
    scheme          = optional(string, "internet-facing")
  })
  default = {}

  validation {
    condition = contains(
      ["internet-facing", "internal"],
      var.alb_config.scheme
    )
    error_message = "alb_config.scheme must be internet-facing or internal."
  }

  validation {
    condition = (
      !var.alb_config.enable_ingress ||
      (try(var.alb_config.certificate_arn, null) != null && trim(var.alb_config.certificate_arn, " ") != "")
    )
    error_message = "alb_config.certificate_arn must be set when alb_config.enable_ingress is true."
  }
}

variable "dns_config" {
  description = "Route53 DNS record configuration for proxy ingress"
  type = object({
    create_record = optional(bool, false)
    zone_id       = optional(string)
    record_name   = optional(string)
  })
  default = {}

  validation {
    condition = (
      !var.dns_config.create_record ||
      (var.dns_config.zone_id != null && trim(var.dns_config.zone_id, " ") != "")
    )
    error_message = "dns_config.zone_id must be set when dns_config.create_record is true."
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

variable "tags" {
  description = "Additional tags applied to AWS resources"
  type        = map(string)
  default     = {}
}
