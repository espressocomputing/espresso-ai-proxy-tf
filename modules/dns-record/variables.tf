variable "create_record" {
  description = "Whether to create the Route53 record"
  type        = bool
}

variable "zone_id" {
  description = "Route53 hosted zone ID where the record will be created"
  type        = string
}

variable "record_name" {
  description = "DNS record name"
  type        = string
}

variable "load_balancer_dns_name" {
  description = "DNS name of the target load balancer"
  type        = string
}

variable "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the target load balancer"
  type        = string
}
