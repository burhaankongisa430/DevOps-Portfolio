# Project 2 — Containers & Orchestration

> **Portfolio context:**

A production-shaped container setup: a Go HTTP service compiled into a distroless image, an EKS managed cluster built on Project 1's VPC, and a Helm chart that handles rolling deploys, autoscaling, and least-privilege pod IAM.

---

## Architecture

```
Internet
    │  (HTTP :80)
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AWS VPC (from Project 1)                      │
│                                                                   │
│  PUBLIC SUBNETS                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │    AWS ALB  (provisioned by AWS Load Balancer Controller) │  │
│  └────────────────────────┬──────────────────────────────────┘  │
│                            │                                      │
│  PRIVATE SUBNETS (EKS node group)                                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  EKS Managed Nodes  (t3.medium × 2–3, Amazon Linux 2)     │  │
│  │                                                              │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │  │
│  │  │  app pod AZ-a│  │  app pod AZ-b│  │  app pod ...  │    │  │
│  │  │  Go HTTP svc │  │  Go HTTP svc │  │   (HPA)       │    │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │  │
│  └────────────────────────────────────────────────────────────┘  │
│                            │  (TCP :5432)                         │
│  DB SUBNETS (from Project 1)                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │               RDS PostgreSQL (Project 1)                  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

ECR  ──► Docker image store (scan on push, lifecycle policy)
OIDC ──► IRSA (pod-level IAM, not node-level)
```

---

## Why these choices

### Distroless final image
The production image contains only the compiled Go binary and CA certificates — no shell, no package manager, no libc. An attacker who achieves RCE has nothing to exec and no tools to install more. 

Multi-stage build keeps this clean: the `golang:alpine` builder stage has all the tooling needed to compile; the final `gcr.io/distroless/static:nonroot` stage gets only the binary. Image size drops from ~300 MB to ~10 MB.

### IRSA over node-level IAM
Pods use IAM Roles for Service Accounts (IRSA) via the cluster's OIDC provider. This means each deployment can have a scoped role — the app pod only gets what it needs, and a compromised pod cannot call any AWS API that its service account isn't explicitly permitted. Node-level roles (the earlier, simpler pattern) let any pod on a node assume the node's role, which is the most common lateral-movement path in EKS compromises.

### Managed node group over self-managed
AWS handles OS patching, AMI rotation, and node replacement for managed groups. Self-managed groups give more control (custom AMIs, Bottlerocket) but requires managing. Manages node groups allow for operating at a reasonable abstraction level, thus reducing operations overhead.

### Helm for application packaging
Helm separates the infrastructure question ("is this an EKS cluster?") from the deployment question ("which version of which image is running with what config?"). Using a Helm chart with `values.yaml` + environment-specific overrides (`values-dev.yaml`) allows for this configuration pattern to  scales to prod without rewriting the chart.

The `--atomic` flag on `helm upgrade` rolls back automatically if any pod fails to become Ready within the timeout. This is the GitOps-adjacent safety property that Project 3 (ArgoCD) formalises.

### topologySpreadConstraints instead of podAntiAffinity
Both spread pods across AZs, but `topologySpreadConstraints` is more expressive and is the current Kubernetes standard. It sets `whenUnsatisfiable: DoNotSchedule`, meaning the scheduler refuses to place a pod in a way that would create an imbalanced topology — a stronger guarantee than soft anti-affinity.

### Pod security defaults
Every pod runs as non-root (uid 65532, matching the distroless image), with `readOnlyRootFilesystem`, all capabilities dropped, and a `RuntimeDefault` seccomp profile. These are the Kubernetes Pod Security Standards "restricted" profile defaults — they're not novel, but absent them a reviewer will notice.

---

## Repository structure

```
project-2-containers/
├── app/
│   ├── main.go          # Go HTTP service (stdlib only, zero external deps)
│   ├── go.mod
│   └── Dockerfile       # Multi-stage: golang:alpine builder → distroless final
├── docker-compose.yml   # Local dev with hot postgres
├── infra/
│   ├── modules/
│   │   ├── ecr/         # ECR repo + lifecycle policy
│   │   └── eks/         # Cluster, node group, OIDC, IRSA roles, subnet tags
│   └── environments/
│       └── dev/         # Reads P1 state, calls modules, installs LBC + metrics-server
├── helm/
│   └── app/
│       ├── Chart.yaml
│       ├── values.yaml        # Defaults
│       ├── values-dev.yaml    # Dev overrides (ALB ingress enabled)
│       └── templates/
│           ├── deployment.yaml     # Rolling update, topology spread, security context
│           ├── service.yaml        # ClusterIP
│           ├── ingress.yaml        # AWS ALB annotations
│           ├── hpa.yaml            # autoscaling/v2 HPA
│           ├── serviceaccount.yaml # IRSA annotation support
│           └── configmap.yaml
└── scripts/
    ├── build-push.sh    # Build + ECR push
    ├── deploy.sh        # Helm upgrade --install
    └── teardown.sh      # Helm uninstall + terraform destroy
```

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x |
| kubectl | >= 1.29 |
| Helm | >= 3.14 |
| Docker | >= 24.x |
| Project 1 | Applied (VPC + RDS must exist) |

---

## Deploying

### 1. Apply infrastructure

```bash
# Fill in the P1 state bucket name in terraform.tfvars first
cd infra/environments/dev
terraform init
terraform plan
terraform apply
```

This creates the EKS cluster, ECR repository, installs the AWS Load Balancer Controller and metrics-server. Takes ~15 minutes (EKS cluster creation is slow).

### 2. Build and push the image

```bash
bash scripts/build-push.sh
# Outputs: sha-<git-sha> tag pushed to ECR
```

### 3. Deploy to EKS

```bash
bash scripts/deploy.sh sha-<git-sha>
```

The script runs `helm upgrade --install --atomic`. If any pod fails to become Ready in 5 minutes, Helm automatically rolls back.

### 4. Verify

```bash
# Wait ~90s for the ALB to provision
kubectl get ingress app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Then:
curl http://<ALB_DNS>/health
curl http://<ALB_DNS>/
```

Expected responses:

```json
// /health
{"status":"ok","version":"sha-abc1234"}

// /
{"name":"devops-portfolio-app","version":"sha-abc1234","buildTime":"2026-06-27T...","hostname":"app-xyz"}
```

### Local development

```bash
docker compose up --build
curl http://localhost:8080/health
curl http://localhost:8080/
```

### Teardown

```bash
bash scripts/teardown.sh
```

---

## Cost estimate (Project 2 additions, us-east-1)

| Resource | Approx monthly cost |
|---|---|
| EKS cluster control plane | $73 |
| 2× t3.medium nodes | $60 |
| ECR storage (10 images) | $1 |
| **Project 2 subtotal** | **~$134/month** |
| Project 1 (from P1 README) | ~$79/month |
| **Combined total** | **~$213/month** |

> Run `bash scripts/teardown.sh` then Project 1's `teardown.sh` when done demoing to stop all charges.

---

## Security posture

- Container image: distroless, non-root, no shell
- All pods: `readOnlyRootFilesystem`, all capabilities dropped, `RuntimeDefault` seccomp
- IAM: IRSA for pod-level permissions — no wildcard node role
- ECR: scan on push enabled; lifecycle policy prevents unbounded image accumulation
- EKS: private endpoint enabled; control-plane logs to CloudWatch (audit trail)
- No port 22: nodes accessible only via SSM Session Manager (inherited from P1 IAM module)
