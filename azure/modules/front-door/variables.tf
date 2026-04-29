variable "name_prefix" {
  description = "Prefix for AFD resource names (e.g. cluster_name)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group hosting the AFD profile."
  type        = string
}

variable "sku_name" {
  description = "AFD SKU. Standard_AzureFrontDoor is sufficient for managed certs and wildcard custom domains; Premium_AzureFrontDoor adds WAF and Private Link to origin."
  type        = string
  default     = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku_name)
    error_message = "sku_name must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "custom_domain_host" {
  description = "The custom domain to associate with the AFD endpoint. Wildcards (e.g. *.example.com) are supported."
  type        = string
}

variable "origin_host" {
  description = "Hostname or IP of the origin (AKS LB public IP)."
  type        = string
}

variable "origin_https_port" {
  description = "HTTPS port on the origin."
  type        = number
  default     = 443
}

variable "origin_http_port" {
  description = "HTTP port on the origin."
  type        = number
  default     = 80
}

variable "health_probe_path" {
  description = "Path the AFD health probe targets on the origin."
  type        = string
  default     = "/healthcheck"
}

variable "tags" {
  description = "Tags applied to AFD resources."
  type        = map(string)
  default     = {}
}
