# Elastic SIEM (ECK) behind Traefik with TLS from a lab CA (cert-manager). R-02: the only credential comes from SOPS.

locals {
  # images pinned by digest (harness/pinning.md)
  es_image       = "docker.elastic.co/elasticsearch/elasticsearch:9.5.0@sha256:8818ab9af72d7482e38a9d6f0454d5ee667564a25bbdc42360c0f9b8f8f72fc5"
  kibana_image   = "docker.elastic.co/kibana/kibana:9.5.0@sha256:4d1ddf41d5488bc2d627cb43b3a5e2fc5fd05e41d34a3ae2527c902ea58993d3"
  agent_image    = "docker.elastic.co/elastic-agent/elastic-agent:9.5.0@sha256:b623e37ffbb75ca5c16c46a8e6ccdc68c8a48adb20ab30f2c7d48d3ffda1d084"
  logstash_image = "docker.elastic.co/logstash/logstash:9.5.0@sha256:b08a2b7767573295e6a53b72214ca42522c4c7a8edbbc7e0af8ef470dcf2f2d3"

  # zk-detections is checked out next to zk-platform (workspace repos/); pipelines and rules come from there
  detections_dir = abspath(var.detections_dir != "" ? var.detections_dir : "${path.module}/../../../zk-detections")

  # $${...} are Logstash env vars injected by ECK for elasticsearchRefs clusterName "eck"
  suricata_pipeline = <<-EOT
    input { elastic_agent { port => 5044 } }
    ${file("${local.detections_dir}/pipelines/suricata.conf")}
    output {
      elasticsearch {
        hosts => ["$${ECK_ES_HOSTS}"]
        user => "$${ECK_ES_USER}"
        password => "$${ECK_ES_PASSWORD}"
        ssl_certificate_authorities => "$${ECK_ES_SSL_CERTIFICATE_AUTHORITY}"
        data_stream => true
      }
    }
  EOT
}

# --- TLS: lab root CA -> ClusterIssuer "zk-ca"

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.3"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  set = [{ name = "crds.enabled", value = "true" }]
}

resource "kubectl_manifest" "selfsigned_issuer" {
  depends_on = [helm_release.cert_manager]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: selfsigned
    spec:
      selfSigned: {}
  YAML
}

resource "kubectl_manifest" "root_ca" {
  depends_on = [kubectl_manifest.selfsigned_issuer]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: zk-root-ca
      namespace: cert-manager
    spec:
      isCA: true
      commonName: zk-lab Root CA
      secretName: zk-root-ca
      duration: 8760h
      privateKey:
        algorithm: ECDSA
        size: 256
      issuerRef:
        name: selfsigned
        kind: ClusterIssuer
  YAML
}

resource "kubectl_manifest" "ca_issuer" {
  depends_on = [kubectl_manifest.root_ca]
  yaml_body  = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: zk-ca
    spec:
      ca:
        secretName: zk-root-ca
  YAML
}

# --- Elastic: ECK operator, then Elasticsearch + Kibana

resource "helm_release" "eck_operator" {
  name             = "elastic-operator"
  repository       = "https://helm.elastic.co"
  chart            = "eck-operator"
  version          = "3.5.0"
  namespace        = "elastic-system"
  create_namespace = true
  wait             = true
}

resource "kubernetes_namespace_v1" "siem" {
  metadata {
    name = "siem"
  }
}

# SOPS is the source of the zk-admin password; CI passes an ephemeral one instead (no repo secrets needed)
variable "zk_admin_password" {
  description = "CI only: overrides the SOPS secret when set"
  type        = string
  default     = ""
  sensitive   = true
}

data "sops_file" "elastic" {
  count       = var.zk_admin_password == "" ? 1 : 0
  source_file = "${path.module}/../../secrets/elastic.enc.yaml"
}

locals {
  zk_admin_password = var.zk_admin_password != "" ? var.zk_admin_password : data.sops_file.elastic[0].data["zk_admin_password"]
}

# file-realm user for humans; the built-in "elastic" superuser stays an ECK-generated secret
resource "kubernetes_secret_v1" "zk_admin" {
  metadata {
    name      = "zk-admin"
    namespace = kubernetes_namespace_v1.siem.metadata[0].name
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "zk-admin"
    password = local.zk_admin_password
    roles    = "superuser"
  }
}

resource "helm_release" "eck_stack" {
  depends_on = [helm_release.eck_operator, kubectl_manifest.ca_issuer]

  name       = "siem"
  chart      = "eck-stack"
  repository = "https://helm.elastic.co"
  version    = "0.20.0"
  namespace  = kubernetes_namespace_v1.siem.metadata[0].name

  values = [yamlencode({
    eck-elasticsearch = {
      image = local.es_image
      auth  = { fileRealm = [{ secretName = kubernetes_secret_v1.zk_admin.metadata[0].name }] }
      nodeSets = [{
        name   = "default"
        count  = 1
        config = { "node.store.allow_mmap" = false }
        resources = {
          requests = { cpu = "500m", memory = "2Gi" }
          limits   = { memory = "2Gi" }
        }
      }]
    }
    eck-kibana = {
      image = local.kibana_image
      # Traefik terminates TLS with the cert-manager certificate; Kibana serves plain HTTP inside the cluster
      http = { tls = { selfSignedCertificate = { disabled = true } } }
      ingress = {
        enabled     = true
        className   = "traefik"
        annotations = { "cert-manager.io/cluster-issuer" = "zk-ca" }
        hosts       = [{ host = "kibana.${var.domain}", path = "/" }]
        tls         = { enabled = true, secretName = "kibana-tls" }
      }
    }

    # R-04: collectors. zk-auth logs are ECS already and go straight to Elasticsearch;
    # Suricata eve.json goes through Logstash for the ECS mapping tested in zk-detections.
    eck-agent = {
      enabled           = true
      fullnameOverride  = "elastic-agent"
      image             = local.agent_image
      elasticsearchRefs = [{ name = "elasticsearch" }]
      config = {
        id = "zk-lab-agent"
        outputs = {
          # ponytail: plain TCP inside the cluster; add TLS (cert-manager) if Logstash is exposed outside
          logstash = { type = "logstash", hosts = ["logstash-ls-beats.${kubernetes_namespace_v1.siem.metadata[0].name}.svc:5044"] }
        }
        inputs = [
          {
            id          = "zk-auth-logs"
            type        = "filestream"
            use_output  = "default"
            data_stream = { namespace = "default" }
            streams = [{
              id          = "zk-auth"
              data_stream = { dataset = "zkauth" }
              paths       = ["/var/log/pods/${kubernetes_namespace_v1.zk_auth.metadata[0].name}_zk-auth-*/zk-auth/*.log"] # real files; /var/log/containers holds symlinks filestream skips
              parsers = [
                { container = {} },
                { ndjson = { target = "", overwrite_keys = true, add_error_key = true } },
              ]
            }]
          },
          {
            id          = "suricata-eve"
            type        = "filestream"
            use_output  = "logstash"
            data_stream = { namespace = "default" }
            streams = [{
              id          = "suricata"
              data_stream = { dataset = "suricata" }
              paths       = ["/var/log/suricata/eve.json"]
            }]
          },
        ]
      }
      daemonSet = {
        podTemplate = {
          spec = {
            serviceAccountName           = "elastic-agent"
            automountServiceAccountToken = true
            securityContext              = { runAsUser = 0 } # reads host log files
            containers = [{
              name      = "agent"
              resources = { requests = { cpu = "100m", memory = "300Mi" }, limits = { memory = "700Mi" } }
              volumeMounts = [
                { name = "varlogcontainers", mountPath = "/var/log/containers", readOnly = true },
                { name = "varlogpods", mountPath = "/var/log/pods", readOnly = true },
                { name = "suricata", mountPath = "/var/log/suricata", readOnly = true },
              ]
            }]
            volumes = [
              { name = "varlogcontainers", hostPath = { path = "/var/log/containers" } },
              { name = "varlogpods", hostPath = { path = "/var/log/pods" } },
              { name = "suricata", hostPath = { path = "/var/log/suricata", type = "DirectoryOrCreate" } },
            ]
          }
        }
      }
    }

    eck-logstash = {
      enabled           = true
      fullnameOverride  = "logstash"
      image             = local.logstash_image
      elasticsearchRefs = [{ clusterName = "eck", name = "elasticsearch" }]
      pipelines = [{
        "pipeline.id"   = "suricata"
        "config.string" = local.suricata_pipeline
      }]
      services = [{
        name    = "beats"
        service = { spec = { type = "ClusterIP", ports = [{ port = 5044, name = "beats", protocol = "TCP", targetPort = 5044 }] } }
      }]
      podTemplate = {
        spec = {
          containers = [{
            name      = "logstash"
            env       = [{ name = "LS_JAVA_OPTS", value = "-Xms512m -Xmx512m" }]
            resources = { requests = { cpu = "250m", memory = "1Gi" }, limits = { memory = "1Gi" } }
          }]
        }
      }
    }
  })]
}
