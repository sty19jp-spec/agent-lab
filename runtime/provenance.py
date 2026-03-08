from __future__ import annotations

from datetime import datetime, timezone
import os
from pathlib import Path
import re
import subprocess
from typing import Any, Dict, Mapping

from runtime.loader import LoaderContract
from runtime.state import RunState

RUNTIME_NAME = "agent-lab-runtime"
UNKNOWN_VALUE = "unknown"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _clean(value: str | None) -> str:
    if value is None:
        return UNKNOWN_VALUE
    text = str(value).strip()
    return text if text else UNKNOWN_VALUE


def _read_runtime_registry() -> Dict[str, str]:
    registry_path = Path(__file__).resolve().parent / "registry.yaml"
    if not registry_path.exists() or not registry_path.is_file():
        return {}

    try:
        text = registry_path.read_text(encoding="utf-8")
    except OSError:
        return {}

    version_match = re.search(r"^\s*version:\s*[\"']?([^\"'\n]+)[\"']?\s*$", text, re.MULTILINE)
    executor_match = re.search(r"^\s*executor:\s*[\"']?([^\"'\n]+)[\"']?\s*$", text, re.MULTILINE)

    out: Dict[str, str] = {}
    if version_match:
        out["runtime_version"] = version_match.group(1).strip()
    if executor_match:
        out["executor_type"] = executor_match.group(1).strip()
    return out


def _read_git_repository_state(cwd: Path | None = None) -> Dict[str, Any]:
    run_cwd = cwd or Path.cwd()

    def _git(*args: str) -> str | None:
        try:
            out = subprocess.check_output(["git", *args], cwd=run_cwd, stderr=subprocess.DEVNULL, text=True)
            return out.strip()
        except (FileNotFoundError, subprocess.CalledProcessError, OSError):
            return None

    commit = _git("rev-parse", "HEAD")
    branch = _git("rev-parse", "--abbrev-ref", "HEAD")

    result: Dict[str, Any] = {
        "repository_commit": _clean(commit),
        "repository_branch": _clean(branch),
    }

    status = _git("status", "--porcelain")
    if status is not None:
        result["repository_dirty"] = bool(status)

    return result


def _derive_task_version(task_document: Mapping[str, Any]) -> str | None:
    value = task_document.get("task_version")
    if isinstance(value, str) and value.strip():
        return value.strip()

    contract = task_document.get("contract")
    if isinstance(contract, Mapping):
        contract_id = contract.get("contract_id")
        if isinstance(contract_id, str) and contract_id.strip():
            return contract_id.strip()

    return None


def build_provenance(
    *,
    contract: LoaderContract,
    state: RunState,
    task_evidence: Mapping[str, Any],
    task_document: Mapping[str, Any] | None = None,
    trigger_type: str | None = None,
) -> Dict[str, Any]:
    runtime_registry = _read_runtime_registry()

    executor_id = (
        os.getenv("CODEX_SESSION_ID")
        or os.getenv("GITHUB_RUN_ID")
        or os.getenv("CI_JOB_ID")
        or state.run_id
    )

    effective_trigger = trigger_type if isinstance(trigger_type, str) and trigger_type.strip() else contract.trigger_type

    provenance: Dict[str, Any] = {
        "execution_identity": {
            "executor_id": _clean(executor_id),
            "executor_type": _clean(os.getenv("EXECUTOR_TYPE") or runtime_registry.get("executor_type")),
            "operator": contract.requested_operator,
        },
        "runtime_fingerprint": {
            "runtime_name": RUNTIME_NAME,
            "runtime_version": _clean(runtime_registry.get("runtime_version")),
            "bundle_version": task_evidence.get("bundle_version"),
            "task_version": _derive_task_version(task_document or {}),
        },
        "repository_state": _read_git_repository_state(),
        "execution_context": {
            "execution_timestamp": state.ended_at or state.started_at or _utc_now(),
            "trigger_type": effective_trigger,
            "retry_counter": state.retry_counter,
        },
    }

    return provenance
