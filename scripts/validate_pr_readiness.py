from __future__ import annotations

import argparse
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_SECTIONS = (
    "Purpose",
    "Scope",
    "Changed files",
    "Validation",
    "Evidence",
    "Risk",
    "Non-goals",
)
REQUIRED_EVIDENCE_LABELS = (
    "run bundle",
    "PR gate judgment",
    "implementation report",
    "backend evidence",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def resolve_path(root: Path, raw: str) -> Path:
    candidate = Path(raw)
    if candidate.is_absolute():
        return candidate
    return (root / candidate).resolve()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def extract_sections(body: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for line in body.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(line)
    return {key: "\n".join(value).strip() for key, value in sections.items()}


def parse_bullet_paths(section: str) -> list[str]:
    paths: list[str] = []
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        match = re.search(r"`([^`]+)`", stripped)
        if match:
            paths.append(match.group(1))
    return paths


def parse_evidence_map(section: str) -> dict[str, str]:
    evidence: dict[str, str] = {}
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        match = re.match(r"- ([^:]+): `([^`]+)`", stripped)
        if match:
            evidence[match.group(1)] = match.group(2)
    return evidence


def detect_gate_verdict(sections: dict[str, str], pr_metadata: dict[str, Any] | None) -> str | None:
    if pr_metadata is not None:
        value = pr_metadata.get("gate_verdict")
        if value in {"pass", "hold", "fail"}:
            return str(value)
    validation = sections.get("Validation", "")
    match = re.search(r"gate verdict:\s*`(pass|hold|fail)`", validation)
    if match:
        return match.group(1)
    return None


def changed_files_from_git(root: Path, base_sha: str, head_sha: str) -> list[str]:
    output = subprocess.check_output(
        ["git", "diff", "--name-only", f"{base_sha}...{head_sha}"],
        cwd=root,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return [line.strip().replace("\\", "/") for line in output.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description="PR body / diff / evidence の整合性を検証します。")
    parser.add_argument("--root", default=".")
    parser.add_argument("--pr-body-file", required=True)
    parser.add_argument("--pr-metadata", default=None)
    parser.add_argument("--changed-files-file", default=None)
    parser.add_argument("--base-sha", default=None)
    parser.add_argument("--head-sha", default=None)
    parser.add_argument("--head-ref", default=None)
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    body_path = resolve_path(root, args.pr_body_file)
    body = body_path.read_text(encoding="utf-8")
    sections = extract_sections(body)
    pr_metadata = load_json(resolve_path(root, args.pr_metadata)) if args.pr_metadata else None

    errors: list[str] = []
    warnings: list[str] = []

    for section in REQUIRED_SECTIONS:
        if section not in sections or not sections[section].strip():
            errors.append(f"section '{section}' is missing or empty.")

    if "PR-ready" not in body:
        errors.append("literal token 'PR-ready' is missing.")

    if args.head_ref and not args.head_ref.startswith("codex/"):
        errors.append("head branch must start with 'codex/'.")

    declared_changed = parse_bullet_paths(sections.get("Changed files", ""))
    actual_changed: list[str] = []
    if args.changed_files_file:
        changed_file_path = resolve_path(root, args.changed_files_file)
        actual_changed = [line.strip().replace("\\", "/") for line in changed_file_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    elif args.base_sha and args.head_sha:
        actual_changed = changed_files_from_git(root, args.base_sha, args.head_sha)

    if actual_changed:
        normalized_declared = {path.strip("`").replace("\\", "/") for path in declared_changed}
        normalized_actual = {path.replace("\\", "/") for path in actual_changed}
        missing = sorted(normalized_actual - normalized_declared)
        extra = sorted(normalized_declared - normalized_actual)
        if missing:
            errors.append("Changed files section is missing actual diff paths: " + ", ".join(missing))
        if extra:
            errors.append("Changed files section lists paths outside actual diff: " + ", ".join(extra))
    elif not declared_changed:
        errors.append("Changed files section does not list any file path.")

    evidence_map = parse_evidence_map(sections.get("Evidence", ""))
    for label in REQUIRED_EVIDENCE_LABELS:
        path = evidence_map.get(label)
        if not path:
            errors.append(f"Evidence section is missing '{label}'.")
            continue
        if not resolve_path(root, path).exists():
            errors.append(f"Evidence path for '{label}' does not exist: {path}")

    gate_verdict = detect_gate_verdict(sections, pr_metadata)
    if gate_verdict is None:
        errors.append("gate verdict could not be resolved from PR metadata or body.")

    verdict = "fail"
    if not errors:
        if gate_verdict == "fail":
            errors.append("gate verdict is fail, so PR readiness cannot pass.")
        elif gate_verdict == "hold":
            verdict = "hold"
            warnings.append("manual review is required because gate verdict is hold.")
        else:
            verdict = "pass"

    if errors:
        verdict = "fail"

    result = {
        "pr_body_path": str(body_path.resolve().relative_to(root)).replace("\\", "/"),
        "validator_verdict": verdict,
        "gate_verdict": gate_verdict,
        "errors": errors,
        "warnings": warnings,
        "validated_at": utc_now(),
    }

    output_path = resolve_path(root, args.output) if args.output else root / "reports" / "pr_readiness" / f"{body_path.stem}_validation.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(output_path)
    return 1 if verdict == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
