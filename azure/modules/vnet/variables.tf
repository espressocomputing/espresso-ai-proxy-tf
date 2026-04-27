variable "vnet_name" {
  description = "Name of the dedicated VNet"
  type        = string
}

variable "address_space" {
  description = "VNet address space (one or more CIDR blocks)"
  type        = list(string)
}

variable "node_subnet_name" {
  description = "Name of the AKS node subnet"
  type        = string
  default     = "aks-nodes"
}

variable "node_subnet_cidr" {
  description = "CIDR for the AKS node subnet"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group hosting the VNet"
  type        = string
}

variable "location" {
  description = "Azure region for the VNet"
  type        = string
}

variable "tags" {
  description = "Tags applied to VNet resources"
  type        = map(string)
  default     = {}
}
