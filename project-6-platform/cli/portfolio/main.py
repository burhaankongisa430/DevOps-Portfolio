"""
portfolio — golden-path CLI for the DevOps portfolio platform.

Wraps the five-project stack (IaC, containers, GitOps, CI/CD, observability)
behind a single command interface so a developer can provision an environment,
deploy a service, and inspect system health without knowing Terraform, kubectl,
or Helm directly.

Usage:
  portfolio status                         # rich platform health table
  portfolio deploy image --tag sha-abc1234 # build + scan + push
  portfolio deploy gitops --tag sha-abc1234 # update ArgoCD Application
  portfolio verify sha-abc1234             # verify cosign signature
  portfolio new payment-service            # scaffold a new service
"""

import typer
from rich.console import Console

from portfolio.commands import deploy, status, verify, new_service

console = Console()

app = typer.Typer(
    name="portfolio",
    help="Golden-path CLI — provision, deploy, and monitor the DevOps portfolio platform.",
    no_args_is_help=True,
    rich_markup_mode="rich",
)

# Sub-command groups
app.add_typer(deploy.app,      name="deploy",  help="Build, push, and deploy a service image")
app.add_typer(status.app,      name="status",  help="Show platform health across all layers",     invoke_without_command=True)
app.add_typer(verify.app,      name="verify",  help="Verify cosign signature on a deployed image", invoke_without_command=True)
app.add_typer(new_service.app, name="new",     help="Scaffold a new service from the golden path", invoke_without_command=True)


@app.command("version")
def version_cmd() -> None:
    """Print the CLI version."""
    from portfolio import __version__
    console.print(f"portfolio-cli {__version__}")


if __name__ == "__main__":
    app()
