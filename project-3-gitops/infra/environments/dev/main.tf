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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
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
      Repository  = "devops-portfolio/project-3-gitops"
    }
  }
}

# ─── Read Project 2 state to get the EKS cluster that already exists ──────────

data "terraform_remote_state" "project2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "project-2/dev/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  cluster_name   = data.terraform_remote_state.project2.outputs.cluster_name
  cluster_host   = data.terraform_remote_state.project2.outputs.cluster_endpoint
  cluster_ca     = data.terraform_remote_state.project2.outputs.cluster_certificate_authority_data
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_host
    cluster_ca_certificate = base64decode(local.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubernetes" {
  host                   = local.cluster_host
  cluster_ca_certificate = base64decode(local.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
  }
}

# ─── ArgoCD ───────────────────────────────────────────────────────────────────
#
# ArgoCD is the GitOps engine: it watches a Git repo and continuously reconciles
# cluster state to match what is declared there. Any drift (manual kubectl apply,
# a failed deploy) is detected and corrected automatically.
#
# server.insecure=true: ArgoCD terminates TLS internally; we rely on the ALB or
# port-forward for HTTPS in this dev setup. Set false and add a TLS cert in prod.

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = var.argocd_version
  create_namespace = true

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
        cm = {
          "timeout.reconciliation" = "30s"
          "resource.customizations.health.argoproj.io_Rollout" = <<-EOT
            hs = {}
            if obj.status ~= nil then
              if obj.status.phase == "Degraded" then
                hs.status = "Degraded"
                hs.message = obj.status.message
              elseif obj.status.phase == "Progressing" then
                hs.status = "Progressing"
                hs.message = obj.status.message
              else
                hs.status = "Healthy"
              end
            else
              hs.status = "Progressing"
            end
            return hs
          EOT
        }
      }
      server = {
        service = {
          type = "ClusterIP"
        }
      }
      # Single replicas for dev — scale up for prod HA
      controller = { replicas = 1 }
      repoServer = { replicas = 1 }
      applicationSet = { replicas = 1 }
      redis-ha = { enabled = false }
    })
  ]
}

# ─── Argo Rollouts ────────────────────────────────────────────────────────────
#
# Argo Rollouts extends Kubernetes with a Rollout CRD that replaces Deployment
# for canary and blue/green strategies. It integrates directly with ArgoCD so
# that GitOps syncs trigger progressive delivery instead of a raw pod swap.

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  namespace        = "argo-rollouts"
  version          = var.argo_rollouts_version
  create_namespace = true

  values = [
    yamlencode({
      controller = { replicas = 1 }
      dashboard  = { enabled = true }
    })
  ]

  depends_on = [helm_release.argocd]
}

# ─── ArgoCD AppProject ────────────────────────────────────────────────────────
#
# AppProject scopes ArgoCD RBAC: it restricts which repos, clusters, and
# namespaces the portfolio applications may touch. Without a project, everything
# falls into 'default' which is unrestricted — fine for a solo setup, not for
# a shared cluster.

resource "kubernetes_manifest" "argocd_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "portfolio"
      namespace = "argocd"
    }
    spec = {
      description = "DevOps portfolio projects"
      sourceRepos = ["*"]
      destinations = [{
        namespace = "*"
        server    = "https://kubernetes.default.svc"
      }]
      clusterResourceWhitelist = [{ group = "*", kind = "*" }]
      namespaceResourceWhitelist = [{ group = "*", kind = "*" }]
    }
  }

  depends_on = [helm_release.argocd]
}
