resource "aws_route53_record" "this" {
  count = var.create_record ? 1 : 0

  zone_id = var.zone_id
  name    = var.record_name
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition     = try(trim(var.zone_id, " ") != "", false)
      error_message = "dns_config.zone_id must be set when dns_config.create_record is true."
    }

    precondition {
      condition     = try(trim(var.record_name, " ") != "", false)
      error_message = "dns_config.record_name or alb_config.ingress_host must be set when dns_config.create_record is true."
    }

    precondition {
      condition     = try(trim(var.load_balancer_dns_name, " ") != "", false)
      error_message = "dns_config.load_balancer_dns_name must be set when dns_config.create_record is true."
    }

    precondition {
      condition     = try(trim(var.load_balancer_zone_id, " ") != "", false)
      error_message = "dns_config.load_balancer_zone_id must be set when dns_config.create_record is true."
    }
  }
}
