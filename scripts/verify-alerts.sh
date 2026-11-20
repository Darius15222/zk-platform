#!/usr/bin/env bash
# Waits until every zk-lab detection rule has raised an alert since SINCE (run after attack.sh).
# Queries Elasticsearch as the read-only zk-triage user (scripts/es.sh). The expected count is the number of rules in
# zk-detections, so a new rule raises it without editing this script, the Makefile or CI.
# Usage: SINCE=<ISO time the attack started> verify-alerts.sh [timeout-seconds]
set -euo pipefail

here=$(dirname "$0")
want=$(grep -c . "${ZK_DETECTIONS_DIR:-$here/../../zk-detections}/rules/elastic/sigma-rules.ndjson")
deadline=$((SECONDS + ${1:-420}))
. "$here/es.sh"
err=$(mktemp)
trap 'rm -f "$err"' EXIT

q='{"size":0,"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"'"${SINCE:-now-30m}"'"}}},{"term":{"kibana.alert.rule.tags":"zk-lab"}}]}},"aggs":{"r":{"terms":{"field":"kibana.alert.rule.name","size":1000}}}}'
while :; do
  # keep the last error: at the deadline, an access problem must not read as "the rules did not fire"
  rules=$(es /.alerts-security.alerts-default/_search "$q" 2>"$err" | jq -r '.aggregations.r.buckets[]? | "\(.key): \(.doc_count)"' || true)
  got=$(grep -c . <<<"$rules" || true)
  if ((got >= want)); then
    echo "$rules"
    echo "ok   $got/$want rules alerted"
    exit 0
  fi
  if ((SECONDS > deadline)); then
    echo "${rules:-no alerts}"
    [[ -s $err ]] && { echo "last Elasticsearch error:"; tail -3 "$err"; }
    echo "FAIL only $got/$want rules alerted"
    exit 1
  fi
  sleep 15
done
