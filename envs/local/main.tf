# Elastic SIEM (ECK) behind Traefik with TLS from a lab CA (cert-manager). R-02: the only credential comes from SOPS.

locals {
  # images pinned by digest (harness/pinning.md)
  es_image     = "docker.elastic.co/elasticsearch/elasticsearch:9.5.0@sha256:8818ab9af72d7482e38a9d6f0454d5ee667564a25bbdc42360c0f9b8f8f72fc5"
  kibana_image = "docker.elastic.co/kibana/kibana:9.5.0@sha256:4d1ddf41d5488bc2d627cb43b3a5e2fc5fd05e41d34a3ae2527c902ea58993d3"
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

data "sops_file" "elastic" {
  source_file = "${path.module}/../../secrets/elastic.enc.yaml"
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
    password = data.sops_file.elastic.data["zk_admin_password"]
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
  })]
}
