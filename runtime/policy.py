from __future__ import annotations

from dataclasses import dataclass

from runtime.discovery import DiscoveryResult
from runtime.loader import LoaderContract
from runtime.trigger import CANONICAL_TRIGGER_TYPES

CANONICAL_OPERATORS = {"Architect", "Executor", "Auditor", "Human"}


@dataclass(frozen=True)
class GateResult:
    gate: str
    passed: bool
    reason: str


@dataclass(frozen=True)
class PreflightResult:
    gate_a: GateResult
    gate_b: GateResult

    @property
    def passed(self) -> bool:
        return self.gate_a.passed and self.gate_b.passed


def evaluate_preflight(contract: LoaderContract, discovery: DiscoveryResult) -> PreflightResult:
    gate_a_passed = (
        contract.trigger_type.lower() in CANONICAL_TRIGGER_TYPES
        and contract.requested_operator in CANONICAL_OPERATORS
    )
    gate_a_reason = (
        "canonical set matched"
        if gate_a_passed
        else "trigger_type/requested_operator is outside canonical set"
    )

    gate_b_passed = True
    gate_b_reason = "runtime policy passed"

    task_resolved = discovery.task_package.get("exists", False)
    bundle_resolved = discovery.runtime_bundle.get("exists", False)
    task_doc = discovery.task_package.get("document", {})
    bundle_doc = discovery.runtime_bundle.get("document", {})

    if contract.trigger_type.lower() == "event_stub" and contract.requested_operator != "Executor":
        gate_b_passed = False
        gate_b_reason = "event_stub trigger requires requested_operator=Executor"
    elif not task_resolved:
        gate_b_passed = False
        gate_b_reason = "task package could not be resolved"
    elif not bundle_resolved:
        gate_b_passed = False
        gate_b_reason = "runtime bundle could not be resolved"
    elif task_doc.get("operator") != contract.requested_operator:
        gate_b_passed = False
        gate_b_reason = "requested_operator does not match task operator"
    elif bundle_doc.get("executor") != contract.requested_operator:
        gate_b_passed = False
        gate_b_reason = "requested_operator does not match bundle executor"

    return PreflightResult(
        gate_a=GateResult(gate="Gate A (Canonical Set)", passed=gate_a_passed, reason=gate_a_reason),
        gate_b=GateResult(gate="Gate B (Runtime Policy)", passed=gate_b_passed, reason=gate_b_reason),
    )
