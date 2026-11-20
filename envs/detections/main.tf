# R-05: Sigma rules from zk-detections (compiled to ES|QL by its rules/build.sh, committed, drift-checked by its CI) become Elastic Security detection rules.

variable "kibana_url" {
  type    = string
  default = "https://kibana.zk.local"
}

variable "ca_cert" {
  description = "PEM of the lab root CA (public), written by `make detections`"
  type        = string
  default     = "zk-root-ca.crt"
}

variable "detections_dir" {
  description = "path to a zk-detections checkout; empty = the sibling folder in the workspace"
  type        = string
  default     = ""
}

locals {
  detections_dir = abspath(var.detections_dir != "" ? var.detections_dir : "${path.module}/../../../zk-detections")
  rules = {
    for line in split("\n", trimspace(file("${local.detections_dir}/rules/elastic/sigma-rules.ndjson"))) :
    jsondecode(line).rule_id => jsondecode(line)
  }
}

resource "elasticstack_kibana_security_detection_rule" "sigma" {
  for_each = local.rules

  rule_id     = each.key
  name        = each.value.name
  description = each.value.description
  type        = each.value.type
  language    = each.value.language
  query       = each.value.query
  index       = null # every rule is ES|QL, which reads its index from the query
  severity    = each.value.severity
  risk_score  = each.value.risk_score
  # ponytail: 1m keeps the lab demo snappy; the correlation window (5m) is inside the query
  interval        = "1m"
  from            = each.value.from
  to              = each.value.to
  enabled         = true
  max_signals     = each.value.max_signals
  author          = each.value.author
  tags            = concat(each.value.tags, ["zk-lab", "sigma"])
  false_positives = each.value.false_positives

  threat = [for t in each.value.threat : {
    framework = t.framework
    tactic    = t.tactic
    technique = [for tech in try(t.technique, []) : {
      id           = tech.id
      name         = tech.name
      reference    = tech.reference
      subtechnique = try(tech.subtechnique, null)
    }]
  }]
}

# R-05: the zk-lab dashboard (logins by outcome, failure reasons, alerts by rule, top source IPs), exported from Kibana.
# overwrite: the file in zk-detections is the source of truth; edits made in the UI are replaced on the next apply.
resource "elasticstack_kibana_import_saved_objects" "dashboard" {
  file_contents = file("${local.detections_dir}/dashboards/zk-lab.ndjson")
  overwrite     = true
}

output "rules" {
  value = { for k, r in elasticstack_kibana_security_detection_rule.sigma : r.name => k }
}
