"""
portfolio deploy  — build → scan → push → gitops update.

Encapsulates the same steps the CI/CD pipeline runs (Project 4) so engineers
can trigger a deploy from their laptop without needing to push a commit first.
Useful for hotfixes and demos; the CI pipeline is still the canonical path.
"""

from __future__ import annotations

import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.panel import Panel

from portfolio.utils import config as cfg_module
from portfolio.utils.shell import run, run_streaming, require_tool, CommandError

app = typer.Typer(no_args_is_help=True)
console = Console()


@app.command()
def image(
    tag: Optional[str] = typer.Option(None, "--tag", "-t", help="Image tag (default: sha-<git-sha>)"),
    push: bool = typer.Option(True, "--push/--no-push", help="Push image to ECR after building"),
    scan: bool = typer.Option(True, "--scan/--no-scan", help="Run Trivy scan before push"),
    sign: bool = typer.Option(False, "--sign/--no-sign", help="Sign image with cosign after push"),
    config_path: Optional[Path] = typer.Option(None, "--config", envvar="PORTFOLIO_CONFIG"),
) -> None:
    """Build the application image and push it to ECR."""
    require_tool("docker")
    if push:
        require_tool("aws")
    if scan:
        require_tool("trivy")
    if sign:
        require_tool("cosign")

    cfg = cfg_module.load(config_path)

    if not tag:
        try:
            result = run("git rev-parse --short HEAD", capture=True, show_cmd=False)
            tag = f"sha-{result.stdout.strip()}"
        except CommandError:
            tag = f"local-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}"

    image_uri = f"{cfg.image_base}:{tag}"
    build_time = datetime.now(timezone.utc).isoformat()

    # Locate the app directory
    app_dir = Path.cwd()
    for parent in [Path.cwd(), *Path.cwd().parents]:
        candidate = parent / "project-2-containers" / "app"
        if candidate.exists():
            app_dir = candidate
            break

    console.print(Panel(
        f"[bold]Build[/bold]\n  Image : {image_uri}\n  Source: {app_dir}",
        title="portfolio deploy image",
        border_style="blue",
    ))

    run_streaming([
        "docker", "build",
        "--build-arg", f"VERSION={tag}",
        "--build-arg", f"BUILD_TIME={build_time}",
        "--tag", image_uri,
        str(app_dir),
    ])
    console.print(f"[green]✓ Build complete[/green]")

    if scan:
        console.print("\n[bold]Trivy image scan...[/bold]")
        try:
            run([
                "trivy", "image",
                "--severity", "CRITICAL,HIGH",
                "--exit-code", "1",
                "--ignore-unfixed",
                image_uri,
            ])
            console.print("[green]✓ Trivy scan passed[/green]")
        except CommandError:
            console.print("[red]✗ Trivy found vulnerabilities — aborting[/red]")
            raise typer.Exit(1)

    if push:
        console.print("\n[bold]Pushing to ECR...[/bold]")
        registry = cfg.ecr_registry
        run(f"aws ecr get-login-password --region {cfg.aws_region} | docker login --username AWS --password-stdin {registry}", show_cmd=False)
        run(["docker", "push", image_uri])
        console.print(f"[green]✓ Pushed {image_uri}[/green]")

        if sign:
            console.print("\n[bold]Signing with cosign (keyless)...[/bold]")
            run(["cosign", "sign", "--yes", image_uri], env={"COSIGN_EXPERIMENTAL": "1"})
            console.print("[green]✓ Image signed[/green]")

    console.print(f"\n[green bold]Done.[/green bold] Next: [cyan]portfolio deploy gitops --tag {tag}[/cyan]")


@app.command()
def gitops(
    tag: str = typer.Argument(..., help="Image tag to deploy (e.g. sha-abc1234)"),
    config_path: Optional[Path] = typer.Option(None, "--config", envvar="PORTFOLIO_CONFIG"),
) -> None:
    """Update the ArgoCD Application manifest to trigger a canary deploy."""
    require_tool("git")
    require_tool("yq")

    cfg = cfg_module.load(config_path)

    # Find the gitops path relative to the repo root
    repo_root = Path.cwd()
    for parent in [Path.cwd(), *Path.cwd().parents]:
        if (parent / ".git").exists():
            repo_root = parent
            break

    app_manifest = repo_root / cfg.gitops_app_path
    if not app_manifest.exists():
        console.print(f"[red]✗ ArgoCD Application manifest not found: {app_manifest}[/red]")
        console.print("  Check gitops_app_path in .portfolio.yaml")
        raise typer.Exit(1)

    console.print(f"[bold]Updating image tag → {tag}[/bold]")
    console.print(f"  File: {app_manifest}")

    run([
        "yq", "-i",
        f'(.spec.source.helm.parameters[] | select(.name == "image.tag")).value = "{tag}"',
        str(app_manifest),
    ])

    run(["git", "config", "user.name", "portfolio-cli"], cwd=str(repo_root))
    run(["git", "config", "user.email", "portfolio-cli@local"], cwd=str(repo_root))
    run(["git", "add", str(app_manifest)], cwd=str(repo_root))

    diff = run(["git", "diff", "--cached", "--stat"], capture=True, cwd=str(repo_root), show_cmd=False)
    if not diff.stdout.strip():
        console.print(f"[yellow]Image tag is already {tag} — nothing to commit.[/yellow]")
        return

    run(["git", "commit", "-m", f"deploy: {tag} via portfolio-cli [skip ci]"], cwd=str(repo_root))
    run(["git", "push"], cwd=str(repo_root))

    console.print(f"\n[green]✓ Pushed GitOps commit.[/green]")
    console.print("  ArgoCD will detect the change within 30s and start the canary.")
    console.print("  Watch: [cyan]portfolio status[/cyan]  or  [cyan]kubectl argo rollouts get rollout app --watch[/cyan]")


@app.command()
def run_all(
    tag: Optional[str] = typer.Option(None, "--tag", "-t"),
    config_path: Optional[Path] = typer.Option(None, "--config", envvar="PORTFOLIO_CONFIG"),
) -> None:
    """Full deploy: build + scan + push + sign + gitops (single command)."""
    ctx = typer.get_current_context()
    # Delegate to image subcommand then gitops
    from typer.testing import CliRunner
    if not tag:
        result = run("git rev-parse --short HEAD", capture=True, show_cmd=False)
        tag = f"sha-{result.stdout.strip()}"

    ctx.invoke(image, tag=tag, push=True, scan=True, sign=True, config_path=config_path)
    ctx.invoke(gitops, tag=tag, config_path=config_path)
