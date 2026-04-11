from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROVENANCE_KEYS = (
    "execution_identity",
    "runtime_fingerprint",
    "repository_state",
    "execution_context",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_path(root: Path, raw: str) -> Path:
    candidate = Path(raw)
    if candidate.is_absolute():
        return candidate
    return (root / candidate).resolve()


def detect_artifact_kind(payload: dict[str, Any]) -> str:
    if "backend_id" in payload and "command_summary" in payload:
        return "backend_evidence"
    if "source_run_bundle_path" in payload and "reproduced_gate_verdict" in payload:
        return "ci_verifier"
    if "task_id" in payload and "verification_status" in payload and "actor_role" in payload:
        return "run_bundle"
    raise ValueError("artifact kind を判定できません。")


def validate_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        datetime.fromisoformat(normalized)
    except ValueError:
        return False
    return True


def validate_single_provenance(label: str, provenance: Any, errors: list[str], warnings: list[str]) -> None:
    if provenance is None:
        warnings.append(f"{label} is missing; accepted for backward compatibility.")
        return
    if not isinstance(provenance, dict):
        errors.append(f"{label} must be an object.")
        return
    for key in PROVENANCE_KEYS:
        if key not in provenance:
            errors.append(f"{label}.{key} is missing.")
            continue
        if not isinstance(provenance[key], dict):
            errors.append(f"{label}.{key} must be an object.")

    if errors:
        return

    execution_identity = provenance["execution_identity"]
    runtime_fingerprint = provenance["runtime_fingerprint"]
    repository_state = provenance["repository_state"]
    execution_context = provenance["execution_context"]

    for key in ("executor_id", "executor_type", "operator"):
        if not isinstance(execution_identity.get(key), str) or not execution_identity[key].strip():
            errors.append(f"{label}.execution_identity.{key} must be a non-empty string.")

    for key in ("runtime_name", "runtime_version"):
        if not isinstance(runtime_fingerprint.get(key), str) or not runtime_fingerprint[key].strip():
            errors.append(f"{label}.runtime_fingerprint.{key} must be a non-empty string.")

    for key in ("repository_commit", "repository_branch"):
        if not isinstance(repository_state.get(key), str) or not repository_state[key].strip():
            errors.append(f"{label}.repository_state.{key} must be a non-empty string.")
    if not isinstance(repository_state.get("repository_dirty"), bool):
        errors.append(f"{label}.repository_state.repository_dirty must be bool.")

    if not validate_timestamp(execution_context.get("execution_timestamp")):
        errors.append(f"{label}.execution_context.execution_timestamp must be RFC3339-like timestamp.")
    if not isinstance(execution_context.get("trigger_type"), str) or not execution_context["trigger_type"].strip():
        errors.append(f"{label}.execution_context.trigger_type must be a non-empty string.")
    if not isinstance(execution_context.get("retry_counter"), int) or execution_context["retry_counter"] < 0:
        errors.append(f"{label}.execution_context.retry_counter must be a non-negative integer.")


def validate_payload(kind: str, payload: dict[str, Any]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    if kind == "backend_evidence":
        validate_single_provenance("provenance", payload.get("provenance"), errors, warnings)
    elif kind == "run_bundle":
        validate_single_provenance("provenance", payload.get("provenance"), errors, warnings)
    elif kind == "ci_verifier":
        validate_single_provenance("source_provenance", payload.get("source_provenance"), errors, warnings)
        validate_single_provenance("verifier_provenance", payload.get("verifier_provenance"), errors, warnings)
        if payload.get("reproduced_gate_verdict") not in {"pass", "hold", "fail"}:
            errors.append("ci_verifier.reproduced_gate_verdict must be one of pass/hold/fail.")
    return errors, warnings


def default_output(root: Path, artifact_path: Path) -> Path:
    return root / "reports" / "evidence_validation" / f"{artifact_path.stem}_provenance_validation.json"


def main() -> int:
    parser = argparse.ArgumentParser(description="backend evidence / run bundle / ci verifier の provenance を検証します。")
    parser.add_argument("--root", default=".")
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    artifact_path = resolve_path(root, args.artifact)
    payload = load_json(artifact_path)
    kind = detect_artifact_kind(payload)
    errors, warnings = validate_payload(kind, payload)

    result = {
        "artifact_path": str(artifact_path.resolve().relative_to(root)).replace("\\", "/"),
        "artifact_kind": kind,
        "validator_verdict": "fail" if errors else "pass",
        "errors": errors,
        "warnings": warnings,
        "validated_at": utc_now(),
    }

    output_path = resolve_path(root, args.output) if args.output else default_output(root, artifact_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(output_path)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
