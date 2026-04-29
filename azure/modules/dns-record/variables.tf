variable "create_record" {
  description = "When true, create the A record"
  type        = bool
}

variable "zone_name" {
  description = "Name of the existing Azure DNS zone"
  type        = string
}

variable "zone_resource_group_name" {
  description = "Resource group hosting the Azure DNS zone"
  type        = string
}

variable "record_name" {
  description = "Record name relative to the zone (use @ for the apex)"
  type        = string
}

variable "target_ip" {
  description = "Public IP address the A record should resolve to"
  type        = string
}

variable "ttl" {
  description = "TTL in seconds"
  type        = number
}

variable "tags" {
  description = "Tags applied to the DNS record"
  type        = map(string)
  default     = {}
}
