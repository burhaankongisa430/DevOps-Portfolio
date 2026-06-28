"""Shell helpers — run external commands with Rich output."""

from __future__ import annotations

import shlex
import subprocess
import sys
from typing import Optional

from rich.console import Console
from rich.text import Text

console = Console()


class CommandError(Exception):
    def __init__(self, cmd: str, returncode: int, stderr: str = ""):
        self.cmd = cmd
        self.returncode = returncode
        self.stderr = stderr
        super().__init__(f"Command failed (exit {returncode}): {cmd}")


def run(
    cmd: str | list[str],
    *,
    cwd: Optional[str] = None,
    env: Optional[dict] = None,
    capture: bool = False,
    check: bool = True,
    show_cmd: bool = True,
) -> subprocess.CompletedProcess:
    """
    Run a shell command with optional Rich formatting.

    Args:
        cmd:      Command string or list of args.
        cwd:      Working directory.
        env:      Environment variables (merged with os.environ if not None).
        capture:  If True, capture and return stdout/stderr instead of printing.
        check:    If True, raise CommandError on non-zero exit.
        show_cmd: If True, print the command before running it.
    """
    if isinstance(cmd, str):
        args = shlex.split(cmd)
    else:
        args = cmd

    if show_cmd:
        console.print(f"[dim]$ {' '.join(args)}[/dim]")

    import os
    merged_env = {**os.environ, **(env or {})}

    result = subprocess.run(
        args,
        cwd=cwd,
        env=merged_env,
        capture_output=capture,
        text=True,
    )

    if check and result.returncode != 0:
        if capture and result.stderr:
            console.print(f"[red]{result.stderr}[/red]")
        raise CommandError(" ".join(args), result.returncode, result.stderr or "")

    return result


def run_streaming(cmd: str | list[str], *, cwd: Optional[str] = None, check: bool = True) -> int:
    """Run a command and stream its output in real-time (useful for terraform, docker build)."""
    if isinstance(cmd, str):
        args = shlex.split(cmd)
    else:
        args = cmd

    console.print(f"[dim]$ {' '.join(args)}[/dim]")

    import os
    proc = subprocess.Popen(args, cwd=cwd, env=os.environ.copy(), text=True)
    proc.wait()

    if check and proc.returncode != 0:
        raise CommandError(" ".join(args), proc.returncode)

    return proc.returncode


def require_tool(name: str) -> None:
    """Abort with a helpful message if a required tool is not in PATH."""
    import shutil
    if shutil.which(name) is None:
        console.print(f"[red]✗ Required tool not found: [bold]{name}[/bold][/red]")
        console.print(f"  Install it and ensure it is on your PATH before running this command.")
        sys.exit(1)
