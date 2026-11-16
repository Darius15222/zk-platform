# R-08: the SIEM namespace accepts only the traffic it needs. Without this, any pod in the cluster
# (a compromised zk-auth, for example) can reach Elasticsearch on 9200 and Logstash on 5044.
# Ingress only: egress stays open. zk-auth has its own policy in zk-auth.tf.
# Not covered, on purpose: ids (Suricata runs on the host network, where NetworkPolicy does not apply),
# cert-manager and elastic-system (their webhooks are called by the API server from the node).

locals {
  siem = kubernetes_namespace_v1.siem.metadata[0].name
}

resource "kubernetes_network_policy_v1" "siem_default_deny" {
  metadata {
    name      = "default-deny-ingress"
    namespace = local.siem
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# Elasticsearch, Kibana, Logstash and Elastic Agent talk to each other inside the namespace
# ponytail: any port between siem pods; split per port if an untrusted workload ever joins the namespace
resource "kubernetes_network_policy_v1" "siem_internal" {
  metadata {
    name      = "allow-same-namespace"
    namespace = local.siem
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

# Traefik (kube-system) is the only way in to Kibana
resource "kubernetes_network_policy_v1" "siem_kibana_ingress" {
  metadata {
    name      = "kibana-from-ingress-controller"
    namespace = local.siem
  }
  spec {
    pod_selector {
      match_labels = { "common.k8s.elastic.co/type" = "kibana" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
      }
      ports {
        port     = "5601"
        protocol = "TCP"
      }
    }
  }
}

# the ECK operator manages Elasticsearch through its HTTP API
resource "kubernetes_network_policy_v1" "siem_es_operator" {
  metadata {
    name      = "elasticsearch-from-eck-operator"
    namespace = local.siem
  }
  spec {
    pod_selector {
      match_labels = { "common.k8s.elastic.co/type" = "elasticsearch" }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "elastic-system" }
        }
      }
      ports {
        port     = "9200"
        protocol = "TCP"
      }
    }
  }
}
