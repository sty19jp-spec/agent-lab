from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any

from evaluate_pr_gate import build_result as build_pr_gate_result
from provenance_utils import build_provenance
from render_pr_body import render_body
from write_pr_metadata import build_metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="run bundle の verification command を再実行し、CI 向け artifact を再生成します。"
    )
    parser.add_argument("--root", default=".")
    parser.add_argument("--run-bundle", required=True)
    parser.add_argument("--output")
    parser.add_argument(
        "--force-verification-status",
        choices=["pass", "fail", "not-run"],
        default=None,
        help="verification_status を強制上書きします。sample fail 再現用です。",
    )
    parser.add_argument(
        "--fail-on-gate",
        choices=["never", "fail", "hold-or-fail"],
        default="fail",
        help="指定 verdict でプロセスを非0終了させます。",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def default_output(root: Path, run_id: str) -> Path:
    return root / "reports" / "ci_verifier" / f"{run_id}_ci_verifier.json"


def default_pr_gate_output(root: Path, run_id: str) -> Path:
    return root / "reports" / "pr_gate" / f"{run_id}_ci_pr_gate_judgment.json"


def default_source_pr_gate_path(root: Path, run_id: str) -> Path:
    return root / "reports" / "pr_gate" / f"{run_id}_pr_gate_judgment.json"


def default_pr_metadata_output(root: Path, run_id: str) -> Path:
    return root / "reports" / "pr_metadata" / f"{run_id}_ci_pr_metadata.json"


def default_pr_body_output(root: Path, run_id: str) -> Path:
    return root / "reports" / "pr_bodies" / f"{run_id}_ci_pr_body.md"


def normalize_command(command: str, root: Path) -> str:
    normalized = command
    match = re.search(r"--root\s+(?P<value>\"[^\"]+\"|\S+)", command)
    if match:
        raw_value = match.group("value")
        source_root = raw_value.strip("\"")
        replacement = f"\"{root}\"" if " " in str(root) else str(root)
        normalized = normalized.replace(raw_value, replacement, 1)
        normalized = normalized.replace(source_root, str(root))
    return normalized


def command_text_from_spec(command_spec: Any) -> str:
    if isinstance(command_spec, dict):
        return str(command_spec["command"])
    return str(command_spec)


def expected_returncode_from_spec(command_spec: Any) -> int:
    if isinstance(command_spec, dict):
        return int(command_spec.get("expected_returncode", 0))
    return 0


def execute_command(command_spec: Any, root: Path) -> dict[str, Any]:
    command = command_text_from_spec(command_spec)
    expected_returncode = expected_returncode_from_spec(command_spec)
    normalized_command = normalize_command(command, root)
    completed = subprocess.run(
        normalized_command,
        cwd=root,
        shell=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return {
        "command": command,
        "normalized_command": normalized_command,
        "expected_returncode": expected_returncode,
        "returncode": completed.returncode,
        "passed": completed.returncode == expected_returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def infer_verification_status(command_results: list[dict[str, Any]]) -> str:
    if not command_results:
        return "not-run"
    if all(result["passed"] for result in command_results):
        return "pass"
    return "fail"


def should_fail_process(gate_verdict: str, fail_on_gate: str) -> bool:
    if fail_on_gate == "never":
        return False
    if fail_on_gate == "hold-or-fail":
        return gate_verdict in {"hold", "fail"}
    return gate_verdict == "fail"


def build_ci_result(
    root: Path,
    run_bundle_path: Path,
    force_verification_status: str | None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], str]:
    run_bundle = load_json(run_bundle_path)
    command_results = [execute_command(command, root) for command in run_bundle.get("verification_commands", [])]

    reproduced_verification_status = force_verification_status or infer_verification_status(command_results)
    reproduced_run_bundle = dict(run_bundle)
    reproduced_run_bundle["verification_status"] = reproduced_verification_status
    pr_gate = build_pr_gate_result(root, reproduced_run_bundle)

    verifier_provenance = build_provenance(
        root=root,
        executor_type="github-actions-ci-verifier",
        operator="ci-verifier",
        runtime_name="harness-system-ci-verifier",
        executor_id=f"{run_bundle['run_id']}-ci-verifier",
        task_version=run_bundle.get("task_id"),
    )

    ci_result = {
        "run_id": run_bundle["run_id"],
        "task_id": run_bundle["task_id"],
        "source_run_bundle_path": str(run_bundle_path.resolve().relative_to(root)).replace("\\", "/"),
        "expected_verification_status": run_bundle.get("verification_status"),
        "reproduced_verification_status": reproduced_verification_status,
        "verification_status_match": run_bundle.get("verification_status") == reproduced_verification_status,
        "expected_gate_verdict": None,
        "reproduced_gate_verdict": pr_gate["gate_verdict"],
        "acceptance_verdict": run_bundle.get("acceptance_verdict"),
        "selected_backend": run_bundle.get("selected_backend"),
        "selected_route": run_bundle.get("selected_route"),
        "selected_model": run_bundle.get("selected_model"),
        "operator_review_required": pr_gate["operator_review_required"],
        "validator_verdict": pr_gate["gate_verdict"],
        "command_results": command_results,
        "source_provenance": run_bundle.get("provenance"),
        "verifier_provenance": verifier_provenance,
    }
    return run_bundle, reproduced_run_bundle, pr_gate, json.dumps(ci_result, ensure_ascii=False, indent=2)


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    run_bundle_path = Path(args.run_bundle).resolve()

    run_bundle, reproduced_run_bundle, pr_gate, ci_result_text = build_ci_result(
        root=root,
        run_bundle_path=run_bundle_path,
        force_verification_status=args.force_verification_status,
    )

    output_path = Path(args.output).resolve() if args.output else default_output(root, run_bundle["run_id"])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(ci_result_text + "\n", encoding="utf-8")

    pr_gate_output_path = default_pr_gate_output(root, run_bundle["run_id"])
    pr_gate_output_path.parent.mkdir(parents=True, exist_ok=True)
    pr_gate_output_path.write_text(json.dumps(pr_gate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    metadata, pr_metadata_output_path = build_metadata(
        root=root,
        run_bundle_path=run_bundle_path,
        pr_gate_path=pr_gate_output_path,
        output_path=default_pr_metadata_output(root, run_bundle["run_id"]),
        pr_body_path_override=str(default_pr_body_output(root, run_bundle["run_id"]).resolve().relative_to(root)).replace("\\", "/"),
    )
    _, pr_body_output_path = render_body(
        root=root,
        metadata=metadata,
        output_path=default_pr_body_output(root, run_bundle["run_id"]),
    )

    ci_result = json.loads(ci_result_text)
    source_pr_gate_path = default_source_pr_gate_path(root, run_bundle["run_id"])
    ci_result["expected_gate_verdict"] = load_json(source_pr_gate_path).get("gate_verdict") if source_pr_gate_path.exists() else None
    ci_result["reproduced_run_bundle_verification_status"] = reproduced_run_bundle["verification_status"]
    ci_result["generated_pr_gate_path"] = str(pr_gate_output_path.resolve().relative_to(root)).replace("\\", "/")
    ci_result["generated_pr_metadata_path"] = str(pr_metadata_output_path.resolve().relative_to(root)).replace("\\", "/")
    ci_result["generated_pr_body_path"] = str(pr_body_output_path.resolve().relative_to(root)).replace("\\", "/")
    output_path.write_text(json.dumps(ci_result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(str(output_path))
    if should_fail_process(pr_gate["gate_verdict"], args.fail_on_gate):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
