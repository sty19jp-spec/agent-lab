#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
from typing import Any, Dict, List, Optional, Set, Tuple


REPO_ROOT = Path(__file__).resolve().parents[1]
REGISTRY_ROOT = Path(__file__).resolve().parent
DATA_DIR = REGISTRY_ROOT / "data"
EVIDENCE_DIR = DATA_DIR / "evidence"
INDEX_PATH = DATA_DIR / "index.json"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _resolve_path(path_str: str, base_dir: Path) -> Path:
    raw = Path(path_str)
    if raw.is_absolute():
        return raw.resolve()
    base_candidate = (base_dir / raw).resolve()
    if base_candidate.exists():
        return base_candidate
    return (REPO_ROOT / raw).resolve()


def _normalize(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned.lower() if cleaned else None


def _relative_or_abs(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path.resolve())


def _base_db() -> Dict[str, Any]:
    now = _utc_now()
    return {
        "schema_name": "execution-evidence-registry",
        "schema_version": "v1",
        "created_at": now,
        "updated_at": now,
        "entries": [],
        "index": {
            "task": {},
            "bundle": {},
            "operator": {},
            "executor_id": {},
            "executor_type": {},
            "repository_commit": {},
            "repository_branch": {},
            "trigger_type": {},
            "execution_timestamp": {},
        },
    }


def _load_db() -> Dict[str, Any]:
    if not INDEX_PATH.exists():
        return _base_db()
    data = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("registry index must be a JSON object")
    data.setdefault("entries", [])
    index = data.setdefault("index", {})
    if not isinstance(index, dict):
        index = {}
        data["index"] = index
    for index_name in (
        "task",
        "bundle",
        "operator",
        "executor_id",
        "executor_type",
        "repository_commit",
        "repository_branch",
        "trigger_type",
        "execution_timestamp",
    ):
        if not isinstance(index.get(index_name), dict):
            index[index_name] = {}
    return data


def _write_db(db: Dict[str, Any]) -> None:
    db["updated_at"] = _utc_now()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    INDEX_PATH.write_text(json.dumps(db, ensure_ascii=True, indent=2), encoding="utf-8")


def _sanitize_token(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]", "_", value)


def _make_entry_id(run_id: Optional[str], source_sha256: str) -> str:
    key = f"{run_id or 'run-unknown'}:{source_sha256}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]


def _persist_evidence_copy(evidence: Dict[str, Any], entry_id: str) -> Tuple[Path, str]:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    run_state = evidence.get("run_state") if isinstance(evidence.get("run_state"), dict) else {}
    run_id = run_state.get("run_id") if isinstance(run_state.get("run_id"), str) else "run-unknown"
    safe_run_id = _sanitize_token(run_id)
    filename = f"{safe_run_id}--{entry_id}.json"
    target = EVIDENCE_DIR / filename
    target.write_text(json.dumps(evidence, ensure_ascii=True, indent=2), encoding="utf-8")
    return target.resolve(), _sha256_file(target)


def _entry_metadata(
    source_path: Path,
    source_sha256: str,
    archived_path: Path,
    archived_sha256: str,
    evidence: Dict[str, Any],
) -> Dict[str, Any]:
    task = evidence.get("task_evidence") if isinstance(evidence.get("task_evidence"), dict) else {}
    exe = evidence.get("execution_evidence") if isinstance(evidence.get("execution_evidence"), dict) else {}
    run_state = evidence.get("run_state") if isinstance(evidence.get("run_state"), dict) else {}
    provenance = evidence.get("provenance") if isinstance(evidence.get("provenance"), dict) else {}
    execution_identity = (
        provenance.get("execution_identity") if isinstance(provenance.get("execution_identity"), dict) else {}
    )
    repository_state = (
        provenance.get("repository_state") if isinstance(provenance.get("repository_state"), dict) else {}
    )
    execution_context = (
        provenance.get("execution_context") if isinstance(provenance.get("execution_context"), dict) else {}
    )

    run_id = run_state.get("run_id") if isinstance(run_state.get("run_id"), str) else None
    entry_id = _make_entry_id(run_id, source_sha256)

    return {
        "entry_id": entry_id,
        "registered_at": _utc_now(),
        "run_id": run_id,
        "status": run_state.get("status"),
        "started_at": run_state.get("started_at"),
        "ended_at": run_state.get("ended_at"),
        "task_ref": task.get("task_ref"),
        "task_id": task.get("task_id"),
        "bundle_ref": task.get("bundle_ref"),
        "bundle_id": task.get("bundle_id"),
        "operator": execution_identity.get("operator") or exe.get("operator"),
        "executor_id": execution_identity.get("executor_id"),
        "executor_type": execution_identity.get("executor_type"),
        "repository_commit": repository_state.get("repository_commit"),
        "repository_branch": repository_state.get("repository_branch"),
        "execution_timestamp": execution_context.get("execution_timestamp"),
        "trigger_type": execution_context.get("trigger_type"),
        "action": exe.get("action"),
        "success": exe.get("success"),
        "detail": exe.get("detail"),
        "source_evidence_path": str(source_path.resolve()),
        "source_evidence_path_repo": _relative_or_abs(source_path),
        "source_evidence_sha256": source_sha256,
        "archived_evidence_path": str(archived_path.resolve()),
        "archived_evidence_path_repo": _relative_or_abs(archived_path),
        "archived_evidence_sha256": archived_sha256,
    }


def _index_values(entry: Dict[str, Any], index_name: str) -> Set[str]:
    if index_name == "task":
        return {
            v
            for v in (
                _normalize(entry.get("task_ref")),
                _normalize(entry.get("task_id")),
            )
            if v
        }
    if index_name == "bundle":
        return {
            v
            for v in (
                _normalize(entry.get("bundle_ref")),
                _normalize(entry.get("bundle_id")),
            )
            if v
        }
    if index_name == "operator":
        v = _normalize(entry.get("operator"))
        return {v} if v else set()
    if index_name == "executor_id":
        v = _normalize(entry.get("executor_id"))
        return {v} if v else set()
    if index_name == "executor_type":
        v = _normalize(entry.get("executor_type"))
        return {v} if v else set()
    if index_name == "repository_commit":
        v = _normalize(entry.get("repository_commit"))
        return {v} if v else set()
    if index_name == "repository_branch":
        v = _normalize(entry.get("repository_branch"))
        return {v} if v else set()
    if index_name == "trigger_type":
        v = _normalize(entry.get("trigger_type"))
        return {v} if v else set()
    if index_name == "execution_timestamp":
        v = _normalize(entry.get("execution_timestamp"))
        return {v} if v else set()
    return set()


def _rebuild_index(db: Dict[str, Any]) -> None:
    index_names = (
        "task",
        "bundle",
        "operator",
        "executor_id",
        "executor_type",
        "repository_commit",
        "repository_branch",
        "trigger_type",
        "execution_timestamp",
    )
    index: Dict[str, Dict[str, List[str]]] = {name: {} for name in index_names}
    for entry in db.get("entries", []):
        if not isinstance(entry, dict):
            continue
        entry_id = entry.get("entry_id")
        if not isinstance(entry_id, str) or not entry_id:
            continue
        for index_name in index_names:
            for value in _index_values(entry, index_name):
                index[index_name].setdefault(value, []).append(entry_id)
    db["index"] = index


def _find_existing_entry(entries: List[Dict[str, Any]], metadata: Dict[str, Any]) -> Optional[int]:
    run_id = metadata.get("run_id")
    source_sha256 = metadata.get("source_evidence_sha256")
    for i, entry in enumerate(entries):
        if not isinstance(entry, dict):
            continue
        if run_id and entry.get("run_id") == run_id:
            return i
        if source_sha256 and entry.get("source_evidence_sha256") == source_sha256:
            return i
    return None


def _load_evidence_file(evidence_file: str) -> Tuple[Path, Dict[str, Any], str]:
    source_path = _resolve_path(evidence_file, Path.cwd())
    if not source_path.exists() or not source_path.is_file():
        raise FileNotFoundError(f"evidence file not found: {evidence_file}")
    data = json.loads(source_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("evidence root must be an object")
    return source_path, data, _sha256_file(source_path)


def _print_entries(entries: List[Dict[str, Any]]) -> None:
    if not entries:
        print("No entries found.")
        return
    for idx, entry in enumerate(entries, start=1):
        print(
            f"{idx}. run_id={entry.get('run_id') or '-'} "
            f"task={entry.get('task_ref') or entry.get('task_id') or '-'} "
            f"bundle={entry.get('bundle_ref') or entry.get('bundle_id') or '-'} "
            f"operator={entry.get('operator') or '-'} "
            f"success={entry.get('success')} "
            f"registered_at={entry.get('registered_at')} "
            f"evidence={entry.get('archived_evidence_path_repo')}"
        )


def cmd_register(args: argparse.Namespace) -> int:
    source_path, evidence, source_sha256 = _load_evidence_file(args.evidence)
    run_state = evidence.get("run_state") if isinstance(evidence.get("run_state"), dict) else {}
    run_id = run_state.get("run_id") if isinstance(run_state.get("run_id"), str) else None
    entry_id = _make_entry_id(run_id, source_sha256)

    archived_path, archived_sha256 = _persist_evidence_copy(evidence, entry_id)
    metadata = _entry_metadata(source_path, source_sha256, archived_path, archived_sha256, evidence)

    db = _load_db()
    entries = db.get("entries", [])
    if not isinstance(entries, list):
        raise ValueError("registry entries must be a list")

    existing_idx = _find_existing_entry(entries, metadata)
    if existing_idx is None:
        entries.append(metadata)
        operation = "registered"
    else:
        existing = entries[existing_idx]
        if isinstance(existing, dict):
            metadata["registered_at"] = existing.get("registered_at", metadata["registered_at"])
        entries[existing_idx] = metadata
        operation = "updated"

    db["entries"] = entries
    _rebuild_index(db)
    _write_db(db)

    print(
        json.dumps(
            {
                "status": "ok",
                "operation": operation,
                "entry_id": metadata["entry_id"],
                "run_id": metadata.get("run_id"),
                "source_evidence_path": metadata["source_evidence_path_repo"],
                "archived_evidence_path": metadata["archived_evidence_path_repo"],
                "index_path": _relative_or_abs(INDEX_PATH),
            },
            ensure_ascii=True,
            indent=2,
        )
    )
    return 0


def _sorted_entries(entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    def sort_key(entry: Dict[str, Any]) -> Tuple[str, str]:
        ended = entry.get("ended_at")
        registered = entry.get("registered_at")
        return (str(ended or ""), str(registered or ""))

    return sorted(entries, key=sort_key, reverse=True)


def cmd_list(_: argparse.Namespace) -> int:
    db = _load_db()
    entries = db.get("entries", [])
    if not isinstance(entries, list):
        raise ValueError("registry entries must be a list")

    ordered = _sorted_entries([e for e in entries if isinstance(e, dict)])
    print(f"Execution Evidence Registry: {len(ordered)} entr{'y' if len(ordered) == 1 else 'ies'}")
    _print_entries(ordered)
    return 0


def _candidate_ids_from_index(
    db: Dict[str, Any],
    task: Optional[str],
    bundle: Optional[str],
    operator: Optional[str],
    executor_id: Optional[str],
    executor_type: Optional[str],
    repository_commit: Optional[str],
    repository_branch: Optional[str],
    trigger_type: Optional[str],
    execution_timestamp: Optional[str],
) -> Optional[Set[str]]:
    index = db.get("index", {}) if isinstance(db.get("index"), dict) else {}

    criteria = [
        ("task", task),
        ("bundle", bundle),
        ("operator", operator),
        ("executor_id", executor_id),
        ("executor_type", executor_type),
        ("repository_commit", repository_commit),
        ("repository_branch", repository_branch),
        ("trigger_type", trigger_type),
        ("execution_timestamp", execution_timestamp),
    ]

    candidates: Optional[Set[str]] = None
    for index_name, value in criteria:
        normalized = _normalize(value)
        if not normalized:
            continue
        # Backward compatibility: older registries may not have this index key.
        idx_for_type_raw = index.get(index_name)
        if not isinstance(idx_for_type_raw, dict):
            continue
        idx_for_type = idx_for_type_raw
        raw_ids = idx_for_type.get(normalized, [])
        ids = {entry_id for entry_id in raw_ids if isinstance(entry_id, str)}
        if candidates is None:
            candidates = ids
        else:
            candidates &= ids
    return candidates


def _parse_ts(value: str, field: str) -> datetime:
    raw = value.strip()
    if not raw:
        raise ValueError(f"{field} must not be empty")
    normalized = raw[:-1] + "+00:00" if raw.endswith("Z") else raw
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError(f"invalid {field}: {value}") from exc
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _entry_timestamp(entry: Dict[str, Any]) -> Optional[datetime]:
    for key in ("execution_timestamp", "ended_at", "started_at", "registered_at"):
        value = entry.get(key)
        if isinstance(value, str) and value.strip():
            try:
                return _parse_ts(value, key)
            except ValueError:
                continue
    return None


def cmd_query(args: argparse.Namespace) -> int:
    if not any(
        [
            args.task,
            args.bundle,
            args.operator,
            args.executor_id,
            args.executor_type,
            args.repository_commit,
            args.repository_branch,
            args.trigger_type,
            args.execution_timestamp,
            args.since,
            args.until,
        ]
    ):
        raise ValueError(
            "at least one query filter is required (--task, --bundle, --operator, --executor-id, "
            "--executor-type, --repository-commit, --repository-branch, --trigger-type, "
            "--execution-timestamp, --since, --until)"
        )

    db = _load_db()
    entries = db.get("entries", [])
    if not isinstance(entries, list):
        raise ValueError("registry entries must be a list")

    entry_map = {
        entry.get("entry_id"): entry
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("entry_id"), str)
    }

    candidate_ids = _candidate_ids_from_index(
        db,
        args.task,
        args.bundle,
        args.operator,
        args.executor_id,
        args.executor_type,
        args.repository_commit,
        args.repository_branch,
        args.trigger_type,
        args.execution_timestamp,
    )
    if candidate_ids is None:
        candidate_entries = [e for e in entries if isinstance(e, dict)]
    else:
        candidate_entries = [entry_map[eid] for eid in candidate_ids if eid in entry_map]

    since_dt = _parse_ts(args.since, "since") if args.since else None
    until_dt = _parse_ts(args.until, "until") if args.until else None

    def matches(entry: Dict[str, Any]) -> bool:
        if args.task:
            t = _normalize(args.task)
            if t not in _index_values(entry, "task"):
                return False
        if args.bundle:
            b = _normalize(args.bundle)
            if b not in _index_values(entry, "bundle"):
                return False
        if args.operator:
            o = _normalize(args.operator)
            if o not in _index_values(entry, "operator"):
                return False
        if args.executor_id:
            v = _normalize(args.executor_id)
            if v not in _index_values(entry, "executor_id"):
                return False
        if args.executor_type:
            v = _normalize(args.executor_type)
            if v not in _index_values(entry, "executor_type"):
                return False
        if args.repository_commit:
            v = _normalize(args.repository_commit)
            if v not in _index_values(entry, "repository_commit"):
                return False
        if args.repository_branch:
            v = _normalize(args.repository_branch)
            if v not in _index_values(entry, "repository_branch"):
                return False
        if args.trigger_type:
            v = _normalize(args.trigger_type)
            if v not in _index_values(entry, "trigger_type"):
                return False
        if args.execution_timestamp:
            v = _normalize(args.execution_timestamp)
            if v not in _index_values(entry, "execution_timestamp"):
                return False
        if since_dt or until_dt:
            ts = _entry_timestamp(entry)
            if ts is None:
                return False
            if since_dt and ts < since_dt:
                return False
            if until_dt and ts > until_dt:
                return False
        return True

    results = _sorted_entries([entry for entry in candidate_entries if matches(entry)])
    print(f"Query Results: {len(results)}")
    _print_entries(results)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Execution Evidence Registry CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    register_parser = sub.add_parser("register", help="Register execution evidence JSON")
    register_parser.add_argument("--evidence", required=True, help="Path to execution evidence JSON")
    register_parser.set_defaults(func=cmd_register)

    list_parser = sub.add_parser("list", help="List execution history")
    list_parser.set_defaults(func=cmd_list)

    query_parser = sub.add_parser("query", help="Query evidence by metadata")
    query_parser.add_argument("--task", help="Task selector (task_ref or task_id)")
    query_parser.add_argument("--bundle", help="Bundle selector (bundle_ref or bundle_id)")
    query_parser.add_argument("--operator", help="Operator selector")
    query_parser.add_argument("--executor-id", help="Provenance executor_id selector")
    query_parser.add_argument("--executor-type", help="Provenance executor_type selector")
    query_parser.add_argument("--repository-commit", help="Provenance repository_commit selector")
    query_parser.add_argument("--repository-branch", help="Provenance repository_branch selector")
    query_parser.add_argument("--trigger-type", help="Provenance trigger_type selector")
    query_parser.add_argument("--execution-timestamp", help="Provenance execution_timestamp selector")
    query_parser.add_argument("--since", help="Include entries at/after timestamp (RFC3339)")
    query_parser.add_argument("--until", help="Include entries at/before timestamp (RFC3339)")
    query_parser.set_defaults(func=cmd_query)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
