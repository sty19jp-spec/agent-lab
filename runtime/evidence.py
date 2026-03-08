from __future__ import annotations

from dataclasses import asdict, dataclass
import json
from pathlib import Path
from typing import Any, Dict

from runtime.policy import PreflightResult
from runtime.state import RunState, state_to_dict


@dataclass(frozen=True)
class ExecutionSummary:
    success: bool
    action: str
    operator: str
    detail: str
    outputs: Dict[str, Any]


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
    task_evidence: Dict[str, Any],
) -> Dict[str, Any]:
    execution_evidence = {
        "success": execution.success,
        "action": execution.action,
        "operator": execution.operator,
        "detail": execution.detail,
        "outputs": execution.outputs,
    }
    return {
        "task_evidence": task_evidence,
        "execution_evidence": execution_evidence,
        "execution_summary": asdict(execution),
        "preflight_summary": {
            "passed": preflight.passed,
            "gate_a": asdict(preflight.gate_a),
            "gate_b": asdict(preflight.gate_b),
        },
        "close_summary": asdict(close_summary),
        "run_state": state_to_dict(state),
    }


def persist_evidence(evidence: Dict[str, Any], output_path: str | None = None) -> str:
    run_id = evidence.get("run_state", {}).get("run_id", "run-unknown")
    target = Path(output_path) if output_path else Path("examples/evidence") / f"{run_id}.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(evidence, ensure_ascii=True, indent=2), encoding="utf-8")
    return str(target.resolve())