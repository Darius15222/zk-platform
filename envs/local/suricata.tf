# Suricata IDS on the node's pod bridge (cni0): sees Traefik -> pod HTTP. Writes eve.json to the host for Elastic Agent.

resource "kubernetes_namespace_v1" "ids" {
  metadata {
    name = "ids"
  }
}

resource "kubernetes_config_map_v1" "suricata_rules" {
  metadata {
    name      = "suricata-rules"
    namespace = kubernetes_namespace_v1.ids.metadata[0].name
  }
  data = {
    "local.rules" = file("${local.detections_dir}/rules/suricata/local.rules")
  }
}

resource "kubernetes_daemon_set_v1" "suricata" {
  # checkov:skip=CKV_K8S_19:packet capture needs the host network namespace
  # checkov:skip=CKV_K8S_20:the image entrypoint drops to the suricata user after binding the interface
  # checkov:skip=CKV_K8S_22:the image writes its default config to /etc/suricata at start
  # checkov:skip=CKV_K8S_23:entrypoint starts as root to set capabilities, Suricata then runs as the suricata user
  # checkov:skip=CKV_K8S_28:NET_ADMIN is required to put the interface in capture mode
  # checkov:skip=CKV_K8S_37:only NET_ADMIN, NET_RAW and SYS_NICE are added, everything else is dropped
  # checkov:skip=CKV_K8S_40:entrypoint needs uid 0 to switch to the suricata user
  # checkov:skip=CKV_K8S_43:image is pinned by digest
  # checkov:skip=CKV_K8S_8:no liveness endpoint in Suricata; the process exiting restarts the pod
  # checkov:skip=CKV_K8S_9:no readiness endpoint in Suricata
  # checkov:skip=CKV_K8S_14:image is pinned by digest, which is stronger than a tag
  # checkov:skip=CKV_K8S_38:the service account token is not mounted (automount disabled)
  metadata {
    name      = "suricata"
    namespace = kubernetes_namespace_v1.ids.metadata[0].name
  }

  spec {
    selector {
      match_labels = { app = "suricata" }
    }
    template {
      metadata {
        labels = { app = "suricata" }
        # restart Suricata when its rules change
        annotations = { "zk-lab/rules-sha" = sha256(kubernetes_config_map_v1.suricata_rules.data["local.rules"]) }
      }
      spec {
        host_network                    = true
        dns_policy                      = "ClusterFirstWithHostNet"
        automount_service_account_token = false

        security_context {
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "suricata"
          image = "jasonish/suricata:8.0.8@sha256:d5a3a1785299ab40918d465e54fedf8e3afeeedba76bb64b0cc74dbc20bda2c3"
          args  = ["-i", "cni0", "-S", "/zk-rules/local.rules"]

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
              add  = ["NET_ADMIN", "NET_RAW", "SYS_NICE", "CHOWN", "SETUID", "SETGID", "DAC_OVERRIDE", "FOWNER", "SETPCAP"] # SETPCAP: libcap-ng drops to the suricata user
            }
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }

          volume_mount {
            name       = "eve"
            mount_path = "/var/log/suricata"
          }
          volume_mount {
            name       = "rules"
            mount_path = "/zk-rules" # outside /etc/suricata: the entrypoint chowns that tree
            read_only  = true
          }
        }

        volume {
          name = "eve"
          host_path {
            path = "/var/log/suricata"
            type = "DirectoryOrCreate"
          }
        }
        volume {
          name = "rules"
          config_map {
            name = kubernetes_config_map_v1.suricata_rules.metadata[0].name
          }
        }
      }
    }
  }
}
