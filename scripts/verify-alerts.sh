#!/usr/bin/env bash
# Waits until every zk-lab detection rule has raised an alert since SINCE (run after attack.sh).
# Queries Elasticsearch from inside its pod with the ECK "elastic" user; the password is never printed.
# Usage: SINCE=<ISO time the attack started> verify-alerts.sh [expected-rule-count] [timeout-seconds]
set -euo pipefail

want=${1:-4}
deadline=$((SECONDS + ${2:-420}))
K="kubectl --kubeconfig ${ZK_KUBECONFIG:-$HOME/.kube/config.zk-lab} -n siem"

es() {
  local pw
  pw=$($K get secret elasticsearch-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
  $K exec elasticsearch-es-default-0 -c elasticsearch -- \
    curl -sk -u "elastic:$pw" -H 'content-type: application/json' "https://localhost:9200$1" -d "$2"
}

q='{"size":0,"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"'"${SINCE:-now-30m}"'"}}},{"term":{"kibana.alert.rule.tags":"zk-lab"}}]}},"aggs":{"r":{"terms":{"field":"kibana.alert.rule.name"}}}}'
while :; do
  rules=$(es /.alerts-security.alerts-default/_search "$q" 2>/dev/null | jq -r '.aggregations.r.buckets[]? | "\(.key): \(.doc_count)"' || true)
  got=$(grep -c . <<<"$rules" || true)
  if ((got >= want)); then
    echo "$rules"
    echo "ok   $got/$want rules alerted"
    exit 0
  fi
  if ((SECONDS > deadline)); then
    echo "${rules:-no alerts}"
    echo "FAIL only $got/$want rules alerted"
    exit 1
  fi
  sleep 15
done
