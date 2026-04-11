from __future__ import annotations

import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


RUNTIME_VERSION = "p5-c1-v1"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def clean_string(value: Any, fallback: str = "unknown") -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    return text if text else fallback


def run_git(root: Path, *args: str) -> str | None:
    try:
        output = subprocess.check_output(
            ["git", *args],
            cwd=root,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return output.strip()
    except (FileNotFoundError, subprocess.CalledProcessError, OSError):
        return None


def build_repository_state(root: Path) -> dict[str, Any]:
    commit = run_git(root, "rev-parse", "HEAD")
    branch = run_git(root, "rev-parse", "--abbrev-ref", "HEAD")
    status = run_git(root, "status", "--porcelain")
    return {
        "repository_commit": clean_string(commit),
        "repository_branch": clean_string(branch),
        "repository_dirty": bool(status) if status is not None else False,
    }


def build_provenance(
    *,
    root: Path,
    executor_type: str,
    operator: str,
    runtime_name: str,
    executor_id: str | None = None,
    bundle_version: str | None = None,
    task_version: str | None = None,
    trigger_type: str = "manual",
    retry_counter: int = 0,
    execution_timestamp: str | None = None,
) -> dict[str, Any]:
    resolved_executor_id = (
        executor_id
        or os.getenv("CODEX_SESSION_ID")
        or os.getenv("GITHUB_RUN_ID")
        or os.getenv("CI_JOB_ID")
        or f"{executor_type}-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"
    )
    return {
        "execution_identity": {
            "executor_id": clean_string(resolved_executor_id),
            "executor_type": clean_string(executor_type),
            "operator": clean_string(operator),
        },
        "runtime_fingerprint": {
            "runtime_name": clean_string(runtime_name),
            "runtime_version": RUNTIME_VERSION,
            "bundle_version": bundle_version,
            "task_version": task_version,
        },
        "repository_state": build_repository_state(root),
        "execution_context": {
            "execution_timestamp": execution_timestamp or utc_now(),
            "trigger_type": clean_string(trigger_type),
            "retry_counter": retry_counter,
        },
    }
