from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict

from runtime.discovery import discover
from runtime.evidence import CloseSummary, ExecutionSummary, build_evidence
from runtime.loader import LoaderContract
from runtime.policy import evaluate_preflight
from runtime.state import close_state, init_state, set_status
from runtime.trigger import normalize_trigger


@dataclass(frozen=True)
class RuntimeResult:
    ok: bool
    evidence: Dict[str, Any]


def _execute_stub(contract: LoaderContract) -> ExecutionSummary:
    return ExecutionSummary(
        success=True,
        action="execute_stub",
        operator=contract.requested_operator,
        detail="minimal execution path completed",
    )


def run_runtime(contract: LoaderContract, retry_counter: int = 0) -> RuntimeResult:
    state = init_state(contract, retry_counter)

    try:
        set_status(state, "loading")

        set_status(state, "discovery")
        discovery = discover(contract)

        set_status(state, "preflight")
        normalize_trigger(contract.trigger_type)
        preflight = evaluate_preflight(contract, discovery)
        if not preflight.passed:
            close_state(state, status="blocked", error="preflight_failed")
            execution = ExecutionSummary(
                success=False,
                action="execute_skipped",
                operator=contract.requested_operator,
                detail="execution skipped because preflight failed",
            )
            close_summary = CloseSummary(
                run_id=state.run_id,
                status=state.status,
                dedup_key=state.dedup_key,
                retry_counter=state.retry_counter,
            )
            return RuntimeResult(
                ok=False,
                evidence=build_evidence(state, preflight, execution, close_summary),
            )

        set_status(state, "execute")
        execution = _execute_stub(contract)

        set_status(state, "evidence")
        close_state(state, status="closed")
        close_summary = CloseSummary(
            run_id=state.run_id,
            status=state.status,
            dedup_key=state.dedup_key,
            retry_counter=state.retry_counter,
        )
        return RuntimeResult(
            ok=True,
            evidence=build_evidence(state, preflight, execution, close_summary),
        )
    except Exception as exc:
        close_state(state, status="failed", error=str(exc))
        fallback_preflight = evaluate_preflight(contract, discover(contract))
        execution = ExecutionSummary(
            success=False,
            action="execute_error",
            operator=contract.requested_operator,
            detail=str(exc),
        )
        close_summary = CloseSummary(
            run_id=state.run_id,
            status=state.status,
            dedup_key=state.dedup_key,
            retry_counter=state.retry_counter,
        )
        return RuntimeResult(
            ok=False,
            evidence=build_evidence(state, fallback_preflight, execution, close_summary),
        )
