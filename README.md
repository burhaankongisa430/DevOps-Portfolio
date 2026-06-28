# AWS DevSecOps Portfolio

A portfolio of six connected AWS DevSecOps projects that together form a production-grade platform: 
Terraform infrastructure, containerised workloads on EKS, GitOps progressive delivery, a secure CI/CD pipeline, full-stack observability, and a developer-facing CLI that ties it all together.

Each project is a genuine layer that the next one runs on top of, they are not six independent tutorials. Project 2's application runs in the VPC from Project 1. Project 3's ArgoCD deploys to Project 2's cluster. Project 4's pipeline scans Project 1's Terraform, builds Project 2's container, and ships it through Project 3's GitOps. Project 5 monitors everything and upgrades Project 3's canary analysis. Project 6 wraps all five layers behind a single CLI so a developer can provision an environment and deploy a new service in five commands.

The security spine runs through every project. Every repository is named "DevSecOps" deliberately: IAM least-privilege in Project 1, IRSA and distroless images in Project 2, ArgoCD self-healing in Project 3, seven automated security gates in Project 4, GuardDuty and Falco in Project 5, and cosign signature verification built into the CLI in Project 6.

Each project folder contains its own detailed README covering architecture, design decisions (the *why* behind each choice), deployment guide, and cost notes.

---

## Portfolio at a Glance

| # | Project | Layer | Key Tools |
|---|---------|-------|-----------|
| 1 | [Infrastructure as Code](#project-1--infrastructure-as-code) | Foundation | Terraform, VPC, IAM, RDS |
| 2 | [Containers & Orchestration](#project-2--containers--orchestration) | Workload | Docker, EKS, Helm, IRSA |
| 3 | [GitOps Continuous Delivery](#project-3--gitops-continuous-delivery) | Delivery | ArgoCD, Argo Rollouts, canary |
| 4 | [Secure CI/CD Pipeline](#project-4--secure-cicd-pipeline) | Security spine | GitHub Actions, Trivy, cosign, OPA |
| 5 | [Observability & Security Monitoring](#project-5--observability--security-monitoring) | Operations | Prometheus, Grafana, GuardDuty, Falco |
| 6 | [Internal Developer Platform](#project-6--internal-developer-platform) | Self-service | portfolio CLI, Backstage catalog |

---

## Project Summaries

### Project 1 — Infrastructure as Code

**Folder:** `project-1-iac/`

A reproducible, modular AWS environment in Terraform: 
VPC with a three-tier subnet layout (public, private, database), Application Load Balancer, Auto Scaling Group with IMDSv2 enforcement, RDS PostgreSQL with SSL forced and no public endpoint, and S3-backed remote state with a DynamoDB lock table. The entire environment applies and destroys cleanly with a single command.

**What it demonstrates:** Modular Terraform design (each component is a reusable module with its own variables and outputs), least-privilege IAM using SSM Session Manager instead of SSH, and the operational discipline of treating Terraform state as a production artefact from day one.

**Why it comes first:** Every subsequent project inherits this VPC, these subnets, and these security group patterns. Building on an existing VPC rather than embedding infrastructure assumptions directly into Project 2 or 3 is what separates "production-shaped" from "tutorial clone." Later projects state will be consumed via `terraform_remote_state` (multi-stack Terraform).

**Key design decisions:** Three-tier subnets over a flat VPC (tier isolation prevents a compromised EC2 instance from reaching the database directly); single NAT gateway for dev (saves ~$32/month, toggled by a variable); RDS `force_ssl = 1` in the parameter group; `prevent_destroy` on the state bucket.

---

### Project 2 — Containers & Orchestration

**Folder:** `project-2-containers/`

A Go HTTP service compiled into a distroless container image (~10 MB), deployed to an Amazon EKS managed cluster that runs inside Project 1's VPC. The Helm chart uses Argo Rollouts (canary-capable from the start), topology spread constraints to spread pods across availability zones, and full pod security hardening. The AWS Load Balancer Controller creates an ALB for ingress; pod-level IAM uses IRSA rather than the node role.

**What it demonstrates:** Multi-stage Docker builds (golang:alpine builder → distroless final), Kubernetes-native deployment with Helm, IRSA for least-privilege pod IAM, and the `terraform_remote_state` pattern for consuming upstream project outputs without duplicating infrastructure.

**How it builds on Project 1:** The EKS cluster and all its nodes live in Project 1's private subnets. The ALB is placed in Project 1's public subnets, tagged by Project 2's Terraform for AWS Load Balancer Controller auto-discovery. Project 1's VPC security groups are extended (not replaced) to allow pod-to-database traffic. This is to have cross-stack dependency management, not just "here is a cluster."

**Key design decisions:** Distroless final image (no shell, no package manager — attack surface near-zero); IRSA over node-level IAM (a compromised pod cannot reach AWS APIs the node role permits); `use-annotation` backend port in the Ingress (required for Argo Rollouts ALB traffic splitting in Project 3).

---

### Project 3 — GitOps Continuous Delivery

**Folder:** `project-3-gitops/`

ArgoCD installed on Project 2's EKS cluster as the GitOps engine, Argo Rollouts driving a canary progressive delivery strategy, and the App-of-Apps pattern managing all ArgoCD Applications declaratively in Git. A deploy is triggered by updating an image tag in Git and pushing. No `helm upgrade` or `kubectl apply` runs manually. An AnalysisRun health-checks the canary before promoting traffic; a failed analysis aborts automatically and returns all traffic to the stable version.

**What it demonstrates:** GitOps reconciliation (ArgoCD detects and corrects drift within 30 seconds), progressive delivery (ALB traffic weights managed by Argo Rollouts during the canary), App-of-Apps pattern (adding a new service is a `git push`), and `ignoreDifferences` on the Ingress annotation (required so ArgoCD doesn't revert the in-flight canary weights mid-deploy).

**How it builds on Projects 1–2:** ArgoCD runs in Project 2's cluster and reads the Helm chart from the same repo. Argo Rollouts modifies the ALB annotation from Project 2 to split traffic between stable and canary target groups. The canary's AnalysisRun queries the `/health` endpoint from Project 2's app — upgraded in Project 5 to use Prometheus error-rate and p99-latency metrics.

**Key design decisions:** Argo Rollouts over plain Kubernetes rolling updates (a standard rolling update gives 100% of users a bad release immediately; the canary limits blast radius to a configurable percentage); App-of-Apps pattern over per-service Application deployment (adding a service is a Git commit, not a cluster operation); `ignoreDifferences` scoped to the one ALB annotation that Argo Rollouts manages dynamically.

---

### Project 4 — Secure CI/CD Pipeline

**Folder:** `project-4-secure-pipeline/`

A five-job GitHub Actions pipeline that builds, tests, scans, and ships Project 2's application through Project 3's GitOps with security woven into every stage. No image that fails a security gate reaches the ECR registry. AWS authentication uses GitHub OIDC with no long-lived access keys stored anywhere. Images are signed with cosign keyless signing via Sigstore's Rekor transparency log. A weekly scheduled workflow rescans the deployed image for CVEs published after the build.

**What it demonstrates:** Supply-chain security at every stage (source → build → image → policy → deploy), keyless image signing with cosign and Sigstore, GitHub OIDC trust federation to AWS IAM (no static credentials), and policy-as-code enforcement with OPA/Conftest at CI time rather than admission-controller time.

**How it builds on Projects 1–3:** Job 3 scans Project 1's Terraform with Checkov and tfsec. Job 4 builds Project 2's Go app, scans it with Trivy, evaluates Project 3's Helm-rendered manifests against Rego policies, pushes the signed image to ECR, then Job 5 updates Project 3's ArgoCD Application manifest and pushes — which triggers Project 3's canary. The pipeline is not a standalone script; it is the deployment pathway for the whole stack.

**Security gates in sequence:**

| Gate | Tool | Blocks at |
|------|------|-----------|
| Secrets in git history | gitleaks | Pre-build |
| Go source SAST | semgrep + govulncheck | Pre-build |
| Terraform misconfigs | Checkov + tfsec | Pre-build |
| Container CVEs (CRIT/HIGH) | Trivy | Post-build, pre-push |
| K8s manifest policy | Conftest + OPA Rego | Post-build, pre-push |
| Image signing | cosign (keyless) | Post-push |

---

### Project 5 — Observability & Security Monitoring

**Folder:** `project-5-observability/`

Prometheus and Grafana on the EKS cluster (via kube-prometheus-stack), meaningful alerting rules tied to real SLO thresholds, AWS-native security services (GuardDuty, Security Hub, Config, CloudTrail), Falco for runtime syscall-level detection inside pods, and one automated remediation: 
A Lambda function that isolates a compromised EC2 instance within seconds of a GuardDuty HIGH severity finding by moving it to a no-rules security group and saving the original groups to an instance tag for restoration. The project also upgrades Project 3's canary AnalysisRun from an HTTP health probe to Prometheus error-rate and p99-latency queries, the gap the postmortem identified.

**What it demonstrates:** Operational maturity (meaningful alerts that fire on conditions requiring action, not on noise), the difference between build-time scanning (Trivy in Project 4) and runtime detection (Falco), AWS-native security posture management, and the discipline of the postmortem. Documenting what happened, what the system caught, what it missed, and what changed as a result.

**How it builds on Projects 1–4:** Prometheus scrapes Project 2's `/metrics` endpoint (added in this project) via a ServiceMonitor. The AnalysisRun upgrade feeds real latency data into Project 3's canary gate. The GuardDuty remediation Lambda uses Project 1's VPC ID to create the isolation security group. The postmortem documents a simulated incident where Project 3's canary auto-aborted a bad deploy. It shows exactly why the HTTP health gate it used was insufficient, making the Prometheus upgrade the direct lesson.

**Key design decisions:** kube-prometheus-stack over a bespoke Prometheus setup (the Operator pattern means new scrape targets and alert rules are added by applying CRD resources, not reloading config); conservative automated remediation (isolate, don't terminate — preserves forensic evidence and is reversible); eBPF driver for Falco (no kernel module needed on managed EKS).

---

### Project 6 — Internal Developer Platform

**Folder:** `project-6-platform/`

A golden-path CLI (`portfolio`) that wraps Projects 1–5 behind a self-service interface. `portfolio status` queries EKS, pods, Argo Rollout state, ArgoCD sync, and GuardDuty findings and renders a single-pane-of-glass health table. `portfolio deploy` builds the image, runs Trivy, pushes to ECR, and updates the GitOps manifest — the same steps the CI pipeline runs, available locally for hotfixes and demos. `portfolio new <service-name>` generates a complete new service directory — Go app with Prometheus metrics, distroless Dockerfile, Helm chart with Argo Rollout canary, ArgoCD Application manifest, and Backstage catalog entry — all pre-wired to the existing stack. A Backstage `catalog-info.yaml` models the full entity graph (System, Components, Resources, APIs, Users) for teams that want a service portal.

**What it demonstrates:** Platform-as-a-product (the platform is not just infrastructure, it is a product with a developer experience), golden-path templating (new services inherit all security defaults from day one), and the ability to operate the entire stack through a single, tested interface.

**How it builds on Projects 1–5:** The CLI reads `.portfolio.yaml` to locate the P1 state bucket, P2 cluster name, P3 GitOps path, and P5 Prometheus address. `portfolio status` calls the EKS API (boto3), kubectl (for pods and rollout state), and GuardDuty (boto3) simultaneously. `portfolio verify` calls `cosign verify` with the exact certificate identity from Project 4's pipeline — any image not built by that workflow fails verification. The generated service template includes the same security context (non-root, `readOnlyRootFilesystem`, capabilities dropped) that the OPA policies in Project 4 enforce.

**Key design decisions:** CLI over a full Backstage deployment (a CLI is demonstrable in under 60 seconds; Backstage requires a running Node.js server, a database, and configured plugins); templates embedded in the Python source (no external template engine needed — the CLI is self-contained); `portfolio new` generates Argo Rollout manifests, not plain Deployments (every new service has progressive delivery from its first deploy).

---

## How the Projects Relate to Each Other

```
                    ┌─────────────────────────────────────────┐
                    │  Project 4: Secure CI/CD Pipeline        │
                    │  Scans P1 IaC · Builds P2 image          │
                    │  Ships via P3 GitOps · Signs with cosign │
                    └──────┬──────────────────────┬────────────┘
                           │  triggers            │ scans
              ┌────────────▼────────┐    ┌────────▼──────────┐
              │ Project 3: GitOps   │    │ Project 1: IaC    │
              │ ArgoCD + Rollouts   │    │ VPC, RDS, ALB,    │
              │ Canary delivery     │    │ EKS node subnets  │
              └────────────┬────────┘    └────────┬──────────┘
                           │ deploys to            │ infrastructure for
              ┌────────────▼────────────────────────▼──────────┐
              │           Project 2: Containers                  │
              │           EKS cluster · Go app · Helm chart     │
              │           IRSA · distroless image · /metrics    │
              └────────────────────────┬───────────────────────┘
                                       │ monitored by
              ┌────────────────────────▼───────────────────────┐
              │  Project 5: Observability & Security Monitoring  │
              │  Prometheus · Grafana · Falco · GuardDuty       │
              │  Upgrades Project 3 canary analysis              │
              └────────────────────────┬───────────────────────┘
                                       │ wrapped by
              ┌────────────────────────▼───────────────────────┐
              │  Project 6: Internal Developer Platform          │
              │  portfolio CLI · Backstage catalog              │
              │  portfolio new → 5 commands → in production     │
              └────────────────────────────────────────────────┘
```

Projects 1 and 2 are the infrastructure and workload layers. Project 3 is the delivery mechanism that runs on top of them. Project 4 is the security and automation layer that automates building and shipping through Project 3, while also validating Project 1. Project 5 wraps the running workload with eyes, and feeds its findings back into Project 3's canary gate. Project 6 is the self-service layer over the whole stack. A developer calls one command, and the entire pipeline runs beneath it.

---

## Common Technology Stack

All six projects share the same core foundation:

| Layer | Technology |
|-------|-----------|
| Cloud provider | Amazon Web Services (AWS) |
| Infrastructure as Code | Terraform >= 1.5 |
| Container orchestration | Amazon EKS (Kubernetes 1.29) |
| Application language | Go 1.21 |
| Application packaging | Helm 3 |
| GitOps engine | ArgoCD + Argo Rollouts |
| CI/CD platform | GitHub Actions |
| Image registry | Amazon ECR |
| Remote state | S3 (versioned, encrypted) + DynamoDB (lock table) |
| Secrets management | No long-lived keys — AWS OIDC, IRSA, SSM Session Manager |

Individual projects layer additional tools on top of this base — see each project's README for the full technology detail.

---

## Detailed Documentation

Each project folder contains a `README.md` with:

- Full architecture diagram (ASCII)
- The *why* behind key design decisions
- Step-by-step deployment guide (prerequisites → deploy → verify → teardown)
- Cost estimate with monthly breakdown and teardown instructions
- Security posture summary
- Notes on promoting the configuration from dev to production

Navigate to the relevant folder to read the detailed documentation for any project.
