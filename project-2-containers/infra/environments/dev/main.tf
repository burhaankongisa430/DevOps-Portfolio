terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "devops-portfolio/project-2-containers"
    }
  }
}

# Helm provider authenticates to the EKS cluster using the AWS CLI exec plugin.
# This avoids storing cluster credentials in Terraform state.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", module.eks.cluster_name,
        "--region", var.aws_region,
      ]
    }
  }
}

# ─── Read Project 1 infrastructure ───────────────────────────────────────────
#
# Rather than re-creating the VPC, we read P1's remote state to consume its
# outputs. This keeps the two projects genuinely connected and shows reviewers
# that you understand multi-stack Terraform patterns.

data "terraform_remote_state" "project1" {
  backend = "s3"
  config = {
    bucket = var.p1_state_bucket
    key    = var.p1_state_key
    region = var.aws_region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.project1.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.project1.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.project1.outputs.public_subnet_ids
}

# ─── ECR repository ──────────────────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"

  project         = var.project
  environment     = var.environment
  repository_name = "app"
  scan_on_push    = true
}

# ─── EKS cluster ─────────────────────────────────────────────────────────────

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  vpc_id             = local.vpc_id
  private_subnet_ids = local.private_subnet_ids
  public_subnet_ids  = local.public_subnet_ids

  kubernetes_version = "1.29"
  node_instance_type = "t3.medium"
  node_min_size      = 1
  node_max_size      = 3
  node_desired_size  = 2
}

# ─── AWS Load Balancer Controller (Helm) ─────────────────────────────────────
#
# Manages ALBs in response to Kubernetes Ingress objects. Installed into the
# cluster via Terraform's Helm provider so the LBC lifecycle is tracked in state.

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.aws_lbc_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = local.vpc_id
  }

  depends_on = [module.eks]
}

# ─── metrics-server (Helm) ────────────────────────────────────────────────────
# Required for kubectl top and HorizontalPodAutoscaler to function.

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.0"

  depends_on = [module.eks]
}
