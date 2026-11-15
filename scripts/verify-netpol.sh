#!/usr/bin/env bash
# R-08 check: a pod outside the siem namespace must not reach Elasticsearch or Logstash; a pod inside must.
# The outside pod is zk-auth itself (the workload an attacker would land in), using its own node binary: no extra image.
# k3s rejects denied traffic instead of dropping it, so "blocked" shows up as a refused connection or a timeout;
# the same port answering from inside the namespace proves the refusal is the policy, not a missing listener.
set -uo pipefail

K="kubectl --kubeconfig ${ZK_KUBECONFIG:-$HOME/.kube/config.zk-lab}"
probe='const s=require("net").connect({host:process.argv[1],port:+process.argv[2],timeout:4000});s.on("connect",()=>{console.log("open");process.exit(0)});s.on("timeout",()=>{console.log("blocked (timeout)");process.exit(0)});s.on("error",e=>{console.log("blocked ("+e.code+")");process.exit(0)})'
fail=0
expect() { [[ $2 == $3* ]] && echo "ok   $1 -> $2" || { echo "FAIL $1 -> $2, want $3"; fail=1; }; }

outside() { $K -n zk-auth exec deploy/zk-auth -- /nodejs/bin/node -e "$probe" "$1" "$2" 2>&1 | tail -1; }
inside() { # pod host port, with bash /dev/tcp from an Elastic image
  $K -n siem exec "$1" -- bash -c "timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3' && echo open || echo blocked" 2>/dev/null | tail -1
}

expect "outside: zk-auth pod to Elasticsearch 9200" "$(outside elasticsearch-es-http.siem.svc 9200)" blocked
expect "outside: zk-auth pod to Logstash 5044" "$(outside logstash-ls-beats.siem.svc 5044)" blocked
expect "inside: Logstash pod to Elasticsearch 9200" "$(inside logstash-ls-0 elasticsearch-es-http.siem.svc 9200)" open
expect "inside: Elasticsearch pod to Logstash 5044" "$(inside elasticsearch-es-default-0 logstash-ls-beats.siem.svc 5044)" open

exit $fail
