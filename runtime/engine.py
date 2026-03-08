from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any, Dict, List

from runtime.discovery import DiscoveryResult, discover
from runtime.evidence import CloseSummary, ExecutionSummary, build_evidence, persist_evidence
from runtime.provenance import build_provenance
from runtime.loader import LoaderContract
from runtime.policy import CANONICAL_OPERATORS, GateResult, PreflightResult, evaluate_preflight
from runtime.state import close_state, init_state, set_status
from runtime.trigger import CANONICAL_TRIGGER_TYPES, normalize_trigger


@dataclass(frozen=True)
class RuntimeResult:
    ok: bool
    evidence: Dict[str, Any]


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _to_repo_path(path_str: str, task_file: str | None) -> Path:
    raw = Path(path_str)
    if raw.is_absolute():
        return raw

    if task_file:
        task_dir = Path(task_file).parent
        candidate = task_dir / raw
        if candidate.exists():
            return candidate

    return Path.cwd() / raw


def _execute_docs_validation(discovery: DiscoveryResult, operator: str) -> ExecutionSummary:
    task_doc = discovery.task_package["document"]
    bundle_doc = discovery.runtime_bundle["document"]

    task_resolved = discovery.task_package.get("resolved")
    input_files = task_doc.get("input", {}).get("target_files", [])
    if not isinstance(input_files, list) or not input_files:
        raise ValueError("docs_validation requires input.target_files as a non-empty list")

    report_path_raw = task_doc.get("output", {}).get("report_path")
    if not isinstance(report_path_raw, str) or not report_path_raw.strip():
        report_path_raw = f"examples/evidence/{task_doc.get('task_id', 'task')}-validation-report.json"

    checks: List[Dict[str, Any]] = []
    missing = 0

    for entry in input_files:
        file_path = _to_repo_path(str(entry), task_resolved)
        exists = file_path.exists()
        is_markdown = file_path.suffix.lower() == ".md"
        size_bytes = file_path.stat().st_size if exists and file_path.is_file() else 0

        if not exists:
            missing += 1

        checks.append(
            {
                "path": str(file_path.resolve()),
                "exists": exists,
                "is_markdown": is_markdown,
                "size_bytes": size_bytes,
            }
        )

    report_path = _to_repo_path(report_path_raw, task_resolved)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "task_id": task_doc.get("task_id"),
        "task_type": task_doc.get("task_type"),
        "bundle_id": bundle_doc.get("bundle_id"),
        "bundle_version": bundle_doc.get("bundle_version"),
        "checked_at": _utc_now(),
        "checks": checks,
        "missing_count": missing,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=True, indent=2), encoding="utf-8")

    success = missing == 0
    detail = "docs validation passed" if success else "docs validation failed because some files are missing"

    return ExecutionSummary(
        success=success,
        action="docs_validation",
        operator=operator,
        detail=detail,
        outputs={
            "validation_report": str(report_path.resolve()),
            "checked_files": len(checks),
            "missing_files": missing,
        },
    )


def _execute_task(contract: LoaderContract, discovery: DiscoveryResult) -> ExecutionSummary:
    task_doc = discovery.task_package.get("document", {})
    task_type = task_doc.get("task_type")

    if task_type == "docs_validation":
        return _execute_docs_validation(discovery, contract.requested_operator)

    raise ValueError(f"unsupported task_type: {task_type}")


def _build_task_evidence(discovery: DiscoveryResult) -> Dict[str, Any]:
    task_doc = discovery.task_package.get("document", {})
    bundle_doc = discovery.runtime_bundle.get("document", {})
    return {
        "task_ref": discovery.task_package.get("ref"),
        "task_resolved": discovery.task_package.get("resolved"),
        "task_id": task_doc.get("task_id"),
        "task_type": task_doc.get("task_type"),
        "bundle_ref": discovery.runtime_bundle.get("ref"),
        "bundle_resolved": discovery.runtime_bundle.get("resolved"),
        "bundle_id": bundle_doc.get("bundle_id"),
        "bundle_version": bundle_doc.get("bundle_version"),
    }


def _build_fallback_preflight(contract: LoaderContract, reason: str) -> PreflightResult:
    gate_a_passed = (
        contract.trigger_type.lower() in CANONICAL_TRIGGER_TYPES
        and contract.requested_operator in CANONICAL_OPERATORS
    )
    gate_a_reason = (
        "canonical set matched"
        if gate_a_passed
        else "trigger_type/requested_operator is outside canonical set"
    )
    return PreflightResult(
        gate_a=GateResult(gate="Gate A (Canonical Set)", passed=gate_a_passed, reason=gate_a_reason),
        gate_b=GateResult(gate="Gate B (Runtime Policy)", passed=False, reason=reason),
    )


def _build_minimal_task_evidence(contract: LoaderContract) -> Dict[str, Any]:
    return {
        "task_ref": contract.task_package_ref,
        "task_resolved": None,
        "task_id": None,
        "task_type": None,
        "bundle_ref": contract.runtime_bundle_ref,
        "bundle_resolved": None,
        "bundle_id": None,
        "bundle_version": None,
    }


def run_runtime(contract: LoaderContract, retry_counter: int = 0) -> RuntimeResult:
    state = init_state(contract, retry_counter)
    discovery: DiscoveryResult | None = None

    try:
        set_status(state, "loading")

        set_status(state, "discovery")
        discovery = discover(contract)
        task_evidence = _build_task_evidence(discovery)

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
                outputs={},
            )
            close_summary = CloseSummary(
                run_id=state.run_id,
                status=state.status,
                dedup_key=state.dedup_key,
                retry_counter=state.retry_counter,
            )
            provenance = build_provenance(
                contract=contract,
                state=state,
                task_evidence=task_evidence,
                task_document=discovery.task_package.get("document", {}),
                trigger_type=discovery.metadata.get("trigger_type"),
            )
            evidence = build_evidence(
                state,
                preflight,
                execution,
                close_summary,
                task_evidence,
                provenance=provenance,
            )
            evidence["evidence_file"] = persist_evidence(evidence)
            return RuntimeResult(ok=False, evidence=evidence)

        set_status(state, "execute")
        execution = _execute_task(contract, discovery)

        set_status(state, "evidence")
        close_state(state, status="closed" if execution.success else "failed")
        close_summary = CloseSummary(
            run_id=state.run_id,
            status=state.status,
            dedup_key=state.dedup_key,
            retry_counter=state.retry_counter,
        )
        provenance = build_provenance(
            contract=contract,
            state=state,
            task_evidence=task_evidence,
            task_document=discovery.task_package.get("document", {}),
            trigger_type=discovery.metadata.get("trigger_type"),
        )
        evidence = build_evidence(
            state,
            preflight,
            execution,
            close_summary,
            task_evidence,
            provenance=provenance,
        )
        evidence_output = discovery.task_package.get("document", {}).get("output", {}).get("evidence_path")
        evidence["evidence_file"] = persist_evidence(evidence, output_path=evidence_output)
        return RuntimeResult(ok=execution.success, evidence=evidence)
    except Exception as exc:
        close_state(state, status="failed", error=str(exc))
        if discovery is not None:
            fallback_preflight = evaluate_preflight(contract, discovery)
            task_evidence = _build_task_evidence(discovery)
        else:
            fallback_preflight = _build_fallback_preflight(
                contract,
                reason="discovery is unavailable because discovery step failed",
            )
            task_evidence = _build_minimal_task_evidence(contract)
        execution = ExecutionSummary(
            success=False,
            action="execute_error",
            operator=contract.requested_operator,
            detail=str(exc),
            outputs={},
        )
        close_summary = CloseSummary(
            run_id=state.run_id,
            status=state.status,
            dedup_key=state.dedup_key,
            retry_counter=state.retry_counter,
        )
        task_document = discovery.task_package.get("document", {}) if discovery is not None else {}
        trigger_type = discovery.metadata.get("trigger_type") if discovery is not None else contract.trigger_type
        provenance = build_provenance(
            contract=contract,
            state=state,
            task_evidence=task_evidence,
            task_document=task_document,
            trigger_type=trigger_type,
        )
        evidence = build_evidence(
            state,
            fallback_preflight,
            execution,
            close_summary,
            task_evidence,
            provenance=provenance,
        )
        evidence["evidence_file"] = persist_evidence(evidence)
        return RuntimeResult(ok=False, evidence=evidence)
