#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from typing import Any, Dict, List, Mapping, Optional

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from runtime.loader import load_bundle_yaml, load_task_yaml

SCHEMA_NAME = "execution-evidence"
SCHEMA_VERSION = "v1"
CANONICAL_OPERATORS = {"Architect", "Executor", "Auditor", "Human"}
TOP_LEVEL_KEYS = (
    "task_evidence",
    "execution_evidence",
    "execution_summary",
    "preflight_summary",
    "close_summary",
    "run_state",
)


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _is_non_negative_int(value: Any) -> bool:
    return isinstance(value, int) and value >= 0


def _resolve_any_path(path_str: str, repo_root: Path, base_dir: Path) -> Path:
    raw = Path(path_str)
    if raw.is_absolute():
        return raw
    base_candidate = (base_dir / raw).resolve()
    if base_candidate.exists():
        return base_candidate
    return (repo_root / raw).resolve()


def _logical_candidates(ref: str, root_dir: str, scheme: str, default_file: str, repo_root: Path) -> List[Path]:
    normalized = ref.strip()
    logical = normalized
    if normalized.startswith(f"{scheme}://"):
        logical = normalized.split("://", 1)[1]
    logical_id = logical.split("@", 1)[0].strip("/")
    if not logical_id:
        return []
    return [
        repo_root / root_dir / logical_id / default_file,
        repo_root / root_dir / f"{logical_id}.yaml",
    ]


def _resolve_task_ref(ref: str, repo_root: Path) -> Optional[Path]:
    normalized = ref.strip()
    direct = Path(normalized)
    if direct.is_absolute() and direct.exists():
        return direct if direct.is_file() else direct / "task.yaml"
    direct_repo = (repo_root / normalized).resolve()
    if direct_repo.exists():
        return direct_repo if direct_repo.is_file() else direct_repo / "task.yaml"
    for candidate in _logical_candidates(normalized, "task", "task", "task.yaml", repo_root):
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


def _resolve_bundle_ref(ref: str, repo_root: Path) -> Optional[Path]:
    normalized = ref.strip()
    direct = Path(normalized)
    if direct.is_absolute() and direct.exists():
        return direct if direct.is_file() else direct / "bundle.yaml"
    direct_repo = (repo_root / normalized).resolve()
    if direct_repo.exists():
        return direct_repo if direct_repo.is_file() else direct_repo / "bundle.yaml"
    for candidate in _logical_candidates(normalized, "bundle", "bundle", "bundle.yaml", repo_root):
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


class Validator:
    def __init__(
        self,
        repo_root: Path,
        policy: str,
        artifact_hashes: Mapping[str, str],
        extra_artifacts: List[str],
        ci_mode: bool,
    ):
        self.repo_root = repo_root
        self.policy = policy
        self.artifact_hashes = artifact_hashes
        self.extra_artifacts = extra_artifacts
        self.ci_mode = ci_mode
        self.errors: List[Dict[str, str]] = []
        self.warnings: List[Dict[str, str]] = []
        self.artifacts: List[Dict[str, Any]] = []

    def error(self, code: str, message: str) -> None:
        self.errors.append({"code": code, "message": message})

    def warn(self, code: str, message: str) -> None:
        self.warnings.append({"code": code, "message": message})

    def _require_key(self, obj: Mapping[str, Any], key: str, label: str) -> bool:
        if key not in obj:
            self.error("missing_key", f"{label} is missing key: {key}")
            return False
        return True

    def _check_gate(self, gate: Any, name: str) -> None:
        if not isinstance(gate, dict):
            self.error("invalid_type", f"{name} must be an object")
            return
        for key, typ in (("gate", str), ("passed", bool), ("reason", str)):
            if self._require_key(gate, key, name) and not isinstance(gate.get(key), typ):
                self.error("invalid_type", f"{name}.{key} must be {typ.__name__}")

    def _validate_deep_schema(self, data: Dict[str, Any]) -> None:
        task = data.get("task_evidence")
        exe = data.get("execution_evidence")
        summary = data.get("execution_summary")
        preflight = data.get("preflight_summary")
        close = data.get("close_summary")
        state = data.get("run_state")

        if not isinstance(task, dict):
            self.error("invalid_type", "task_evidence must be an object")
        if not isinstance(exe, dict):
            self.error("invalid_type", "execution_evidence must be an object")
        if not isinstance(summary, dict):
            self.error("invalid_type", "execution_summary must be an object")
        if not isinstance(preflight, dict):
            self.error("invalid_type", "preflight_summary must be an object")
        if not isinstance(close, dict):
            self.error("invalid_type", "close_summary must be an object")
        if not isinstance(state, dict):
            self.error("invalid_type", "run_state must be an object")

        if "evidence_file" in data and not isinstance(data.get("evidence_file"), str):
            self.error("invalid_type", "evidence_file must be a string when present")

        if isinstance(task, dict):
            for key in ("task_ref", "bundle_ref"):
                if self._require_key(task, key, "task_evidence") and not isinstance(task.get(key), str):
                    self.error("invalid_type", f"task_evidence.{key} must be string")
            for key in ("task_resolved", "task_id", "task_type", "bundle_resolved", "bundle_id", "bundle_version"):
                if self._require_key(task, key, "task_evidence"):
                    v = task.get(key)
                    if v is not None and not isinstance(v, str):
                        self.error("invalid_type", f"task_evidence.{key} must be string or null")

        if isinstance(exe, dict):
            for key, typ in (("success", bool), ("action", str), ("operator", str), ("detail", str)):
                if self._require_key(exe, key, "execution_evidence") and not isinstance(exe.get(key), typ):
                    self.error("invalid_type", f"execution_evidence.{key} must be {typ.__name__}")
            if self._require_key(exe, "outputs", "execution_evidence") and not isinstance(exe.get("outputs"), dict):
                self.error("invalid_type", "execution_evidence.outputs must be object")

        if isinstance(summary, dict) and isinstance(exe, dict):
            for key in ("success", "action", "operator", "detail", "outputs"):
                if self._require_key(summary, key, "execution_summary") and summary.get(key) != exe.get(key):
                    self.error("inconsistent_value", f"execution_summary.{key} must equal execution_evidence.{key}")

        if isinstance(preflight, dict):
            if self._require_key(preflight, "passed", "preflight_summary") and not isinstance(preflight.get("passed"), bool):
                self.error("invalid_type", "preflight_summary.passed must be bool")
            if self._require_key(preflight, "gate_a", "preflight_summary"):
                self._check_gate(preflight.get("gate_a"), "preflight_summary.gate_a")
            if self._require_key(preflight, "gate_b", "preflight_summary"):
                self._check_gate(preflight.get("gate_b"), "preflight_summary.gate_b")

        if isinstance(close, dict):
            if self._require_key(close, "run_id", "close_summary") and not isinstance(close.get("run_id"), str):
                self.error("invalid_type", "close_summary.run_id must be string")
            if self._require_key(close, "status", "close_summary") and not isinstance(close.get("status"), str):
                self.error("invalid_type", "close_summary.status must be string")
            if self._require_key(close, "dedup_key", "close_summary") and not isinstance(close.get("dedup_key"), str):
                self.error("invalid_type", "close_summary.dedup_key must be string")
            if self._require_key(close, "retry_counter", "close_summary") and not _is_non_negative_int(close.get("retry_counter")):
                self.error("invalid_type", "close_summary.retry_counter must be non-negative integer")

        if isinstance(state, dict):
            if self._require_key(state, "run_id", "run_state") and not isinstance(state.get("run_id"), str):
                self.error("invalid_type", "run_state.run_id must be string")
            if self._require_key(state, "status", "run_state") and not isinstance(state.get("status"), str):
                self.error("invalid_type", "run_state.status must be string")
            if self._require_key(state, "dedup_key", "run_state") and not isinstance(state.get("dedup_key"), str):
                self.error("invalid_type", "run_state.dedup_key must be string")
            if self._require_key(state, "retry_counter", "run_state") and not _is_non_negative_int(state.get("retry_counter")):
                self.error("invalid_type", "run_state.retry_counter must be non-negative integer")
            for tkey in ("started_at", "ended_at"):
                if self._require_key(state, tkey, "run_state"):
                    tval = state.get(tkey)
                    if tval is not None and not isinstance(tval, str):
                        self.error("invalid_type", f"run_state.{tkey} must be string or null")
            if self._require_key(state, "error", "run_state"):
                err = state.get("error")
                if err is not None and not isinstance(err, str):
                    self.error("invalid_type", "run_state.error must be string or null")

    def _validate_cross_field(self, data: Dict[str, Any]) -> None:
        close = data.get("close_summary") if isinstance(data.get("close_summary"), dict) else {}
        state = data.get("run_state") if isinstance(data.get("run_state"), dict) else {}
        exe = data.get("execution_evidence") if isinstance(data.get("execution_evidence"), dict) else {}
        preflight = data.get("preflight_summary") if isinstance(data.get("preflight_summary"), dict) else {}

        for key in ("run_id", "dedup_key", "retry_counter"):
            if key in close and key in state and close[key] != state[key]:
                self.error("inconsistent_value", f"close_summary.{key} must equal run_state.{key}")

        status = close.get("status")
        success = exe.get("success")
        if status == "closed" and success is not True:
            self.error("inconsistent_value", "close_summary.status=closed requires execution_evidence.success=true")
        if status in {"blocked", "failed"} and success is not False:
            self.error("inconsistent_value", "close_summary.status=blocked/failed requires execution_evidence.success=false")

        if isinstance(preflight.get("passed"), bool):
            gate_a = preflight.get("gate_a", {}) if isinstance(preflight.get("gate_a"), dict) else {}
            gate_b = preflight.get("gate_b", {}) if isinstance(preflight.get("gate_b"), dict) else {}
            if preflight["passed"] and not (gate_a.get("passed") is True and gate_b.get("passed") is True):
                self.error("inconsistent_value", "preflight_summary.passed=true requires both gate_a/gate_b passed=true")

    def _validate_runtime_contract(self, data: Dict[str, Any]) -> None:
        task = data.get("task_evidence") if isinstance(data.get("task_evidence"), dict) else {}
        exe = data.get("execution_evidence") if isinstance(data.get("execution_evidence"), dict) else {}

        operator = exe.get("operator")
        if isinstance(operator, str) and operator not in CANONICAL_OPERATORS:
            self.error("contract_violation", f"execution_evidence.operator is not canonical: {operator}")

        task_ref = task.get("task_ref")
        if isinstance(task_ref, str) and task_ref and not (task_ref.startswith("task://") or Path(task_ref).exists()):
            self.warn("noncanonical_ref", "task_evidence.task_ref is not a canonical task:// ref or existing path")

        bundle_ref = task.get("bundle_ref")
        if isinstance(bundle_ref, str) and bundle_ref and not (bundle_ref.startswith("bundle://") or Path(bundle_ref).exists()):
            self.warn("noncanonical_ref", "task_evidence.bundle_ref is not a canonical bundle:// ref or existing path")

        task_resolved = task.get("task_resolved")
        if isinstance(task_resolved, str) and task_resolved and not Path(task_resolved).exists():
            if self.ci_mode:
                self.warn(
                    "ci_missing_resolved_path",
                    f"task_evidence.task_resolved does not exist in CI environment: {task_resolved}",
                )
            else:
                self.error("contract_violation", f"task_evidence.task_resolved does not exist: {task_resolved}")

        bundle_resolved = task.get("bundle_resolved")
        if isinstance(bundle_resolved, str) and bundle_resolved and not Path(bundle_resolved).exists():
            if self.ci_mode:
                self.warn(
                    "ci_missing_resolved_path",
                    f"task_evidence.bundle_resolved does not exist in CI environment: {bundle_resolved}",
                )
            else:
                self.error("contract_violation", f"task_evidence.bundle_resolved does not exist: {bundle_resolved}")

        if isinstance(task_ref, str):
            resolved_task = _resolve_task_ref(task_ref, self.repo_root)
            if resolved_task is not None and resolved_task.exists():
                try:
                    task_doc = load_task_yaml(resolved_task)
                    if task.get("task_id") is not None and task_doc.get("task_id") != task.get("task_id"):
                        self.error("contract_violation", "task_evidence.task_id does not match resolved task.yaml")
                    if isinstance(bundle_ref, str) and task_doc.get("bundle") != bundle_ref:
                        self.error("contract_violation", "task_evidence.bundle_ref does not match task.yaml bundle")
                    if isinstance(operator, str) and task_doc.get("operator") != operator:
                        self.error("contract_violation", "execution_evidence.operator does not match task.yaml operator")
                except Exception as exc:
                    self.error("contract_violation", f"failed to load resolved task.yaml: {exc}")

        if isinstance(bundle_ref, str):
            resolved_bundle = _resolve_bundle_ref(bundle_ref, self.repo_root)
            if resolved_bundle is not None and resolved_bundle.exists():
                try:
                    bundle_doc = load_bundle_yaml(resolved_bundle)
                    if task.get("bundle_id") is not None and bundle_doc.get("bundle_id") != task.get("bundle_id"):
                        self.error("contract_violation", "task_evidence.bundle_id does not match resolved bundle.yaml")
                    if isinstance(operator, str) and bundle_doc.get("executor") != operator:
                        self.error("contract_violation", "execution_evidence.operator does not match bundle.yaml executor")
                except Exception as exc:
                    self.error("contract_violation", f"failed to load resolved bundle.yaml: {exc}")

    def _validate_artifact(self, artifact_path: str, expected_hash: Optional[str], source: str) -> None:
        resolved = _resolve_any_path(artifact_path, self.repo_root, self.repo_root)
        artifact = {
            "source": source,
            "path": artifact_path,
            "resolved_path": str(resolved),
            "exists": resolved.exists(),
        }

        if not resolved.exists():
            if self.ci_mode:
                self.warn("ci_artifact_missing", f"artifact does not exist in CI environment: {artifact_path}")
            else:
                self.error("artifact_missing", f"artifact does not exist: {artifact_path}")
            self.artifacts.append(artifact)
            return

        computed = _sha256_file(resolved)
        artifact["sha256_computed"] = computed

        if expected_hash is not None:
            if not re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash):
                self.error("invalid_hash", f"expected hash is not valid sha256 hex: {expected_hash}")
            elif computed.lower() != expected_hash.lower():
                self.error("hash_mismatch", f"artifact hash mismatch for {artifact_path}")
            artifact["sha256_expected"] = expected_hash
        else:
            self.warn("hash_missing", f"no expected hash provided for artifact: {artifact_path}")

        self.artifacts.append(artifact)

    def _validate_artifacts(self, data: Dict[str, Any], evidence_path: Path) -> None:
        exe = data.get("execution_evidence") if isinstance(data.get("execution_evidence"), dict) else {}
        outputs = exe.get("outputs") if isinstance(exe.get("outputs"), dict) else {}

        seen = set()
        report_path = outputs.get("validation_report")
        if isinstance(report_path, str):
            expected_hash = None
            if isinstance(outputs.get("validation_report_sha256"), str):
                expected_hash = outputs.get("validation_report_sha256")
            elif report_path in self.artifact_hashes:
                expected_hash = self.artifact_hashes[report_path]
            elif str(_resolve_any_path(report_path, self.repo_root, evidence_path.parent)) in self.artifact_hashes:
                expected_hash = self.artifact_hashes[str(_resolve_any_path(report_path, self.repo_root, evidence_path.parent))]
            self._validate_artifact(report_path, expected_hash, source="execution_evidence.outputs.validation_report")
            seen.add(report_path)

        for artifact_path in self.extra_artifacts:
            if artifact_path in seen:
                continue
            expected_hash = self.artifact_hashes.get(artifact_path)
            self._validate_artifact(artifact_path, expected_hash, source="cli")

    def validate(self, data: Dict[str, Any], evidence_path: Path, schema_name: str, schema_version: str) -> Dict[str, Any]:
        if schema_name != SCHEMA_NAME:
            self.error("schema_name_mismatch", f"unsupported schema_name: {schema_name}")
        if schema_version != SCHEMA_VERSION:
            self.error("schema_version_mismatch", f"unsupported schema_version: {schema_version}")

        for key in TOP_LEVEL_KEYS:
            if key not in data:
                self.error("missing_key", f"evidence is missing top-level key: {key}")
        if "evidence_file" not in data:
            self.warn("compat_missing_evidence_file", "evidence_file is missing; accepted for backward compatibility")

        if self.policy == "strict":
            self._validate_deep_schema(data)
            self._validate_cross_field(data)
            self._validate_runtime_contract(data)
            self._validate_artifacts(data, evidence_path)
        else:
            if isinstance(data.get("execution_evidence"), dict):
                self._validate_artifacts(data, evidence_path)

        evidence_file = data.get("evidence_file")
        if isinstance(evidence_file, str):
            resolved_reported = _resolve_any_path(evidence_file, self.repo_root, evidence_path.parent)
            if resolved_reported != evidence_path.resolve():
                self.warn(
                    "path_mismatch",
                    "evidence_file does not resolve to input evidence path; accepted for compatibility",
                )

        return {
            "valid": len(self.errors) == 0,
            "errors": self.errors,
            "warnings": self.warnings,
            "schema_name": schema_name,
            "schema_version": schema_version,
            "validated_at": _utc_now(),
            "evidence_file": str(evidence_path.resolve()),
            "artifacts": self.artifacts,
            "policy": self.policy,
        }


def _parse_artifact_hashes(raw_items: List[str]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for item in raw_items:
        if "=" not in item:
            raise ValueError(f"invalid --artifact-hash value: {item}; expected <path>=<sha256>")
        path, digest = item.split("=", 1)
        path = path.strip()
        digest = digest.strip()
        if not path or not digest:
            raise ValueError(f"invalid --artifact-hash value: {item}; expected non-empty <path>=<sha256>")
        out[path] = digest
    return out


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate runtime execution evidence and related artifacts")
    parser.add_argument("--evidence-file", required=True, help="Path to evidence JSON")
    parser.add_argument("--schema-name", default=SCHEMA_NAME, help="Schema name (default: execution-evidence)")
    parser.add_argument("--schema-version", default=SCHEMA_VERSION, help="Schema version (default: v1)")
    parser.add_argument("--policy", choices=("lenient", "strict"), default="lenient")
    parser.add_argument(
        "--ci-mode",
        action="store_true",
        default=bool(os.getenv("CI")),
        help="Relax artifact/resolved-path existence checks for CI portability",
    )
    parser.add_argument(
        "--artifact-file",
        action="append",
        default=[],
        help="Additional artifact path to validate existence/hash (repeatable)",
    )
    parser.add_argument(
        "--artifact-hash",
        action="append",
        default=[],
        help="Expected artifact hash in format <path>=<sha256> (repeatable)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = REPO_ROOT

    evidence_path = _resolve_any_path(args.evidence_file, repo_root, Path.cwd())
    if not evidence_path.exists() or not evidence_path.is_file():
        print(
            json.dumps(
                {
                    "valid": False,
                    "errors": [{"code": "evidence_not_found", "message": f"evidence file not found: {args.evidence_file}"}],
                    "warnings": [],
                    "schema_name": args.schema_name,
                    "schema_version": args.schema_version,
                    "validated_at": _utc_now(),
                },
                ensure_ascii=True,
                indent=2,
            )
        )
        return 1

    try:
        data = json.loads(evidence_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(
            json.dumps(
                {
                    "valid": False,
                    "errors": [{"code": "json_parse_error", "message": str(exc)}],
                    "warnings": [],
                    "schema_name": args.schema_name,
                    "schema_version": args.schema_version,
                    "validated_at": _utc_now(),
                    "evidence_file": str(evidence_path.resolve()),
                },
                ensure_ascii=True,
                indent=2,
            )
        )
        return 1

    if not isinstance(data, dict):
        print(
            json.dumps(
                {
                    "valid": False,
                    "errors": [{"code": "invalid_type", "message": "evidence root must be an object"}],
                    "warnings": [],
                    "schema_name": args.schema_name,
                    "schema_version": args.schema_version,
                    "validated_at": _utc_now(),
                    "evidence_file": str(evidence_path.resolve()),
                },
                ensure_ascii=True,
                indent=2,
            )
        )
        return 1

    try:
        artifact_hashes = _parse_artifact_hashes(args.artifact_hash)
    except ValueError as exc:
        print(
            json.dumps(
                {
                    "valid": False,
                    "errors": [{"code": "invalid_argument", "message": str(exc)}],
                    "warnings": [],
                    "schema_name": args.schema_name,
                    "schema_version": args.schema_version,
                    "validated_at": _utc_now(),
                    "evidence_file": str(evidence_path.resolve()),
                },
                ensure_ascii=True,
                indent=2,
            )
        )
        return 1

    validator = Validator(
        repo_root=repo_root,
        policy=args.policy,
        artifact_hashes=artifact_hashes,
        extra_artifacts=args.artifact_file,
        ci_mode=args.ci_mode,
    )
    result = validator.validate(
        data=data,
        evidence_path=evidence_path,
        schema_name=args.schema_name,
        schema_version=args.schema_version,
    )

    print(json.dumps(result, ensure_ascii=True, indent=2))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
