variable "role_name" {
  description = "IAM role name for AWS Load Balancer Controller IRSA"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the controller service account"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Service account name for the controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "tags" {
  description = "Additional tags applied to IAM resources"
  type        = map(string)
  default     = {}
}
