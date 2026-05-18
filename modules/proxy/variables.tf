variable "proxy_image" {
  description = "Proxy container image"
  type        = string

  validation {
    condition     = trim(var.proxy_image, " ") != ""
    error_message = "proxy_image must be a non-empty container image reference."
  }
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

variable "otel_collector" {
  description = "OTEL collector sidecar configuration. When enabled, deploys a sidecar that receives OTLP from the proxy on localhost and fans out to the Espresso ingress and an optional customer endpoint."
  type = object({
    enabled                   = optional(bool, false)
    image                     = optional(string, "otel/opentelemetry-collector-contrib:0.152.0")
    image_pull_policy         = optional(string, "IfNotPresent")
    espresso_endpoint         = optional(string, "https://metrics.espressocomputing.com:443")
    customer_endpoint         = optional(string, "")
    customer_protocol         = optional(string, "grpc")
    customer_signals          = optional(list(string), ["traces", "metrics", "logs"])
    customer_auth_secret_name = optional(string, "")
    customer_auth_secret_key  = optional(string, "authorization")
    customer_tls_insecure     = optional(bool, false)
    resources = optional(object({
      requests = optional(object({
        cpu    = optional(string, "50m")
        memory = optional(string, "128Mi")
      }), {})
      limits = optional(object({
        cpu    = optional(string, "200m")
        memory = optional(string, "256Mi")
      }), {})
    }), {})
  })
  default = {}

  validation {
    condition     = contains(["grpc", "http"], var.otel_collector.customer_protocol)
    error_message = "otel_collector.customer_protocol must be grpc or http."
  }

  validation {
    condition = alltrue([
      for s in var.otel_collector.customer_signals : contains(["traces", "metrics", "logs"], s)
    ])
    error_message = "otel_collector.customer_signals values must be one of traces, metrics, logs."
  }

  validation {
    condition     = !var.otel_collector.enabled || trim(var.otel_collector.espresso_endpoint, " ") != ""
    error_message = "otel_collector.espresso_endpoint must be non-empty when otel_collector.enabled is true."
  }
}
