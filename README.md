# zk-platform

Infrastructure as code for the [zk-secops lab](https://github.com/Darius15222/zk-secops-dev). Terraform deploys the whole lab onto a local k3d cluster:

- the TLS chain;
- a self-hosted Elastic SIEM;
- log and network collection;
- the zk-auth service;
- the network policies.

It also manages the GitHub settings of every lab repository. The same code runs on a laptop (`make up`) and in CI, where every pull request builds the cluster, runs a simulated attack and waits for the alerts.

## What gets deployed

| Component | Namespace | Role |
|---|---|---|
| cert-manager | `cert-manager` | Lab root CA and ClusterIssuer; TLS for every ingress |
| ECK operator | `elastic-system` | Runs Elasticsearch and Kibana |
| Elasticsearch, Kibana | `siem` | The SIEM; Kibana at `https://kibana.zk.local` |
| Elastic Agent (DaemonSet) | `siem` | Ships zk-auth pod logs (already ECS) and Suricata `eve.json` |
| Logstash | `siem` | Maps Suricata events to ECS with the pipeline from zk-detections |
| Suricata (DaemonSet) | `ids` | Network IDS on the pod bridge, with the rules from zk-detections |
| zk-auth | `zk-auth` | The monitored service, signed image pinned by digest, at `https://auth.zk.local` |
| NetworkPolicies | `siem`, `zk-auth` | Only the traffic the SIEM needs reaches it (R-08) |
| Detection rules, dashboard | Kibana | Sigma rules compiled by zk-detections, loaded as Elastic Security rules |

## Layout

```
envs/
├── local/        the lab: cert-manager, ECK, agent, Logstash, Suricata, zk-auth, network policies
└── detections/   Elastic Security rules and the dashboard, read from the sibling zk-detections checkout
github/           repository rulesets for all lab repositories (R-01): PR required, no force-push, no deletion
scripts/
├── attack.sh         simulated attack: honest login, replayed proof, forged proof, 25 wrong passwords
├── verify-alerts.sh  waits for one alert per detection rule
├── verify-netpol.sh  pods outside siem must not reach Elasticsearch or Logstash
├── alerts.sh         read-only JSON of recent alerts for triage
└── es.sh             Elasticsearch access as the read-only zk-triage user
secrets/          SOPS-encrypted secrets (ciphertext only)
Makefile          entry point for every workflow
.github/workflows/
├── ci.yml        fmt, validate, tflint, checkov, signature check, then e2e: k3d + apply + attack + alerts
└── ai-review.yml advisory AI security review of the diff
```

Terraform state lives in an S3 bucket in floci, a local AWS emulator, so nothing leaves the machine. CI uses a local backend instead.

## Technologies and why

| Technology | Used for | Why |
|---|---|---|
| Terraform | Everything above | One declarative, reviewable description of the lab; `plan` shows every change before it happens |
| k3d (k3s in Docker) | Cluster | A real Kubernetes in seconds on one machine, with Traefik ingress built in; the same in CI |
| ECK | Elasticsearch, Kibana | The official operator handles certificates, users and upgrades |
| cert-manager | TLS | A lab CA that issues certificates for every ingress; HTTPS only |
| Elastic Agent, Logstash | Collection | Agent reads pod logs and Suricata output; Logstash normalizes Suricata to ECS |
| Suricata | Network IDS | Sees HTTP between Traefik and the pods, so a login burst is visible on the wire too |
| SOPS + age | Secrets (R-02) | Secrets are committed only as ciphertext; decryption happens only in `make` targets the user runs |
| cosign | Supply chain (R-03) | CI deploys only a zk-auth digest signed by zk-auth's own CI on `main` |
| GitHub provider | Rulesets (R-01) | Branch protection is code too: drift shows up in `make github-plan` |

## Commands

Run from a lab clone (see the workspace's `docs/running-locally/local-stack.md` for prerequisites):

| Command | Does |
|---|---|
| `make up` | Starts floci, the registry and the cluster, applies `envs/local`, loads the detection rules |
| `make attack` | Simulated attack, then waits for one alert per rule |
| `make triage MIN=30` | Read-only JSON of the alerts of the last 30 minutes |
| `make netpol` | Checks the SIEM network policy |
| `make plan` | Plan of `envs/local` |
| `make github-plan` / `github-apply` | Repository rulesets; apply is for humans |
| `make down` | Stops the cluster (state and data are kept) |

Never `terraform apply` outside `envs/local` by hand: `envs/detections` is applied only by `make up` / `make detections`, and `github` only by its own target.
