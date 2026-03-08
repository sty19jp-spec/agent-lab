from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import hashlib
from typing import Any, Dict, Optional

from runtime.loader import LoaderContract


@dataclass
class RunState:
    run_id: str
    status: str
    dedup_key: str
    retry_counter: int
    started_at: str
    ended_at: Optional[str] = None
    error: Optional[str] = None


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def build_dedup_key(contract: LoaderContract) -> str:
    base = "|".join(
        [
            contract.task_package_ref,
            contract.runtime_bundle_ref,
            contract.trigger_type.lower(),
            contract.requested_operator,
        ]
    )
    return hashlib.sha256(base.encode("utf-8")).hexdigest()[:16]


def init_state(contract: LoaderContract, retry_counter: int) -> RunState:
    dedup_key = build_dedup_key(contract)
    run_id = f"run-{dedup_key}-{retry_counter}"
    return RunState(
        run_id=run_id,
        status="initialized",
        dedup_key=dedup_key,
        retry_counter=retry_counter,
        started_at=_utc_now(),
    )


def set_status(state: RunState, status: str) -> None:
    state.status = status


def close_state(state: RunState, status: str, error: Optional[str] = None) -> None:
    state.status = status
    state.error = error
    state.ended_at = _utc_now()


def state_to_dict(state: RunState) -> Dict[str, Any]:
    return asdict(state)
