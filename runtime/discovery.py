from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from runtime.loader import LoaderContract, load_bundle_yaml, load_task_yaml


@dataclass(frozen=True)
class DiscoveryResult:
    task_package: Dict[str, Any]
    runtime_bundle: Dict[str, Any]
    metadata: Dict[str, Any]


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _normalize_ref(ref: str) -> str:
    return ref.strip()


def _logical_candidates(ref: str, root_dir: str, scheme: str, default_file: str) -> List[Path]:
    normalized = _normalize_ref(ref)

    if normalized.startswith(f"{scheme}://"):
        logical = normalized.split("://", 1)[1]
    else:
        logical = normalized

    logical_id = logical.split("@", 1)[0].strip("/")
    if not logical_id:
        return []

    return [
        Path(root_dir) / logical_id / default_file,
        Path(root_dir) / f"{logical_id}.yaml",
    ]


def _pick_existing_path(paths: List[Path]) -> Optional[Path]:
    for path in paths:
        if path.exists():
            if path.is_dir():
                continue
            return path
    return None


def _resolve_task_package(ref: str) -> Dict[str, Any]:
    normalized = _normalize_ref(ref)
    direct = Path(normalized)
    candidates: List[Path] = []

    if direct.exists():
        if direct.is_dir():
            candidates.append(direct / "task.yaml")
        else:
            candidates.append(direct)

    if not candidates:
        candidates.extend(_logical_candidates(normalized, "task", "task", "task.yaml"))

    resolved = _pick_existing_path(candidates)
    if resolved is None:
        return {
            "ref": ref,
            "kind": "task_package",
            "resolved": None,
            "exists": False,
            "attempted": [str(path) for path in candidates],
        }

    return {
        "ref": ref,
        "kind": "task_package",
        "resolved": str(resolved.resolve()),
        "exists": True,
        "document": load_task_yaml(resolved),
    }


def _resolve_runtime_bundle(ref: str) -> Dict[str, Any]:
    normalized = _normalize_ref(ref)
    direct = Path(normalized)
    candidates: List[Path] = []

    if direct.exists():
        if direct.is_dir():
            candidates.append(direct / "bundle.yaml")
        else:
            candidates.append(direct)

    if not candidates:
        candidates.extend(_logical_candidates(normalized, "bundle", "bundle", "bundle.yaml"))

    resolved = _pick_existing_path(candidates)
    if resolved is None:
        return {
            "ref": ref,
            "kind": "runtime_bundle",
            "resolved": None,
            "exists": False,
            "attempted": [str(path) for path in candidates],
        }

    return {
        "ref": ref,
        "kind": "runtime_bundle",
        "resolved": str(resolved.resolve()),
        "exists": True,
        "document": load_bundle_yaml(resolved),
    }


def discover(contract: LoaderContract) -> DiscoveryResult:
    return DiscoveryResult(
        task_package=_resolve_task_package(contract.task_package_ref),
        runtime_bundle=_resolve_runtime_bundle(contract.runtime_bundle_ref),
        metadata={
            "trigger_type": contract.trigger_type,
            "requested_operator": contract.requested_operator,
            "discovered_at": _utc_now(),
            "metadata_version": "phase23-minimal-v1",
        },
    )