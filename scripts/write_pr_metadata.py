from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write deterministic PR metadata from a run bundle and PR gate judgment."
    )
    parser.add_argument("--root", required=True)
    parser.add_argument("--run-bundle", required=True)
    parser.add_argument("--pr-gate", required=True)
    parser.add_argument("--output")
    parser.add_argument("--branch-name")
    parser.add_argument("--base-branch", default="main")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def relpath(root: Path, path_str: str | None) -> str | None:
    if not path_str:
        return None
    path = Path(path_str)
    if not path.is_absolute():
        path = root / path
    return str(path.resolve().relative_to(root.resolve())).replace("\\", "/")


def branch_name_for(task_id: str, branch_name: str | None) -> str:
    if branch_name:
        return branch_name
    slug = re.sub(r"[^A-Za-z0-9._/-]+", "-", task_id).strip("-")
    return f"codex/{slug}"


def extract_section_lines(lines: list[str], heading: str) -> list[str]:
    collected: list[str] = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            if in_section:
                break
            in_section = line.strip() == heading
            continue
        if in_section:
            collected.append(line.rstrip())
    return collected


def first_meaningful(lines: list[str]) -> str | None:
    for line in lines:
        stripped = line.strip()
        if stripped:
            return stripped.replace("`", "")
    return None


def parse_task_markdown(task_path: Path) -> dict[str, Any]:
    lines = task_path.read_text(encoding="utf-8").splitlines()
    task_name = first_meaningful(extract_section_lines(lines, "## task名"))
    purpose_lines = [line.strip() for line in extract_section_lines(lines, "## 実装目的") if line.strip()]
    changed_files = [
        line.strip()[2:]
        for line in extract_section_lines(lines, "## 変更対象")
        if line.strip().startswith("- ")
    ]
    boundary_lines = extract_section_lines(lines, "## 今回触る範囲 / 触らない範囲")
    non_goals: list[str] = []
    in_non_goals = False
    for raw in boundary_lines:
        stripped = raw.strip()
        if "触らない範囲" in stripped:
            in_non_goals = True
            continue
        if "触る範囲" in stripped and "触らない範囲" not in stripped:
            in_non_goals = False
            continue
        if in_non_goals and stripped.startswith("- "):
            non_goals.append(stripped[2:])

    return {
        "task_name": task_name,
        "purpose": " ".join(purpose_lines) if purpose_lines else None,
        "changed_files": changed_files,
        "non_goals": non_goals,
    }


def default_output_path(root: Path, run_id: str) -> Path:
    return root / "reports" / "pr_metadata" / f"{run_id}_pr_metadata.json"


def build_metadata(
    root: Path,
    run_bundle_path: Path,
    pr_gate_path: Path,
    branch_name_override: str | None = None,
    base_branch: str = "main",
    output_path: Path | None = None,
    pr_body_path_override: str | None = None,
) -> tuple[dict[str, Any], Path]:
    run_bundle = load_json(run_bundle_path)
    pr_gate = load_json(pr_gate_path)

    task_path = root / run_bundle["task_path"]
    task_info = parse_task_markdown(task_path)

    branch_name = branch_name_for(run_bundle["task_id"], branch_name_override)
    task_intent = task_info["task_name"] or run_bundle["task_id"]
    pr_title = f"{run_bundle['task_id']}: {task_intent}"
    resolved_output_path = output_path or default_output_path(root, run_bundle["run_id"])
    resolved_output_path.parent.mkdir(parents=True, exist_ok=True)

    required_artifacts = [
        "run bundle",
        "PR gate judgment",
        "implementation report",
        "backend evidence",
    ]

    metadata = {
        "task_id": run_bundle["task_id"],
        "run_id": run_bundle["run_id"],
        "branch_name": branch_name,
        "base_branch": base_branch,
        "pr_title": pr_title,
        "pr_body_path": pr_body_path_override
        or str((root / "reports" / "pr_bodies" / f"{run_bundle['run_id']}_pr_body.md").resolve().relative_to(root)).replace("\\", "/"),
        "gate_verdict": pr_gate["gate_verdict"],
        "gate_reason": pr_gate["gate_reason"],
        "selected_backend": run_bundle["selected_backend"],
        "selected_route": run_bundle["selected_route"],
        "selected_model": run_bundle["selected_model"],
        "acceptance_verdict": run_bundle["acceptance_verdict"],
        "verification_status": run_bundle["verification_status"],
        "bundle_path": relpath(root, str(run_bundle_path)),
        "pr_gate_path": relpath(root, str(pr_gate_path)),
        "report_path": run_bundle["implementation_report_path"],
        "backend_evidence_path": run_bundle["backend_evidence_path"],
        "required_artifacts": required_artifacts,
        "changed_files": task_info["changed_files"],
        "purpose": task_info["purpose"] or task_intent,
        "non_goals": task_info["non_goals"],
    }

    resolved_output_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return metadata, resolved_output_path


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    run_bundle_path = Path(args.run_bundle).resolve()
    pr_gate_path = Path(args.pr_gate).resolve()
    output_path = Path(args.output).resolve() if args.output else None

    _, resolved_output_path = build_metadata(
        root=root,
        run_bundle_path=run_bundle_path,
        pr_gate_path=pr_gate_path,
        branch_name_override=args.branch_name,
        base_branch=args.base_branch,
        output_path=output_path,
    )
    print(str(resolved_output_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
