"""portfolio verify — confirm a deployed image was built by the CI pipeline."""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.panel import Panel

from portfolio.utils import config as cfg_module
from portfolio.utils.shell import run, require_tool, CommandError

app = typer.Typer()
console = Console()


@app.callback(invoke_without_command=True)
def verify(
    tag: str = typer.Argument(..., help="Image tag to verify (e.g. sha-abc1234)"),
    config_path: Optional[Path] = typer.Option(None, "--config", envvar="PORTFOLIO_CONFIG"),
) -> None:
    """
    Verify the cosign signature on a deployed image.

    Confirms the image was built by the GitHub Actions pipeline (Project 4)
    using keyless signing. Any image that was not built and signed by that
    pipeline will fail verification — protecting against supply-chain tampering.
    """
    require_tool("cosign")

    cfg = cfg_module.load(config_path)
    image_uri = f"{cfg.image_base}:{tag}"

    if not cfg.github_repo:
        console.print("[red]✗ github.repo is not set in .portfolio.yaml[/red]")
        raise typer.Exit(1)

    # The certificate identity is the specific workflow file path in the repo
    cert_identity = (
        f"https://github.com/{cfg.github_repo}/.github/workflows/pipeline.yaml"
        f"@refs/heads/{cfg.github_branch}"
    )

    console.print(Panel(
        f"[bold]Image:[/bold]             {image_uri}\n"
        f"[bold]Expected identity:[/bold] {cert_identity}\n"
        f"[bold]OIDC issuer:[/bold]       https://token.actions.githubusercontent.com",
        title="Signature Verification",
        border_style="blue",
    ))

    try:
        run([
            "cosign", "verify",
            "--certificate-identity", cert_identity,
            "--certificate-oidc-issuer", "https://token.actions.githubusercontent.com",
            image_uri,
        ])
        console.print(f"\n[green bold]✓ Signature verified.[/green bold]")
        console.print(f"  This image was built by the CI pipeline from [{cfg.github_repo}].")
    except CommandError:
        console.print(f"\n[red bold]✗ Signature verification failed.[/red bold]")
        console.print("  Either the image was not built by this pipeline, or the tag does not exist.")
        raise typer.Exit(1)
