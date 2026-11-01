terraform {
  required_version = ">= 1.9"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }

  # state lives in floci on the host, outside the cluster it manages; credentials come from the Makefile
  backend "s3" {
    bucket                      = "zk-tfstate"
    key                         = "github/terraform.tfstate"
    region                      = "eu-central-1"
    endpoints                   = { s3 = "http://localhost:4566" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

provider "github" {
  owner = var.owner
}
