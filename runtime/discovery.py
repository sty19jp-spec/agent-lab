from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

from runtime.loader import LoaderContract


@dataclass(frozen=True)
class DiscoveryResult:
    task_package: Dict[str, Any]
    runtime_bundle: Dict[str, Any]
    metadata: Dict[str, Any]


def _resolve_ref(ref: str) -> Dict[str, Any]:
    path = Path(ref)
    if path.exists():
        return {
            "ref": ref,
            "kind": "local_path",
            "resolved": str(path.resolve()),
            "exists": True,
        }

    return {
        "ref": ref,
        "kind": "logical_ref",
        "resolved": None,
        "exists": False,
    }


def discover(contract: LoaderContract) -> DiscoveryResult:
    now = datetime.now(timezone.utc).isoformat()
    return DiscoveryResult(
        task_package=_resolve_ref(contract.task_package_ref),
        runtime_bundle=_resolve_ref(contract.runtime_bundle_ref),
        metadata={
            "trigger_type": contract.trigger_type,
            "requested_operator": contract.requested_operator,
            "discovered_at": now,
            "metadata_version": "phase22-minimal-v1",
        },
    )
