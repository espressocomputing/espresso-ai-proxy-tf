variable "name" {
  description = "Name for the user-assigned managed identity and the federated credential"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group hosting the managed identity"
  type        = string
}

variable "location" {
  description = "Azure region for the managed identity"
  type        = string
}

variable "oidc_issuer_url" {
  description = "AKS OIDC issuer URL used as the federated-credential issuer"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account this identity is bound to"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name this identity is bound to"
  type        = string
}

variable "tags" {
  description = "Tags applied to the managed identity"
  type        = map(string)
  default     = {}
}
