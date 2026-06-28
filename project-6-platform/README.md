# Project 6 — Internal Developer Platform (Capstone)

> **Portfolio context:** Wraps Projects 1–5 behind a single command interface. The platform only earns its name once the plumbing beneath it is real — which it now is.

A golden-path CLI (`portfolio`) that provisions environments, deploys services end-to-end, scaffolds new services pre-wired to the full stack, and reports health across every layer in a single command. A Backstage catalog models the system's entity hierarchy for teams that want a service portal instead of a CLI.

---

## What the CLI does

```
$ portfolio --help

 Usage: portfolio [OPTIONS] COMMAND [ARGS]...

 Golden-path CLI — provision, deploy, and monitor the DevOps portfolio platform.

╭─ Commands ──────────────────────────────────────────────────────────────────╮
│  status   Show platform health across all layers                            │
│  deploy   Build, push, and deploy a service image                          │
│  verify   Verify cosign signature on a deployed image                      │
│  new      Scaffold a new service from the golden path                      │
│  version  Print the CLI version                                             │
╰─────────────────────────────────────────────────────────────────────────────╯
```

### `portfolio status`

```
╭─────────────────────────────────────────────────────────────────╮
│  Project: devops-portfolio   Environment: dev   Region: us-east-1  │
╰─────────────────────────────────────────────────────────────────╯

  Layer             Status          Detail
  ────────────────────────────────────────────────────────────────
  EKS Cluster       ✓ Active        k8s v1.29
  App Pods          ✓ Running       sha-abc1234 · 2/2 ready
  Argo Rollout      ✓ Healthy       sha-abc1234 · 100% stable
  ArgoCD Sync       ✓ Synced        sync=Synced health=Healthy · 2026-06-28T10:14
  GuardDuty         ✓ Clean         no HIGH/CRITICAL findings

  ALB Endpoint: http://portfolio-app-k8s-xxx.us-east-1.elb.amazonaws.com
```

### `portfolio deploy`

```
$ portfolio deploy image --tag sha-abc1234
$ portfolio deploy gitops --tag sha-abc1234
```

Builds the Docker image, runs Trivy (stops if CRITICAL/HIGH CVEs found), pushes to ECR, optionally signs with cosign, then updates `portfolio-app.yaml` and pushes to Git — triggering the Project 3 ArgoCD canary.

### `portfolio new payment-service`

```
╭───────── ✓ Generated payment-service ─────────────────────────────────╮
│                                                                         │
│  payment-service/                                                       │
│  ├── app/                                                               │
│  │   ├── main.go        Go HTTP service with /health, /, /metrics      │
│  │   ├── go.mod         Module with prometheus/client_golang            │
│  │   └── Dockerfile     Multi-stage distroless build                   │
│  ├── helm/payment-service/                                              │
│  │   ├── Chart.yaml                                                     │
│  │   └── values.yaml    Argo Rollout with canary strategy               │
│  ├── argocd/
│  │   └── payment-service.yaml  ArgoCD Application                      │
│  └── catalog-info.yaml  Backstage Component registration                │
╰─────────────────────────────────────────────────────────────────────────╯

  Next steps:
    1. Move payment-service/ into your repo
    2. Copy argocd/payment-service.yaml to project-3-gitops/argocd/apps/
    3. git add . && git commit && git push
    4. portfolio deploy image --tag sha-$(git rev-parse --short HEAD)
    5. portfolio deploy gitops --tag sha-$(git rev-parse --short HEAD)
```

### `portfolio verify sha-abc1234`

```
╭─── Signature Verification ─────────────────────────────────────────────╮
│  Image:             .../devops-portfolio/dev/app:sha-abc1234           │
│  Expected identity: .../pipeline.yaml@refs/heads/main                  │
│  OIDC issuer:       https://token.actions.githubusercontent.com         │
╰─────────────────────────────────────────────────────────────────────────╯

✓ Signature verified.
  This image was built by the CI pipeline from [GITHUB_USERNAME/devops-portfolio].
```

---

## Why a CLI over a full Backstage deployment

The strategy doc offers "a golden-path template / CLI" as an alternative to Backstage, and for this portfolio the CLI is the stronger choice:

**A CLI is verifiably real.** You can run `portfolio status` in an interview and a reviewer sees live output from the actual cluster. Backstage requires a running Node.js server, a database, and configured plugins to demonstrate — much harder to show in 10 minutes.

**A CLI tests the platform end-to-end.** The `deploy` command exercises ECR, Docker, yq, git, and AWS credentials in sequence — any gap in the platform shows immediately. A portal abstracts those gaps behind UI buttons.

**A CLI shows you understand the toolchain.** Writing a CLI that wraps Terraform, kubectl, and Docker shows you know what each tool does and when to use it — not just how to click through a portal. Backstage is appropriate when the platform is mature and the audience is application developers who shouldn't need to know the tools. This portfolio is the platform itself, and the CLI demonstrates its depth.

The Backstage catalog (`backstage/catalog-info.yaml`) is included to show familiarity with the entity model — it can be registered in any Backstage instance to make the portfolio discoverable.

---

## Repository structure

```
project-6-platform/
├── cli/
│   └── portfolio/
│       ├── main.py               # typer app, all commands wired
│       ├── commands/
│       │   ├── deploy.py         # build → scan → push → gitops update
│       │   ├── status.py         # rich table: EKS + pods + ArgoCD + GuardDuty
│       │   ├── verify.py         # cosign signature verification
│       │   └── new_service.py    # golden-path service scaffolding
│       └── utils/
│           ├── config.py         # .portfolio.yaml loader
│           └── shell.py          # subprocess helpers with Rich output
├── backstage/
│   └── catalog-info.yaml         # System, Components, Resources, APIs, User, Group
├── .portfolio.yaml.example       # Config template to copy and fill in
└── docs/
    └── platform-overview.md
```

---

## Installation

```bash
# From the project-6-platform/cli directory:
pip install -e .

# Verify:
portfolio --help
portfolio version
```

### Setup

```bash
# 1. Copy and fill in the config file at the monorepo root
cp project-6-platform/.portfolio.yaml.example .portfolio.yaml
# Edit .portfolio.yaml with your account ID, cluster name, github repo, etc.

# 2. Set AWS credentials (any standard method)
export AWS_PROFILE=devops-portfolio   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY

# 3. Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name devops-portfolio-dev-eks

# 4. Test
portfolio status
```

---

## The golden path: onboarding a new service in 5 commands

```bash
# 1. Scaffold the service
portfolio new payment-service

# 2. Push to Git (triggers nothing yet — GitOps needs the ArgoCD Application first)
cp payment-service/argocd/payment-service.yaml project-3-gitops/argocd/apps/
git add . && git commit -m "feat: add payment-service" && git push

# 3. Build and push the image
cd payment-service
portfolio deploy image --tag sha-$(git rev-parse --short HEAD)

# 4. Update the GitOps manifest (triggers ArgoCD canary)
portfolio deploy gitops --tag sha-$(git rev-parse --short HEAD)

# 5. Watch the canary
portfolio status
```

From `portfolio new` to running in production: 5 commands, ~10 minutes (mostly waiting for the ALB to provision). The new service inherits all security defaults from Projects 1–5: distroless image, IRSA, canary progressive delivery, Trivy scanning, Prometheus metrics, Falco runtime monitoring.

---

## The portfolio as a whole

```
Project 1: terraform apply          → VPC, EKS, RDS, ALB
Project 2: docker build && push     → containerised Go app on EKS
Project 3: argocd sync              → canary progressive delivery
Project 4: github actions           → 5-gate secure pipeline
Project 5: prometheus + guardduty   → observability + security monitoring
Project 6: portfolio new/deploy     → developer self-service over P1–P5
                                      ↑
                              This project — the capstone
```

Each project is independently deployable but reads state from its predecessors via Terraform remote state. The CLI is the surface that makes this system feel like a product rather than six separate repositories.
