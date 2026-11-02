#!/usr/bin/env bash
# Simulated attack on zk-auth through Traefik (TLS): one honest zk login, a replayed proof, a forged proof,
# and 25 wrong passwords. Every step asserts the expected HTTP result. Used by `make attack` and CI e2e.
# Needs: a zk-auth checkout (ZK_AUTH_DIR, default: sibling in the workspace) with node >= 26, curl, jq, kubectl.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
APP=${ZK_AUTH_DIR:-$here/../../zk-auth}
KC=${ZK_KUBECONFIG:-$HOME/.kube/config.zk-lab}
U=https://auth.${ZK_DOMAIN:-zk.local}
ca=$(mktemp)
trap 'rm -f "$ca"' EXIT
kubectl --kubeconfig "$KC" -n cert-manager get secret zk-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$ca"

c() { curl -sS --cacert "$ca" --resolve "${U#https://}:443:127.0.0.1" -H 'content-type: application/json' "$@"; }
expect() { [[ $2 == "$3" ]] && echo "ok   $1" || { echo "FAIL $1: got $2, want $3"; exit 1; }; }
prove() { (cd "$APP" && node --input-type=module -e "import {prove} from './src/schnorr.ts'; const p=prove(0x$1n,'$2','$3'); console.log(JSON.stringify({username:'$2',nonce:'$3',...p}))"); }

user=attack$RANDOM
keys=$(cd "$APP" && node src/client.ts keygen)
sk=$(jq -r .secret <<<"$keys")
expect "register zk user" "$(c -o /dev/null -w '%{http_code}' -d "{\"username\":\"$user\",\"publicKey\":\"$(jq -r .publicKey <<<"$keys")\"}" "$U/register/zk")" 201

nonce=$(c -d "{\"username\":\"$user\"}" "$U/challenge" | jq -r .nonce)
proof=$(prove "$sk" "$user" "$nonce")
expect "honest zk login" "$(c -o /dev/null -w '%{http_code}' -d "$proof" "$U/login/zk")" 200
expect "replayed proof rejected" "$(c -o /dev/null -w '%{http_code}' -d "$proof" "$U/login/zk")" 401

nonce=$(c -d "{\"username\":\"$user\"}" "$U/challenge" | jq -r .nonce)
other=$(cd "$APP" && node src/client.ts keygen | jq -r .secret)
expect "forged proof rejected" "$(c -o /dev/null -w '%{http_code}' -d "$(prove "$other" "$user" "$nonce")" "$U/login/zk")" 401

c -o /dev/null -d '{"username":"victim","password":"Correct-horse-9"}' "$U/register/password" || true
for i in $(seq 1 25); do
  code=$(c -o /dev/null -w '%{http_code}' -d "{\"username\":\"victim\",\"password\":\"guess$i\"}" "$U/login/password")
  [[ $code == 401 ]] || { echo "FAIL wrong password $i: got $code"; exit 1; }
done
echo "ok   25 wrong passwords rejected"
