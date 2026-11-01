locals {
  repos = {
    "zk-secops-dev" = "zk-secops lab workspace: rules, docs, Claude guardrails"
    "zk-auth"       = "Minimal zero-knowledge (Schnorr) authentication service"
    "zk-platform"   = "Terraform for the zk-secops lab platform"
    "zk-detections" = "Logstash pipelines and Sigma rules with tests"
  }
}

resource "github_repository" "this" {
  # checkov:skip=CKV_GIT_1:public by design, chosen for free rulesets and secret scanning
  # checkov:skip=CKV2_GIT_1:protected by github_repository_ruleset, which replaces classic branch protection
  for_each = local.repos

  name                   = each.key
  description            = each.value
  visibility             = var.visibility
  has_issues             = true
  has_wiki               = false
  has_projects           = false
  allow_merge_commit     = false
  allow_rebase_merge     = false
  allow_squash_merge     = true
  delete_branch_on_merge = true

  dynamic "security_and_analysis" {
    for_each = var.visibility == "public" ? [1] : []
    content {
      secret_scanning {
        status = "enabled"
      }
      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# R-01: main changes only through pull requests
resource "github_repository_ruleset" "main" {
  for_each = github_repository.this

  name        = "main"
  repository  = each.value.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      # ponytail: 0 approvals because the lab has one author; raise to 1 when a reviewer joins
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      required_review_thread_resolution = true
    }
    # required_status_checks are added per repo once its CI exists (stage 3)
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  for_each = github_repository.this

  repository = each.value.name
  enabled    = true
}
