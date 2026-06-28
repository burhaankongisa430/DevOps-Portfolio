# Project 4 — Secure CI/CD Pipeline

> **Portfolio context:** The flagship project. Every other project feeds into this pipeline — Project 1's Terraform is scanned here, Project 2's container is built and signed here, Project 3's GitOps trigger fires from here.

Security at every stage of the software supply chain: secrets scanning, SAST, dependency scanning, IaC scanning, container CVE scanning, policy-as-code gates, keyless image signing, and a weekly rescan for new CVEs in already-deployed images.

---

## Pipeline architecture

```
git push ──► GitHub Actions
               │
               ├──[parallel]────────────────────────────────────────────┐
               │                                                          │
               ▼                                                          ▼
        ┌────────────┐                                         ┌─────────────────┐
        │ Job 1      │                                         │ Job 3           │
        │ gitleaks   │                                         │ Checkov + tfsec │
        │ (secrets)  │                                         │ (IaC scan P1)   │
        └─────┬──────┘                                         └────────┬────────┘
              │                                                          │
              ├──[parallel]──────────────┐                              │
              │                          │                              │
              ▼                          ▼                              │
       ┌───────────┐              ┌────────────┐                        │
       │ Job 2     │              │            │                        │
       │ semgrep   │              │  (same     │                        │
       │ govulnchk │              │   job 2)   │                        │
       └─────┬─────┘              └────────────┘                        │
             │                                                           │
             └──────────────────────────────────────────────────────────┤
                                                                         │
                                    ┌────────────────────────────────────┘
                                    │
                                    ▼
                          ┌──────────────────────┐
                          │ Job 4                 │
                          │ 1. docker build       │
                          │ 2. Trivy image scan ──┼──► fail = stop here
                          │ 3. Conftest (OPA) ────┼──► fail = stop here
                          │ 4. docker push ────── │
                          │ 5. cosign sign ─────► │ Sigstore Rekor log
                          └──────────┬────────────┘
                                     │  (main branch only)
                                     ▼
                          ┌──────────────────────┐
                          │ Job 5                 │
                          │ yq update image.tag   │
                          │ git push ─────────── │
                          └──────────────────────┘
                                     │
                                     │  30s later (ArgoCD detects)
                                     ▼
                             Argo Rollouts canary
                             (Project 3 takes over)
```

---

## Security controls at a glance

| Stage | Tool | Gate | Failure action |
|---|---|---|---|
| Pre-build | gitleaks | Secret patterns in git history | Pipeline stops |
| Pre-build | semgrep | OWASP Top 10, Go anti-patterns | Pipeline stops |
| Pre-build | govulncheck | Go dependency CVEs | Pipeline stops |
| Pre-build | Checkov | Terraform misconfigurations | Pipeline stops |
| Pre-build | tfsec | Terraform security rules | Pipeline stops |
| Post-build | Trivy | Container image CVEs (CRIT/HIGH) | Stop before push |
| Post-build | Conftest + OPA | K8s manifest policy gates | Stop before push |
| Post-push | cosign | Keyless image signing | Attestation in Rekor |
| Weekly | Trivy (scheduled) | New CVEs on deployed image | GitHub Security alert |

All findings upload to the GitHub Security tab as SARIF. Nothing that fails a security gate reaches the ECR registry.

---

## Why these choices

### Scan before push, not after
The most important architectural decision in the pipeline. Once an image is in the registry, it might get deployed before a scan result comes back. Scanning the local image before `docker push` means a failing image never reaches the registry. There is no window where bad code is in ECR but not yet caught.

### Keyless cosign over key-based signing
Traditional image signing requires managing a private key: generating it, storing it securely, rotating it, and making sure CI has read access. Keyless signing via Sigstore uses GitHub's OIDC token as the proof of identity. The signing certificate is issued for the duration of one workflow run and then expires, there is no private key to lose or rotate. The signature is recorded in Rekor's public append-only log, which means anyone can verify it independently and any attempt to tamper with the log is detectable.

### Policy-as-code (OPA/Conftest) over admission controllers
Admission controllers (OPA Gatekeeper, Kyverno) enforce policy at deploy time in the cluster. Conftest enforces the same policies at CI time, before the manifests ever touch the cluster. This gives faster feedback (CI fails in seconds, not when `kubectl apply` is run) and means the policies are version-controlled alongside the code they govern. In Project 5, admission controller policies are added as a second enforcement layer.

### Separate SARIF uploads per scanner
Each tool uploads its own SARIF file with a distinct `category`. This keeps findings attributed to the correct scanner in the GitHub Security tab. You can filter to just Trivy findings, or just Checkov findings, without them being mixed together.

### GitHub OIDC over static AWS credentials
No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in GitHub Secrets. The workflow assumes an IAM role via OIDC for the duration of a single run, then the credentials expire. The trust policy restricts assumption to this specific repo's workflows — lateral movement from another repo is prevented at the IAM level.

### Weekly rescan
CVEs are published on a rolling basis. The Trivy database used during the build may be days old by the time a new CVE is published for a package in the running image. The scheduled scan catches this without requiring a new build, it surfaces the finding in GitHub Security and notifies the team via workflow failure email.

---

## Repository structure

```
project-4-secure-pipeline/
├── .github/
│   └── workflows/
│       ├── pipeline.yaml           # Main: 5-job secure pipeline
│       └── scheduled-scan.yaml     # Weekly Trivy rescan of deployed image
├── policy/
│   └── conftest/                   # OPA Rego policies (evaluated by Conftest)
│       ├── deny_latest_tag.rego
│       ├── require_resource_limits.rego
│       ├── deny_privileged.rego
│       └── deny_root.rego
├── infra/
│   └── github-oidc/                # Terraform: GitHub OIDC provider + IAM role
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── docs/
│   └── security-controls.md        # Per-control documentation (the WHY)
├── .gitleaks.toml                  # gitleaks allowlist for false positives
└── .trivyignore                    # Trivy CVE exceptions (justified + expiry dated)
```

---

## Setup

### 1. Create the GitHub OIDC IAM role

```bash
cd infra/github-oidc
terraform init
terraform apply \
  -var="github_org=YOUR_GITHUB_USERNAME" \
  -var="github_repo=devops-portfolio"

# Copy the role ARN from the output
terraform output github_actions_role_arn
```

### 2. Add the role ARN as a GitHub Secret

In your GitHub repo: **Settings → Secrets and variables → Actions → New repository secret**

```
Name:  AWS_ROLE_ARN
Value: arn:aws:iam::ACCOUNT_ID:role/devops-portfolio-github-actions
```

### 3. Enable GitHub Actions OIDC (repo level)

In your repo settings: **Settings → Actions → General → Workflow permissions**
- Select "Read and write permissions"
- Check "Allow GitHub Actions to create and approve pull requests"

### 4. Push and watch it run

```bash
git add .
git commit -m "feat: add project 4 secure pipeline"
git push
```

The pipeline fires automatically. Watch it in **Actions** tab.

---

## Adding a new OPA policy

Drop a `.rego` file into `policy/conftest/`. Use `package main` and write `deny[msg]` or `warn[msg]` rules. Conftest picks it up on the next pipeline run — no workflow change needed.

To test a policy locally:

```bash
# Install conftest
brew install conftest   # or download from GitHub releases

# Render manifests
helm template portfolio-app project-3-gitops/helm/app \
  -f project-3-gitops/helm/app/values.yaml \
  > /tmp/manifests.yaml

# Evaluate all policies
conftest test /tmp/manifests.yaml \
  --policy project-4-secure-pipeline/policy/conftest \
  --namespace main \
  --output table
```

---

## Verifying a signed image

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/YOUR_USERNAME/devops-portfolio/.github/workflows/pipeline.yaml.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/devops-portfolio/dev/app:sha-abc1234
```

A successful verification means this image was built by this pipeline from this repository — any tampered or externally-built image will fail verification.

---

## Cost

Project 4 is GitHub Actions minutes + Sigstore's free public infrastructure. No additional AWS resources beyond Projects 1–3. GitHub provides 2,000 free minutes/month for public repos and 2,000 for private with a free plan. Each full pipeline run takes approximately 4–6 minutes.
