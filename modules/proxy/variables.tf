variable "region" {
  description = "AWS region used for ALB hosted zone discovery"
  type        = string
}

variable "proxy_image" {
  description = "Proxy container image"
  type        = string
}

variable "proxy_replicas" {
  description = "Desired proxy pod replicas"
  type        = number
}

variable "proxy_port" {
  description = "Proxy container and service port"
  type        = number
}

variable "proxy_env" {
  description = "Environment variables for the proxy container"
  type        = map(string)
}

variable "proxy_api_key_secret_name" {
  description = "Existing Kubernetes Secret name containing ESPRESSO_AI_API_KEY. Null disables secret injection."
  type        = string
  default     = null
}

variable "enable_alb_ingress" {
  description = "Enable ALB-backed ingress for proxy"
  type        = bool
}

variable "alb_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS listener"
  type        = string
}

variable "proxy_ingress_host" {
  description = "Optional host for ingress routing"
  type        = string
  default     = null
}

variable "alb_scheme" {
  description = "ALB scheme for ingress"
  type        = string
}

variable "alb_ingress_annotations" {
  description = "Additional annotations for ALB ingress"
  type        = map(string)
}

variable "enable_proxy_autoscaling" {
  description = "Enable Horizontal Pod Autoscaler for the proxy deployment"
  type        = bool
}

variable "proxy_autoscaling_min_replicas" {
  description = "Minimum number of pods for proxy autoscaling"
  type        = number
}

variable "proxy_autoscaling_max_replicas" {
  description = "Maximum number of pods for proxy autoscaling"
  type        = number
}

variable "proxy_autoscaling_target_cpu_utilization" {
  description = "Target average CPU utilization percentage for proxy autoscaling"
  type        = number
}
