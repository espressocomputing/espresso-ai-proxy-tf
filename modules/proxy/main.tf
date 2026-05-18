locals {
  proxy_namespace = "proxy"

  otel_collector_enabled     = var.otel_collector.enabled
  otel_customer_enabled      = local.otel_collector_enabled && var.otel_collector.customer_endpoint != ""
  otel_customer_exporter_key = var.otel_collector.customer_protocol == "http" ? "otlphttp/customer" : "otlp/customer"

  otel_collector_config = local.otel_collector_enabled ? templatefile("${path.module}/files/otel-collector-config.yaml.tftpl", {
    espresso_endpoint     = var.otel_collector.espresso_endpoint
    customer_enabled      = local.otel_customer_enabled
    customer_endpoint     = var.otel_collector.customer_endpoint
    customer_auth         = var.otel_collector.customer_auth_secret_name != ""
    customer_tls_insecure = var.otel_collector.customer_tls_insecure
    customer_signals      = var.otel_collector.customer_signals
    customer_exporter_key = local.otel_customer_exporter_key
  }) : ""
}

resource "kubernetes_config_map_v1" "otel_collector" {
  count = local.otel_collector_enabled ? 1 : 0

  metadata {
    name      = "proxy-otel-collector"
    namespace = local.proxy_namespace
  }

  data = {
    "config.yaml" = local.otel_collector_config
  }
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = "proxy"
    namespace = local.proxy_namespace
    labels = {
      app = "proxy"
    }
  }

  spec {
    replicas = var.proxy_replicas
    strategy {
      type = "RollingUpdate"
    }

    selector {
      match_labels = {
        app = "proxy"
      }
    }

    template {
      metadata {
        labels = {
          app = "proxy"
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "proxy"
          image = var.proxy_image

          port {
            container_port = var.proxy_port
          }

          readiness_probe {
            http_get {
              path = "/healthcheck"
              port = var.proxy_port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/healthcheck"
              port = var.proxy_port
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            timeout_seconds       = 2
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "1000m"
              memory = "2048Mi"
            }
            limits = {
              cpu    = "1500m"
              memory = "3072Mi"
            }
          }

          dynamic "env" {
            for_each = var.proxy_env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = var.proxy_api_key_secret_name == null ? [] : [1]
            content {
              name = "ESPRESSO_AI_API_KEY"
              value_from {
                secret_key_ref {
                  name = var.proxy_api_key_secret_name
                  key  = "ESPRESSO_AI_API_KEY"
                }
              }
            }
          }
        }

        dynamic "container" {
          for_each = local.otel_collector_enabled ? [1] : []
          content {
            name              = "otel-collector"
            image             = var.otel_collector.image
            image_pull_policy = var.otel_collector.image_pull_policy
            args              = ["--config=/etc/otelcol/config.yaml"]

            port {
              name           = "otlp-grpc"
              container_port = 4317
              protocol       = "TCP"
            }
            port {
              name           = "otlp-http"
              container_port = 4318
              protocol       = "TCP"
            }

            dynamic "env" {
              for_each = var.proxy_api_key_secret_name == null ? [] : [1]
              content {
                name = "ESPRESSO_AI_API_KEY"
                value_from {
                  secret_key_ref {
                    name = var.proxy_api_key_secret_name
                    key  = "ESPRESSO_AI_API_KEY"
                  }
                }
              }
            }

            dynamic "env" {
              for_each = var.otel_collector.customer_auth_secret_name == "" ? [] : [1]
              content {
                name = "CUSTOMER_OTLP_AUTH"
                value_from {
                  secret_key_ref {
                    name = var.otel_collector.customer_auth_secret_name
                    key  = var.otel_collector.customer_auth_secret_key
                  }
                }
              }
            }

            volume_mount {
              name       = "otel-collector-config"
              mount_path = "/etc/otelcol"
            }

            resources {
              requests = {
                cpu    = var.otel_collector.resources.requests.cpu
                memory = var.otel_collector.resources.requests.memory
              }
              limits = {
                cpu    = var.otel_collector.resources.limits.cpu
                memory = var.otel_collector.resources.limits.memory
              }
            }
          }
        }

        dynamic "volume" {
          for_each = local.otel_collector_enabled ? [1] : []
          content {
            name = "otel-collector-config"
            config_map {
              name = kubernetes_config_map_v1.otel_collector[0].metadata[0].name
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name        = "proxy"
    namespace   = local.proxy_namespace
    annotations = {}
  }

  spec {
    selector = {
      app = "proxy"
    }

    port {
      port        = var.proxy_port
      target_port = var.proxy_port
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  count = var.enable_proxy_autoscaling ? 1 : 0

  metadata {
    name      = "proxy"
    namespace = local.proxy_namespace
  }

  spec {
    min_replicas = var.proxy_autoscaling_min_replicas
    max_replicas = var.proxy_autoscaling_max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }

    metric {
      type = "Resource"

      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.proxy_autoscaling_target_cpu_utilization
        }
      }
    }
  }
}
