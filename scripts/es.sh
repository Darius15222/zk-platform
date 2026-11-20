# Sourced by alerts.sh and verify-alerts.sh. `es <path> <json>` runs a search from inside the Elasticsearch pod as
# zk-triage, the read-only file-realm user (R-09, envs/local/main.tf). The password goes to curl on stdin (-K -), so it
# never appears in a command line (ps) on the host or in the pod, and it is never printed.
K="kubectl --kubeconfig ${ZK_KUBECONFIG:-$HOME/.kube/config.zk-lab} -n siem --request-timeout=30s"

es() {
  $K get secret zk-triage -o go-template='user = "zk-triage:{{.data.password | base64decode}}"{{"\n"}}' |
    $K exec -i elasticsearch-es-default-0 -c elasticsearch -- \
      curl -sk --max-time 30 -K - -H 'content-type: application/json' "https://localhost:9200$1" -d "$2"
}
