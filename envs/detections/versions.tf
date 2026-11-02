terraform {
  required_version = ">= 1.9"

  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "0.16.6"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }

  backend "s3" {
    bucket                      = "zk-tfstate"
    key                         = "detections/terraform.tfstate"
    region                      = "eu-central-1"
    endpoints                   = { s3 = "http://localhost:4566" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

data "sops_file" "elastic" {
  source_file = "${path.module}/../../secrets/elastic.enc.yaml"
}

provider "elasticstack" {
  kibana {
    endpoints = [var.kibana_url]
    username  = "zk-admin"
    password  = data.sops_file.elastic.data["zk_admin_password"]
    ca_certs  = [var.ca_cert] # lab root CA, exported by `make detections`
  }
  # the provider requires an Elasticsearch block even when only Kibana resources are managed
  elasticsearch {
    endpoints = ["https://localhost:9200"]
    username  = "zk-admin"
    password  = data.sops_file.elastic.data["zk_admin_password"]
    insecure  = true # never contacted: no Elasticsearch resources in this stack
  }
}
