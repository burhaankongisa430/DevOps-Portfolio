"""
portfolio status  — rich status table across the full P1–P5 stack.

Queries every layer of the platform and presents a single-pane-of-glass
view. Useful at the start of an on-call shift or before a demo.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Optional

import boto3
import typer
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from portfolio.utils import config as cfg_module
from portfolio.utils.shell import run, CommandError

app = typer.Typer()
console = Console()


def _eks_status(cfg) -> tuple[str, str]:
    try:
        eks = boto3.client("eks", region_name=cfg.aws_region)
        cluster = eks.describe_cluster(name=cfg.eks_cluster_name)["cluster"]
        status = cluster["status"]
        version = cluster.get("version", "?")
        if status == "ACTIVE":
            return "✓ Active", f"k8s v{version}"
        return f"⚠ {status}", f"k8s v{version}"
    except Exception as e:
        return "✗ Error", str(e)[:40]


def _pods_status(cfg) -> tuple[str, str]:
    try:
        result = run(
            ["kubectl", "get", "pods", "-n", cfg.eks_namespace,
             "-l", "app.kubernetes.io/name=app",
             "-o", "json"],
            capture=True, check=False, show_cmd=False,
        )
        if result.returncode != 0:
            return "✗ Error", "kubectl unavailable"
        pods = json.loads(result.stdout).get("items", [])
        ready = sum(
            1 for p in pods
            if all(c.get("ready") for c in p.get("status", {}).get("containerStatuses", []))
        )
        total = len(pods)
        tag = ""
        if pods:
            containers = pods[0]["spec"]["containers"]
            img = containers[0]["image"] if containers else ""
            tag = img.split(":")[-1] if ":" in img else img[-16:]

        if total == 0:
            return "– No pods", "not deployed"
        if ready == total:
            return "✓ Running", f"{tag} · {ready}/{total} ready"
        return f"⚠ Partial", f"{tag} · {ready}/{total} ready"
    except Exception as e:
        return "✗ Error", str(e)[:40]


def _rollout_status(cfg) -> tuple[str, str]:
    try:
        result = run(
            ["kubectl", "argo", "rollouts", "get", "rollout", "app",
             "-n", cfg.eks_namespace, "-o", "json"],
            capture=True, check=False, show_cmd=False,
        )
        if result.returncode != 0:
            return "– Unavailable", "argo rollouts plugin not found"
        data = json.loads(result.stdout)
        phase = data.get("status", {}).get("phase", "Unknown")
        current_image = ""
        for rs in data.get("status", {}).get("replicaSets", []):
            if rs.get("stable"):
                img = rs.get("template", {}).get("spec", {}).get("containers", [{}])[0].get("image", "")
                current_image = img.split(":")[-1] if ":" in img else img[-16:]
                break
        icon = "✓" if phase == "Healthy" else ("⚠" if phase == "Progressing" else "✗")
        return f"{icon} {phase}", current_image or phase
    except Exception as e:
        return "✗ Error", str(e)[:40]


def _argocd_status(cfg) -> tuple[str, str]:
    try:
        result = run(
            ["kubectl", "get", "application", cfg.argocd_app_name,
             "-n", cfg.argocd_namespace, "-o", "json"],
            capture=True, check=False, show_cmd=False,
        )
        if result.returncode != 0:
            return "– Unavailable", "argocd not deployed"
        data = json.loads(result.stdout)
        sync = data.get("status", {}).get("sync", {}).get("status", "Unknown")
        health = data.get("status", {}).get("health", {}).get("status", "Unknown")
        last_sync = data.get("status", {}).get("operationState", {}).get("finishedAt", "")
        detail = f"sync={sync} health={health}"
        if last_sync:
            detail += f" · {last_sync[:16]}"
        icon = "✓" if sync == "Synced" and health == "Healthy" else "⚠"
        return f"{icon} {sync}", detail
    except Exception as e:
        return "✗ Error", str(e)[:40]


def _guardduty_status(cfg) -> tuple[str, str]:
    try:
        gd = boto3.client("guardduty", region_name=cfg.aws_region)
        detectors = gd.list_detectors().get("DetectorIds", [])
        if not detectors:
            return "✗ Disabled", "enable GuardDuty (Project 5)"
        detector_id = detectors[0]
        findings = gd.list_findings(
            DetectorId=detector_id,
            FindingCriteria={
                "Criterion": {
                    "severity": {"Gte": 7},
                    "service.archived": {"Eq": ["false"]},
                }
            },
        ).get("FindingIds", [])
        high_count = len(findings)
        if high_count == 0:
            return "✓ Clean", "no HIGH/CRITICAL findings"
        return f"✗ {high_count} HIGH+", f"{high_count} unarchived findings"
    except Exception as e:
        return "– Error", str(e)[:40]


def _alb_endpoint(cfg) -> str:
    try:
        result = run(
            ["kubectl", "get", "ingress", "app", "-n", cfg.eks_namespace,
             "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}"],
            capture=True, check=False, show_cmd=False,
        )
        host = result.stdout.strip()
        return f"http://{host}" if host else "(not yet assigned)"
    except Exception:
        return "(unavailable)"


@app.callback(invoke_without_command=True)
def status(
    config_path: Optional[Path] = typer.Option(None, "--config", envvar="PORTFOLIO_CONFIG"),
) -> None:
    """Show platform health across all layers: IaC, EKS, pods, GitOps, security."""
    cfg = cfg_module.load(config_path)

    console.print()
    console.print(Panel(
        f"[bold]Project:[/bold] {cfg.project}   [bold]Environment:[/bold] {cfg.environment}   "
        f"[bold]Region:[/bold] {cfg.aws_region}",
        title="[bold cyan]Portfolio Platform Status[/bold cyan]",
        border_style="cyan",
    ))
    console.print()

    table = Table(show_header=True, header_style="bold", border_style="dim", expand=True)
    table.add_column("Layer", style="bold", width=20)
    table.add_column("Status", width=18)
    table.add_column("Detail")

    console.print("[dim]Gathering status...[/dim]")

    eks_status, eks_detail = _eks_status(cfg)
    pods_status, pods_detail = _pods_status(cfg)
    rollout_status, rollout_detail = _rollout_status(cfg)
    argocd_status, argocd_detail = _argocd_status(cfg)
    gd_status, gd_detail = _guardduty_status(cfg)

    def colour(s: str) -> str:
        if s.startswith("✓"):
            return f"[green]{s}[/green]"
        if s.startswith("⚠"):
            return f"[yellow]{s}[/yellow]"
        if s.startswith("✗"):
            return f"[red]{s}[/red]"
        return f"[dim]{s}[/dim]"

    table.add_row("EKS Cluster",    colour(eks_status),     eks_detail)
    table.add_row("App Pods",       colour(pods_status),    pods_detail)
    table.add_row("Argo Rollout",   colour(rollout_status), rollout_detail)
    table.add_row("ArgoCD Sync",    colour(argocd_status),  argocd_detail)
    table.add_row("GuardDuty",      colour(gd_status),      gd_detail)

    console.print(table)

    alb = _alb_endpoint(cfg)
    if alb != "(unavailable)":
        console.print(f"\n  [bold]ALB Endpoint:[/bold] [cyan]{alb}[/cyan]")

    console.print()
