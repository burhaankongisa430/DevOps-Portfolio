# Project 5 — Observability & Security Monitoring

> **Portfolio context:** Wraps Projects 1–4 with eyes. The Prometheus analysis upgrade closes the loop on Project 3's canary: it now uses real latency data rather than a health probe. The postmortem documents what happens when the system is stressed — and why it recovered without human intervention.

Prometheus + Grafana on the cluster, AWS-native security services (GuardDuty, Security Hub, Config), Falco for runtime container monitoring, one automated remediation (EC2 isolation via Lambda), and a postmortem that ties all five projects together.

---

## Architecture

```
┌───────────────────────────────── EKS Cluster ─────────────────────────────────┐
│                                                                                  │
│  Workload (default namespace)          Monitoring (monitoring namespace)        │
│  ┌──────────────────────────┐          ┌─────────────────────────────────────┐  │
│  │  portfolio-app pods       │          │  kube-prometheus-stack              │  │
│  │  GET /metrics ◄───────────┼──scrape──│  Prometheus                         │  │
│  └──────────────────────────┘          │  Grafana      ◄── dashboards/alerts  │  │
│                                         │  Alertmanager ──► SNS ──► email      │  │
│  Falco (falco namespace)               │  node-exporter, kube-state-metrics   │  │
│  eBPF kernel tap ──► CloudWatch Logs   └─────────────────────────────────────┘  │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘

AWS Account
  GuardDuty ──► EventBridge ──► Lambda (isolate EC2) + SNS (email)
  Security Hub (aggregates GuardDuty + Config + Inspector)
  Config ──► compliance rules (encrypted volumes, no-public-S3, no-SSH-0.0.0.0/0)
  CloudTrail ──► S3 (90-day audit log)
```

---

## Why these choices

### kube-prometheus-stack over bespoke Prometheus setup
The `kube-prometheus-stack` Helm chart bundles Prometheus Operator, Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter — the complete production observability stack, deployed with one command. More importantly, it installs the Prometheus Operator's CRDs (`ServiceMonitor`, `PrometheusRule`) which let you manage scrape targets and alert rules declaratively in Git without reloading Prometheus.

### Prometheus analysis in Argo Rollouts (the Project 5 upgrade)
Project 3's AnalysisTemplate used an HTTP health probe (`/health` returning `{"status":"ok"}`). The postmortem shows why that is insufficient: the canary pods can be alive but slow. The upgrade to Prometheus queries measures error rate and p99 latency from real traffic — a failing pod that is slow rather than dead is caught in the first 30-second check interval.

### GuardDuty + Security Hub over a single tool
GuardDuty detects threats (credential misuse, crypto-mining, unusual API calls). Config detects misconfigurations (public S3, unencrypted EBS, open port 22). Security Hub aggregates both into a single findings dashboard with a security score. Together they cover the two most common sources of cloud incidents: active attacks and configuration drift.

### Conservative automated remediation
The Lambda isolates an EC2 instance by removing it from all security groups — a fast, reversible action that stops the bleeding without destroying evidence. It only runs on severity ≥ 7 EC2 findings, which prevents false-positive isolations. Crucially, it saves the original security groups to an instance tag before overwriting them, so restoration is one AWS CLI command. More aggressive automation (terminate instance, revoke IAM credentials) requires human confirmation because the cost of a false positive is too high.

### Falco for runtime, Trivy for build time
Trivy scans the image before deployment for known CVEs. Falco watches system calls at runtime for anomalous behaviour that CVE scanners cannot detect: a pod that starts a shell, opens an unexpected network connection, or writes to `/etc/`. These are different threat models covering different phases of the attack lifecycle. Both are needed.

---

## Repository structure

```
project-5-observability/
├── infra/
│   ├── modules/
│   │   ├── aws-security/       # GuardDuty, Security Hub, Config, CloudTrail, SNS
│   │   └── auto-remediation/   # EC2 isolation Lambda + EventBridge trigger
│   │       └── lambda/
│   │           └── remediate.py
│   └── environments/dev/       # Reads P1+P2 state, installs kube-prometheus-stack + Falco
├── helm/
│   ├── kube-prometheus-stack/
│   │   └── values.yaml         # Prometheus + Grafana + Alertmanager config
│   └── falco/
│       └── values.yaml         # Falco + custom portfolio-app rules
├── k8s/
│   ├── servicemonitor.yaml     # Tells Prometheus Operator to scrape the app
│   └── alerts/
│       └── prometheusrule.yaml # HighErrorRate, HighP99Latency, PodCrashLooping, OOMKilled
└── docs/
    └── postmortem-2026-06-28.md  # Simulated incident: canary latency spike
```

**Also modified in other projects:**
- `project-2-containers/app/main.go` — adds Prometheus instrumentation (`/metrics` endpoint)
- `project-2-containers/app/go.mod` — adds `prometheus/client_golang` dependency
- `project-3-gitops/helm/app/templates/analysis-template.yaml` — upgraded to Prometheus queries (with HTTP fallback)
- `project-3-gitops/helm/app/values.yaml` — adds `analysis.prometheusAddress` field

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Projects 1–4 applied | EKS cluster and pipeline must exist |
| `alert_email` | Update `terraform.tfvars` with your real email address |

---

## Deploying

```bash
cd infra/environments/dev
terraform init
terraform apply
```

After apply, apply the Kubernetes manifests:

```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name devops-portfolio-dev-eks

# ServiceMonitor + PrometheusRule
kubectl apply -f k8s/servicemonitor.yaml
kubectl apply -f k8s/alerts/prometheusrule.yaml
```

### Accessing the UIs

```bash
# Grafana (user: admin, password: changeme-in-prod)
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Open http://localhost:3000

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
# Open http://localhost:9090

# Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093
```

### Enable Prometheus canary analysis (Project 3 upgrade)

```bash
# Get the Prometheus service address
PROM_ADDR="http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

# Update the ArgoCD Application with the Prometheus address
yq -i '
  (.spec.source.helm.parameters[] | select(.name == "analysis.prometheusAddress")).value = "'${PROM_ADDR}'"
' ../project-3-gitops/argocd/apps/portfolio-app.yaml
git add ../project-3-gitops/argocd/apps/portfolio-app.yaml
git commit -m "feat: enable Prometheus canary analysis (Project 5)"
git push
```

---

## Cost estimate (Project 5 additions)

| Resource | Approx monthly cost |
|---|---|
| GuardDuty (low traffic) | ~$4 |
| Security Hub | ~$1 |
| CloudTrail (management events) | ~$0 |
| Config (rules + recording) | ~$5 |
| Lambda + EventBridge | ~$0 (free tier) |
| CloudWatch Logs (Falco) | ~$1 |
| **Project 5 subtotal** | **~$11/month** |
| Projects 1–4 | ~$213/month |
| **Combined total** | **~$224/month** |

---

## The postmortem

See [docs/postmortem-2026-06-28.md](docs/postmortem-2026-06-28.md) — a simulated incident where a canary deploy caused a latency spike. The postmortem documents:
- The 18-minute timeline from deploy to full recovery
- Why the HTTP health-check gate missed the issue
- Why the Prometheus gate (deployed in this project) would catch it in 30 seconds
- The systemic gap (no indexed query performance testing in CI) that remains open

The postmortem is written as you would for a real team: specific times, specific metrics, specific action items with owners and priorities. Reading it, a remote reviewer can see exactly how you operate when production breaks.
