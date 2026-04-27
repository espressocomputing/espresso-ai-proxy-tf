variable "region" {
  description = "AWS region used for ALB hosted zone discovery"
  type        = string
}

variable "enabled" {
  description = "Whether to create the ALB ingress"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Kubernetes namespace where the ingress is created"
  type        = string
}

variable "service_name" {
  description = "Kubernetes service name to back the ingress"
  type        = string
}

variable "service_port" {
  description = "Kubernetes service port to back the ingress"
  type        = number
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener"
  type        = string
}

variable "ingress_host" {
  description = "Optional host for ingress routing. When null, a host-less rule is created."
  type        = string
  default     = null
}

variable "scheme" {
  description = "ALB scheme (internet-facing or internal)"
  type        = string
}

variable "additional_annotations" {
  description = "Additional annotations to merge onto the Ingress"
  type        = map(string)
  default     = {}
}
