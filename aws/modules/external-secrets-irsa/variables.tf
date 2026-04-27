variable "role_name" {
  description = "IAM role name for External Secrets Operator IRSA"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for External Secrets Operator service account"
  type        = string
  default     = "external-secrets"
}

variable "service_account_name" {
  description = "Service account name for External Secrets Operator"
  type        = string
  default     = "external-secrets"
}

variable "role_policy_arns" {
  description = "Policy ARNs to attach to the IRSA role"
  type        = map(string)
}

variable "tags" {
  description = "Additional tags applied to IAM resources"
  type        = map(string)
  default     = {}
}
