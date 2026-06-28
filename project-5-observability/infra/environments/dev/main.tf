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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
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
      Repository  = "devops-portfolio/project-5-observability"
    }
  }
}

# ─── Read upstream project state ─────────────────────────────────────────────

data "terraform_remote_state" "project1" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "dev/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "project2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "project-2/dev/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.project1.outputs.vpc_id
  cluster_name       = data.terraform_remote_state.project2.outputs.cluster_name
  cluster_host       = data.terraform_remote_state.project2.outputs.cluster_endpoint
  cluster_ca         = data.terraform_remote_state.project2.outputs.cluster_certificate_authority_data
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

# ─── AWS security services ────────────────────────────────────────────────────

module "aws_security" {
  source = "../../modules/aws-security"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  alert_email = var.alert_email
}

# ─── Automated remediation ────────────────────────────────────────────────────

module "auto_remediation" {
  source = "../../modules/auto-remediation"

  project       = var.project
  environment   = var.environment
  vpc_id        = local.vpc_id
  sns_topic_arn = module.aws_security.security_alerts_topic_arn
}

# ─── kube-prometheus-stack ────────────────────────────────────────────────────
#
# Installs Prometheus Operator, Prometheus, Grafana, Alertmanager,
# kube-state-metrics, and node-exporter in one chart. The Prometheus Operator
# watches ServiceMonitor and PrometheusRule CRDs — add new scrape targets and
# alert rules by applying those resources, no config reload required.

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  version          = var.prometheus_version
  create_namespace = true
  timeout          = 600

  values = [file("${path.module}/../../../helm/kube-prometheus-stack/values.yaml")]
}

# ─── Falco (runtime security) ─────────────────────────────────────────────────
#
# Falco monitors system calls at the kernel level to detect anomalous behaviour
# at runtime — container escapes, privilege escalations, unexpected outbound
# connections. It complements static analysis (Trivy/OPA) by catching attacks
# that evade static checks.

resource "helm_release" "falco" {
  name             = "falco"
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  namespace        = "falco"
  version          = var.falco_version
  create_namespace = true
  timeout          = 300

  values = [file("${path.module}/../../../helm/falco/values.yaml")]

  depends_on = [helm_release.kube_prometheus_stack]
}
