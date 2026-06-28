terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# ─── GitHub OIDC provider ─────────────────────────────────────────────────────
#
# This is the bridge between GitHub Actions and AWS IAM. GitHub Issues short-lived
# OIDC tokens to each workflow run. AWS validates the token against this provider
# and, if the claim conditions match, issues temporary credentials — zero long-lived
# access keys ever committed to the repo or stored in GitHub Secrets.

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # Stable thumbprint for GitHub's OIDC endpoint.
  # AWS validates this against the provider's TLS certificate chain.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ─── IAM role for GitHub Actions ─────────────────────────────────────────────

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Only allow assumption when the token's audience is AWS STS
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Restrict to YOUR repo — any other GitHub repo's workflows cannot
          # assume this role, even if they reference the same ARN.
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })
}

# ─── IAM policy: minimal permissions for the pipeline ─────────────────────────

data "aws_iam_policy_document" "github_actions" {
  # ECR login token — must target * (it's a global operation)
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  # ECR push to portfolio repositories only — not the whole registry
  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_prefix}/*",
    ]
  }

  # EKS describe — needed to generate kubeconfig for the deploy step
  statement {
    sid    = "EKSRead"
    effect = "Allow"
    actions = [
      "eks:DescribeCluster",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_actions" {
  name        = "${var.project}-github-actions-policy"
  description = "Minimal permissions for the portfolio CI/CD pipeline"
  policy      = data.aws_iam_policy_document.github_actions.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}
