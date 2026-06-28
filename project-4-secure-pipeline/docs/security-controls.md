# Security Controls Reference

Each gate in the pipeline addresses a specific threat. This document records what each control does, what attack it mitigates, and what the failure action is. Knowing why a control exists is what separates a DevSecOps engineer from someone who followed a tutorial.

---

## 1. Secrets Scan — gitleaks

**Stage:** Pre-build (job 1, runs first)  
**Tool:** [gitleaks](https://github.com/gitleaks/gitleaks)  
**What it checks:** Every file in every commit in the repository's full git history for patterns that look like credentials (API keys, private keys, tokens, connection strings).  
**Threat mitigated:** Accidental credential commit. A secret committed and immediately reverted is still in git history and still exploitable.  
**Failure action:** Pipeline stops immediately. No build, no push, no deploy.  
**Configuration:** `.gitleaks.toml` — allowlist suppresses false positives (Terraform placeholder strings, example ECR URLs in docs). Every allowlist entry requires a justification comment.

---

## 2. SAST — semgrep + govulncheck

**Stage:** Pre-build (job 2, parallel with secrets scan)  
**Tools:** [semgrep](https://semgrep.dev), [govulncheck](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck)  
**What it checks:**  
- `semgrep`: Static analysis of Go source code for OWASP Top 10 patterns, secrets in code, and Go-specific anti-patterns.  
- `govulncheck`: Scans Go module dependencies against the [Go Vulnerability Database](https://vuln.go.dev). Reports only vulnerabilities reachable in the call graph — no false positives from transitive deps that are never called.  
**Threat mitigated:** Vulnerable dependencies, injection flaws, hardcoded credentials in logic.  
**Failure action:** Pipeline stops. Findings uploaded as SARIF to the GitHub Security tab.

---

## 3. IaC Scan — Checkov + tfsec

**Stage:** Pre-build (job 3, parallel with SAST)  
**Tools:** [Checkov](https://www.checkov.io), [tfsec](https://aquasecurity.github.io/tfsec)  
**What it checks:** All Terraform modules in `project-1-iac/` for AWS misconfigurations — open security groups, unencrypted S3 buckets, missing flow logs, public RDS endpoints, IAM wildcard policies, IMDSv1 access, etc.  
**Threat mitigated:** Infrastructure misconfiguration that creates a security gap (e.g., an accidentally public S3 bucket or an unencrypted RDS instance).  
**Failure action:** Pipeline stops. `soft_fail: false` means any high-severity finding blocks the build. Acceptable exceptions are listed with `skip_check` in the workflow and documented in the `# Skip:` comments there.  
**Why both?** Checkov and tfsec have different rule sets. Running both in parallel catches findings the other misses. SARIF output from each is uploaded separately so findings are attributed to the correct scanner.

---

## 4. Container Image Scan — Trivy

**Stage:** Post-build, pre-push (inside job 4)  
**Tool:** [Trivy](https://aquasecurity.github.io/trivy)  
**What it checks:** The built container image for OS package CVEs, language-level CVEs, and known secrets baked into image layers. Scans against CVE databases including NVD, GitHub Advisory, and OS vendor databases.  
**Threat mitigated:** Shipping a container with a known exploitable vulnerability to production.  
**Failure action:** Build fails before the image is pushed to ECR. An image that fails Trivy never reaches the registry.  
**`ignore-unfixed: true`:** CVEs with no upstream fix available are excluded from the exit-code check (they still appear in SARIF). Blocking on unfixed CVEs only creates pressure to suppress the check — better to surface them as informational and act when a fix is available.  
**`.trivyignore`:** CVEs that are genuinely not applicable (e.g., a bash CVE in a distroless image with no shell) can be suppressed with a documented justification and an expiry date.

---

## 5. Policy-as-Code — OPA/Conftest

**Stage:** Post-build, pre-push (inside job 4)  
**Tool:** [Conftest](https://www.conftest.dev) + [OPA Rego policies](policy/conftest/)  
**What it checks:** Kubernetes manifests rendered from the Helm chart. Policies are evaluated before deployment, not after.

| Policy file | What it enforces |
|---|---|
| `deny_latest_tag.rego` | Images must use `sha-<git-sha>` tags — `:latest` is non-deterministic |
| `require_resource_limits.rego` | All containers must set CPU and memory requests and limits |
| `deny_privileged.rego` | No privileged containers, no `hostPID`, no `hostNetwork` |
| `deny_root.rego` | `runAsNonRoot: true` required; `runAsUser: 0` denied; capability drops verified |

**Threat mitigated:** Misconfigured Kubernetes manifests that create runtime security gaps — caught at CI time rather than during a production incident.  
**Failure action:** Build fails before push. Manifests that violate any `deny` rule are rejected.  
**Adding policies:** Drop a new `.rego` file into `policy/conftest/` — Conftest picks it up automatically. No workflow change needed.

---

## 6. Image Signing — cosign (keyless)

**Stage:** Post-push (inside job 4)  
**Tool:** [cosign](https://github.com/sigstore/cosign) via [Sigstore](https://www.sigstore.dev)  
**What it does:** Signs the image digest with a certificate issued by Fulcio CA, anchored to the GitHub Actions OIDC token. The signature and certificate are recorded in Rekor (a public, append-only transparency log).  
**Threat mitigated:** Image substitution attacks — someone replacing a legitimate image in the registry with a malicious one. Signed images can be verified cryptographically before deployment.  
**Why keyless?** Traditional cosign signing requires managing a private key (rotation, storage, access control). Keyless signing uses the pipeline's ephemeral OIDC identity as proof — no private key to lose, rotate, or leak.

**Verify a signature:**
```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/GITHUB_USERNAME/devops-portfolio/.github/workflows/pipeline.yaml.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/devops-portfolio/dev/app:sha-abc1234
```

---

## 7. Weekly Rescan — scheduled Trivy

**Schedule:** Every Monday at 03:00 UTC  
**What it does:** Re-scans the latest deployed image against an up-to-date vulnerability database. CVEs are published continuously — an image that was clean at build time may have critical findings a week later.  
**Action:** Uploads SARIF to GitHub Security tab. Does not fail CD (the image is already deployed). Triggers a GitHub workflow failure notification if CRITICAL findings are found, prompting the team to rebuild and redeploy.

---

## AWS authentication — GitHub OIDC

No long-lived AWS access keys are stored anywhere. GitHub Actions authenticates to AWS by presenting a short-lived OIDC token (valid for the duration of one workflow run). The `infra/github-oidc/` Terraform creates the OIDC trust relationship and an IAM role scoped to:
- ECR push to `devops-portfolio/*` repositories only
- `eks:DescribeCluster` on any cluster (read-only)

The trust policy's `StringLike` condition restricts assumption to workflows running from this specific GitHub repository — any other repo's workflows cannot assume the role even if they know the ARN.
