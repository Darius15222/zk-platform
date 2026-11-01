terraform {
  required_version = ">= 1.9"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.4.0"
    }
    # applies CRD-based manifests (cert-manager issuers) without needing the CRD at plan time
    kubectl = {
      source  = "alekc/kubectl"
      version = "3.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }

  backend "s3" {
    bucket                      = "zk-tfstate"
    key                         = "local/terraform.tfstate"
    region                      = "eu-central-1"
    endpoints                   = { s3 = "http://localhost:4566" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig)
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand(var.kubeconfig)
  }
}

provider "kubectl" {
  config_path      = pathexpand(var.kubeconfig)
  load_config_file = true
}
