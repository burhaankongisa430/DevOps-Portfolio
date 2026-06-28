"""Config loader — reads .portfolio.yaml from the repo root or a specified path."""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import boto3
import yaml


@dataclass
class Config:
    # Top-level
    project: str = "devops-portfolio"
    environment: str = "dev"

    # AWS
    aws_region: str = "us-east-1"
    aws_account_id: str = ""

    # ECR
    ecr_registry: str = ""
    ecr_image_name: str = "devops-portfolio/dev/app"

    # EKS
    eks_cluster_name: str = ""
    eks_namespace: str = "default"

    # Terraform
    tf_state_bucket: str = ""
    tf_p1_state_key: str = "dev/terraform.tfstate"
    tf_p2_state_key: str = "project-2/dev/terraform.tfstate"

    # GitHub
    github_repo: str = ""
    github_branch: str = "main"
    gitops_app_path: str = "project-3-gitops/argocd/apps/portfolio-app.yaml"

    # ArgoCD
    argocd_namespace: str = "argocd"
    argocd_app_name: str = "portfolio-app"

    # Prometheus
    prometheus_address: str = ""

    @property
    def image_base(self) -> str:
        return f"{self.ecr_registry}/{self.ecr_image_name}"

    def resolve(self) -> "Config":
        """Fill in auto-derived fields (account ID, ECR registry, cluster name)."""
        if not self.aws_account_id:
            try:
                sts = boto3.client("sts", region_name=self.aws_region)
                self.aws_account_id = sts.get_caller_identity()["Account"]
            except Exception:
                pass

        if not self.ecr_registry and self.aws_account_id:
            self.ecr_registry = f"{self.aws_account_id}.dkr.ecr.{self.aws_region}.amazonaws.com"

        if not self.eks_cluster_name:
            self.eks_cluster_name = f"{self.project}-{self.environment}-eks"

        return self


def load(config_path: Optional[Path] = None) -> Config:
    """
    Load config from .portfolio.yaml. Searches: explicit path → CWD → repo root.
    Returns a Config with sensible defaults if no file is found.
    """
    paths_to_try: list[Path] = []

    if config_path:
        paths_to_try.append(config_path)

    # Walk up from CWD to find the repo root (.portfolio.yaml)
    cwd = Path.cwd()
    for parent in [cwd, *cwd.parents]:
        candidate = parent / ".portfolio.yaml"
        paths_to_try.append(candidate)
        if (parent / ".git").exists():
            break

    cfg = Config()

    for path in paths_to_try:
        if path.exists():
            with open(path) as f:
                raw = yaml.safe_load(f) or {}

            p = raw.get("platform", {})
            cfg.project     = p.get("project", cfg.project)
            cfg.environment = p.get("environment", cfg.environment)

            a = raw.get("aws", {})
            cfg.aws_region     = a.get("region", cfg.aws_region)
            cfg.aws_account_id = a.get("account_id", cfg.aws_account_id)

            e = raw.get("ecr", {})
            cfg.ecr_registry   = e.get("registry", cfg.ecr_registry)
            cfg.ecr_image_name = e.get("image_name", cfg.ecr_image_name)

            k = raw.get("eks", {})
            cfg.eks_cluster_name = k.get("cluster_name", cfg.eks_cluster_name)
            cfg.eks_namespace    = k.get("namespace", cfg.eks_namespace)

            t = raw.get("terraform", {})
            cfg.tf_state_bucket  = t.get("state_bucket", cfg.tf_state_bucket)
            cfg.tf_p1_state_key  = t.get("p1_state_key", cfg.tf_p1_state_key)
            cfg.tf_p2_state_key  = t.get("p2_state_key", cfg.tf_p2_state_key)

            g = raw.get("github", {})
            cfg.github_repo      = g.get("repo", cfg.github_repo)
            cfg.github_branch    = g.get("branch", cfg.github_branch)
            cfg.gitops_app_path  = g.get("gitops_app_path", cfg.gitops_app_path)

            ac = raw.get("argocd", {})
            cfg.argocd_namespace = ac.get("namespace", cfg.argocd_namespace)
            cfg.argocd_app_name  = ac.get("app_name", cfg.argocd_app_name)

            cfg.prometheus_address = raw.get("prometheus", {}).get("address", cfg.prometheus_address)
            break

    return cfg.resolve()
