data "aws_lb_hosted_zone_id" "ingress" {
  region             = var.region
  load_balancer_type = "application"
}

resource "kubernetes_ingress_v1" "this" {
  count = var.enabled ? 1 : 0

  wait_for_load_balancer = true

  metadata {
    name      = "proxy"
    namespace = var.namespace
    annotations = merge(
      {
        "alb.ingress.kubernetes.io/scheme"           = var.scheme
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/certificate-arn"  = var.certificate_arn
        "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443}]"
        "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
        "alb.ingress.kubernetes.io/healthcheck-path" = "/healthcheck"
      },
      var.additional_annotations
    )
  }

  spec {
    ingress_class_name = "alb"

    dynamic "rule" {
      for_each = var.ingress_host == null ? [] : [var.ingress_host]
      content {
        host = rule.value
        http {
          path {
            path      = "/"
            path_type = "Prefix"
            backend {
              service {
                name = var.service_name
                port {
                  number = var.service_port
                }
              }
            }
          }
        }
      }
    }

    dynamic "rule" {
      for_each = var.ingress_host == null ? [1] : []
      content {
        http {
          path {
            path      = "/"
            path_type = "Prefix"
            backend {
              service {
                name = var.service_name
                port {
                  number = var.service_port
                }
              }
            }
          }
        }
      }
    }
  }

  timeouts {
    create = "30m"
    delete = "30m"
  }
}
