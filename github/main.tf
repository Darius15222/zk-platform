locals {
  repos = {
    "zk-secops-dev" = "zk-secops lab workspace: rules, docs, Claude guardrails"
    "zk-auth"       = "Minimal zero-knowledge (Schnorr) authentication service"
    "zk-platform"   = "Terraform for the zk-secops lab platform"
    "zk-detections" = "Logstash pipelines and Sigma rules with tests"
  }

  # CI job names each repo must pass before merging; a repo joins once its CI exists on main
  required_checks = {
    "zk-auth"       = ["test", "scan", "image"]
    "zk-detections" = ["test", "scan"]
  }
  github_actions_app_id = 15368 # only GitHub Actions may report these checks
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

    dynamic "required_status_checks" {
      for_each = contains(keys(local.required_checks), each.key) ? [1] : []
      content {
        strict_required_status_checks_policy = true
        dynamic "required_check" {
          for_each = local.required_checks[each.key]
          content {
            context        = required_check.value
            integration_id = local.github_actions_app_id
          }
        }
      }
    }
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  for_each = github_repository.this

  repository = each.value.name
  enabled    = true
}
