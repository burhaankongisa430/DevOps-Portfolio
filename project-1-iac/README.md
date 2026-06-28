# Project 1 — Infrastructure as Code

A production-shaped, modular Terraform codebase that builds a complete AWS environment from scratch and tears it down cleanly, demonstrating AWS depth (VPC internals, IAM least-privilege, RDS hardening) alongside IaC discipline (remote state, module composition, sensible defaults for dev vs prod). Every subsequent project runs on this infrastructure.

---

## Architecture

```
Internet
    │  (HTTP :80 / HTTPS :443)
    ▼
┌────────────────────────────────────────────────────────────────┐
│                      VPC  10.0.0.0/16                          │
│                                                                  │
│  PUBLIC SUBNETS  (10.0.1–3.0/24) — one per AZ                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          Application Load Balancer  (ALB)                │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                          │  (port 8080, ALB SG → App SG only)  │
│  PRIVATE SUBNETS  (10.0.11–13.0/24)                            │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐               │
│  │  EC2 AZ-a  │  │  EC2 AZ-b  │  │  EC2 AZ-c  │  ← ASG       │
│  └────────────┘  └────────────┘  └────────────┘               │
│       │  (port 5432, App SG → RDS SG only)                     │
│  DB SUBNETS  (10.0.21–23.0/24)                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │             RDS PostgreSQL 15  (Multi-AZ opt-in)         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Internet Gateway ──► NAT Gateway (shared, dev)                │
│  VPC Flow Logs ──► CloudWatch Logs                             │
└────────────────────────────────────────────────────────────────┘

Remote State
  S3 (versioned, AES-256, public access blocked)
  DynamoDB (PAY_PER_REQUEST lock table)
```

---

## Why these choices

### Three-tier subnets over a flat VPC
The ALB, app instances, and database each live in their own subnet tier with security groups enforcing layer-to-layer rules. This means a compromised EC2 instance cannot reach the database directly — it must go through a security group that only permits the app port from the app SG. 

### Single NAT gateway in dev, variable in prod
A NAT gateway costs ~$32/month. For dev, one shared across three AZs is fine. In production you'd set `single_nat_gateway = false` to get per-AZ NAT gateways so an AZ failure doesn't take down all outbound traffic from private subnets. The variable is wired up — it's a one-line change to go from dev to prod topology.

### SSM Session Manager instead of SSH
There is no port 22 open anywhere in this stack. EC2 instances are accessed via `aws ssm start-session`, authenticated through IAM. This removes the key management burden (no key pairs to rotate or lose) and means every session is logged to CloudWatch automatically. This is the correct pattern for ephemeral autoscaled instances.

### IMDSv2 required on all instances
The EC2 metadata endpoint is the most common lateral-movement target in AWS compromises (SSRF → metadata → credentials). Requiring IMDSv2 (token-gated, single-hop) closes that attack path. It's a single `metadata_options` block in the launch template — there's no reason not to enforce it.

### RDS force_ssl and no public access
The parameter group sets `rds.force_ssl = 1` so every connection is encrypted in transit, and `publicly_accessible = false` so the instance has no public IP.

### Remote state from day one
State is kept in S3 (versioned, encrypted, public-access blocked) with a DynamoDB lock table. This is to concurrent-apply risks and treat state as a production artefact, not a local file.

---

## Repository structure

```
project-1-iac/
├── bootstrap/              # One-time setup: S3 state bucket + DynamoDB lock table
├── modules/
│   ├── vpc/                # VPC, all subnet tiers, NAT, IGW, flow logs
│   ├── security-groups/    # ALB / App / RDS security groups
│   ├── alb/                # Application Load Balancer + target group
│   ├── autoscaling/        # Launch template + ASG + CPU target-tracking policy
│   ├── rds/                # PostgreSQL RDS, subnet group, parameter group
│   └── iam/                # EC2 instance role (SSM + CloudWatch, least-privilege)
├── environments/
│   └── dev/                # Dev environment wires all modules together
│       ├── main.tf
│       ├── backend.tf      # S3 remote state (fill in after bootstrap)
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
└── scripts/
    ├── apply-dev.sh        # Bootstrap + apply in one command
    └── teardown.sh         # Destroy dev to stop charges
```

---

## Prerequisites

| Requirement | Version |
|---|---|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x, configured with `aws configure` |
| AWS permissions | AdministratorAccess (or a scoped policy covering EC2, VPC, RDS, IAM, S3, DynamoDB, Budgets) |

---

## Deploying

### Option A — automated script

```bash
export TF_VAR_db_password="choose-a-strong-password"
bash scripts/apply-dev.sh
```

### Option B — step by step

**1. Bootstrap remote state (one-time)**

```bash
cd bootstrap
terraform init
terraform apply
# Copy the `backend_config_snippet` output
```

**2. Configure the dev backend**

Paste the snippet output from step 1 into `environments/dev/backend.tf`, replacing the placeholder values.

**3. Deploy the dev environment**

```bash
export TF_VAR_db_password="choose-a-strong-password"

cd environments/dev
terraform init   # migrates state to S3
terraform plan
terraform apply
```

**4. Verify**

```bash
terraform output app_url          # curl this — expect HTTP 200 /health
terraform output -json vpc_id
```

### Teardown (stop charges)

```bash
export TF_VAR_db_password="same-password-as-above"
bash scripts/teardown.sh
```

---

## Cost estimate (dev environment, us-east-1)

| Resource | Approx monthly cost |
|---|---|
| NAT Gateway (1x) | $32 |
| ALB | $16 |
| 2× t3.micro EC2 | $15 |
| db.t3.micro RDS (20 GiB gp3) | $15 |
| VPC Flow Logs (low traffic) | $1 |
| **Total** | **~$79/month** |

> The budget alarm in `main.tf` fires at 80% of $50 — adjust `limit_amount` to match your actual spend tolerance.
> Run `bash scripts/teardown.sh` when you are done demoing to drop this to ~$0.

---

## Promoting to production

| Parameter | Dev | Prod |
|---|---|---|
| `single_nat_gateway` | `true` | `false` |
| `multi_az` (RDS) | `false` | `true` |
| `deletion_protection` (RDS) | `false` | `true` |
| `skip_final_snapshot` | `true` | `false` |
| `enable_deletion_protection` (ALB) | `false` | `true` |
| `desired_capacity` | `2` | `≥3` |

Add a `environments/prod/` directory mirroring `environments/dev/` with these values changed. The modules require no modification.

---

## Security posture

- No EC2 instance has a public IP or an open port 22
- All inter-tier traffic is restricted by security group reference (not CIDR)
- IMDSv2 required on all instances (blocks SSRF metadata exfil)
- RDS: SSL enforced, no public endpoint, storage encrypted at rest
- IAM: EC2 role is SSM + CloudWatch only — no `*` actions, no `*` resources
- VPC Flow Logs capture all accepted and rejected traffic for incident investigation
- Terraform state is encrypted and versioned; lock prevents concurrent applies
