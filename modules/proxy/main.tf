locals {
  proxy_namespace = "proxy"
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
