# Project 3 — GitOps Continuous Delivery

> **Portfolio context:** Installs on the EKS cluster from Project 2. Deployments are now driven entirely by Git — no one runs `helm install` manually any more.

ArgoCD as the GitOps engine, Argo Rollouts for canary progressive delivery, and a documented rollback runbook to provide safe releases and failure modes ( as apposed to merely deploying something).

---

## Architecture

```
Developer pushes image tag change to Git
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Repository (source of truth)                            │
│  argocd/apps/portfolio-app.yaml  ◄── update image.tag, push    │
└──────────────────────┬──────────────────────────────────────────┘
                       │  ArgoCD polls every 30s (or webhook)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  ArgoCD  (argocd namespace)                                     │
│  Detects drift → triggers Helm sync → Rollout controller takes  │
│  over from here                                                 │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  Argo Rollouts  (argo-rollouts namespace)                       │
│                                                                  │
│  Step 1: setWeight 20%  ──► 20% traffic to canary pods         │
│  Step 2: pause 30s/2m                                           │
│  Step 3: AnalysisRun    ──► GET canary-svc/health × 3–5        │
│          status=="ok"?  ──► continue  │  ✗ abort               │
│  Step 4: setWeight 50%                │                         │
│  Step 5: pause 30s/2m                 ▼                        │
│  Step 6: setWeight 100%       100% traffic back to stable      │
│                               (automatic, no manual step)       │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  ALB  (from Project 1 VPC, managed by AWS Load Balancer Ctrl)  │
│  ┌──────────────────────────┬───────────────────────────────┐  │
│  │  stable-svc  (80–100%)   │  canary-svc  (0–20–50%)       │  │
│  │  old pods                │  new pods                     │  │
│  └──────────────────────────┴───────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why these choices

### GitOps over imperative deploys
With plain `helm upgrade`, the deployment state lives in the engineer's shell history. With GitOps, the state lives in Git — every deploy is a commit, every rollback is a revert, every team member can see exactly what is running and why. ArgoCD continuously reconciles, so if someone applies a manual change to the cluster, it is detected and corrected within `timeout.reconciliation` (30 seconds).

### Argo Rollouts over plain Kubernetes rolling updates
A standard `Deployment` rolling update swaps all pods with no traffic control. If the new version has a bug, 100% of users are affected before you can react. Argo Rollouts uses two Services and ALB weighted target groups so only the configured percentage of real traffic hits the new version. The AnalysisRun then evaluates it automatically. The feedback loop takes minutes, not an on-call page at 3am.

### Analysis at the cluster level, not the pipeline level
Shipping a container image through the pipeline proves the image builds and tests pass. An AnalysisRun proves the image works under real production traffic. These are different things. The analysis here checks the canary's `/health` endpoint — a weak gate, but intentionally so for Project 3. Project 5 upgrades it to Prometheus-backed error rate and p99 latency queries, which is the production-grade version.

### App-of-Apps pattern
The root Application watches `argocd/apps/` in Git. Adding a new service is a `git add` + `git push` — no `kubectl apply` needed, no human needs to log into the cluster. This is how to scale GitOps beyond a single application.

### `ignoreDifferences` on the Ingress
Argo Rollouts dynamically modifies the ALB Ingress annotation during a canary to adjust traffic weights. Without `ignoreDifferences`, ArgoCD would see the modified annotation as drift and revert it — interrupting the canary mid-flight. The ignore rule scopes precisely to that one annotation, everything else is still reconciled.

---

## Repository structure

```
project-3-gitops/
├── infra/
│   └── environments/dev/     # Terraform: installs ArgoCD + Argo Rollouts on P2's EKS
├── argocd/
│   ├── projects/
│   │   └── portfolio.yaml    # AppProject (RBAC scope)
│   └── apps/
│       ├── root.yaml         # App-of-Apps root Application
│       └── portfolio-app.yaml  # Application for the portfolio service
├── helm/
│   └── app/
│       ├── Chart.yaml
│       ├── values.yaml         # Defaults (2m pauses, 5 analysis checks)
│       ├── values-dev.yaml     # Overrides (30s pauses, 3 checks)
│       └── templates/
│           ├── rollout.yaml           # Argo Rollout (replaces Deployment)
│           ├── service-stable.yaml    # Stable traffic sink
│           ├── service-canary.yaml    # Canary traffic sink
│           ├── ingress.yaml           # ALB ingress with use-annotation backend
│           ├── analysis-template.yaml # HTTP health gate
│           ├── hpa.yaml               # HPA targeting Rollout (not Deployment)
│           ├── serviceaccount.yaml
│           └── configmap.yaml
├── docs/
│   └── runbook-rollback.md   # Abort, promote, emergency revert procedures
└── scripts/
    ├── bootstrap.sh   # First-time: Terraform apply + root Application install
    ├── promote.sh     # kubectl argo rollouts promote
    ├── abort.sh       # kubectl argo rollouts abort
    └── teardown.sh
```

---

## Prerequisites

| Tool | Notes |
|---|---|
| Project 2 applied | EKS cluster must exist |
| `kubectl argo rollouts` plugin | `brew install argoproj/tap/kubectl-argo-rollouts` or GitHub releases |
| GitHub repo | Push this project to GitHub before bootstrapping — ArgoCD needs to pull from Git |

---

## First-time setup

### 1. Point ArgoCD at your repo

Update the `repoURL` in both files:
- [argocd/apps/root.yaml](argocd/apps/root.yaml)
- [argocd/apps/portfolio-app.yaml](argocd/apps/portfolio-app.yaml)

Also update `image.repository` in `portfolio-app.yaml` with your ECR URL from Project 2:
```bash
cd ../project-2-containers/infra/environments/dev
terraform output ecr_repository_url
```

### 2. Run bootstrap

```bash
# Fill in state_bucket in terraform.tfvars first
bash scripts/bootstrap.sh
```

This installs ArgoCD and Argo Rollouts via Terraform, waits for them to be ready, then applies the root Application. ArgoCD syncs the rest automatically.

### 3. Access the UIs

```bash
# ArgoCD UI (http://localhost:8080, user: admin)
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Password:
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d

# Argo Rollouts dashboard (http://localhost:3100)
kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100
```

---

## Triggering a canary deploy

```bash
# 1. Build and push a new image (from Project 2)
cd ../project-2-containers
bash scripts/build-push.sh
# Note the sha-<git-sha> tag

# 2. Update the image tag in Git (this is the GitOps trigger)
cd ../project-3-gitops
sed -i "s/value: \".*\"/value: \"sha-<git-sha>\"/" argocd/apps/portfolio-app.yaml
git add argocd/apps/portfolio-app.yaml
git commit -m "deploy: sha-<git-sha>"
git push

# ArgoCD detects the change within 30s and triggers the Rollout.
# Watch progress:
kubectl argo rollouts get rollout app -n default --watch
```

### Manual operations during a rollout

```bash
# Promote past the current pause
bash scripts/promote.sh

# Promote all remaining steps at once
bash scripts/promote.sh --full

# Abort (traffic instantly returns to 100% stable)
bash scripts/abort.sh
```

---

## What a successful canary looks like

```
Name:            app
Namespace:       default
Status:          ॥ Paused
Strategy:        Canary
  Step:          2/6
  SetWeight:     20
  ActualWeight:  20

Images:
  sha-abc1234 (canary)
  sha-def5678 (stable)

Replicas:
  Desired:  4
  Current:  4
  Updated:  1   ← 1 pod running new image (20%)
  Ready:    4
  Available: 4
```

After the AnalysisRun passes and promotion completes:
```
Status:          ✔ Healthy
  Step:          6/6
  SetWeight:     100
  ActualWeight:  100
```

---

## Rollback

See [docs/runbook-rollback.md](docs/runbook-rollback.md) for the full procedure covering: automatic analysis-triggered abort, manual abort, post-abort retry, and emergency Git revert.

---

## Cost

Project 3 adds no new AWS resources — ArgoCD and Argo Rollouts run as pods on the existing EKS cluster from Project 2. Combined running cost remains ~$213/month (Projects 1 + 2). Run `bash scripts/teardown.sh` to remove the components from the cluster without destroying the cluster itself.
