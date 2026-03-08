from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict

from runtime.policy import PreflightResult
from runtime.state import RunState, state_to_dict


@dataclass(frozen=True)
class ExecutionSummary:
    success: bool
    action: str
    operator: str
    detail: str


@dataclass(frozen=True)
class CloseSummary:
    run_id: str
    status: str
    dedup_key: str
    retry_counter: int


def build_evidence(
    state: RunState,
    preflight: PreflightResult,
    execution: ExecutionSummary,
    close_summary: CloseSummary,
) -> Dict[str, Any]:
    return {
        "execution_summary": asdict(execution),
        "preflight_summary": {
            "passed": preflight.passed,
            "gate_a": asdict(preflight.gate_a),
            "gate_b": asdict(preflight.gate_b),
        },
        "close_summary": asdict(close_summary),
        "run_state": state_to_dict(state),
    }
