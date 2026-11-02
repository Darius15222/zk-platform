# zk-auth: the monitored application. Its stdout (ECS JSON) is collected by Elastic Agent.

resource "kubernetes_namespace_v1" "zk_auth" {
  metadata {
    name = "zk-auth"
  }
}

resource "kubernetes_deployment_v1" "zk_auth" {
  # checkov:skip=CKV_K8S_14:image is pinned by digest, which is stronger than a tag
  # checkov:skip=CKV_K8S_43:image is pinned by digest (var.zk_auth_image)
  metadata {
    name      = "zk-auth"
    namespace = kubernetes_namespace_v1.zk_auth.metadata[0].name
    labels    = { app = "zk-auth" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "zk-auth" }
    }

    template {
      metadata {
        labels = { app = "zk-auth" }
      }

      spec {
        automount_service_account_token = false

        security_context {
          run_as_non_root = true
          run_as_user     = 65532 # distroless nonroot
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = "zk-auth"
          image             = var.zk_auth_image
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          env {
            name  = "TRUST_PROXY" # Traefik sets X-Forwarded-For; source.ip is the real client
            value = "1"
          }

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "zk_auth" {
  metadata {
    name      = "zk-auth"
    namespace = kubernetes_namespace_v1.zk_auth.metadata[0].name
  }
  spec {
    selector = { app = "zk-auth" }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "zk_auth" {
  metadata {
    name        = "zk-auth"
    namespace   = kubernetes_namespace_v1.zk_auth.metadata[0].name
    annotations = { "cert-manager.io/cluster-issuer" = "zk-ca" }
  }
  spec {
    ingress_class_name = "traefik"
    tls {
      hosts       = ["auth.${var.domain}"]
      secret_name = "auth-tls"
    }
    rule {
      host = "auth.${var.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.zk_auth.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

# only the ingress controller (kube-system) may reach zk-auth
resource "kubernetes_network_policy_v1" "zk_auth" {
  metadata {
    name      = "zk-auth-ingress-only"
    namespace = kubernetes_namespace_v1.zk_auth.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = { app = "zk-auth" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}
