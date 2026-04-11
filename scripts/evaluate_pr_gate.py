from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_path(root: Path, raw: str | None) -> Path | None:
    if not raw:
        return None
    candidate = Path(raw)
    if candidate.is_absolute():
        return candidate
    return (root / candidate).resolve()


def artifact_exists(root: Path, raw_path: str | None) -> bool:
    path = resolve_path(root, raw_path)
    return bool(path and path.exists())


def build_result(root: Path, run_bundle: dict[str, Any]) -> dict[str, Any]:
    required_artifacts_complete = all(
        [
            artifact_exists(root, run_bundle.get("implementation_report_path")),
            artifact_exists(root, run_bundle.get("backend_evidence_path")),
            run_bundle.get("verification_status") is not None,
        ]
    )

    verification_status = run_bundle.get("verification_status")
    acceptance_verdict = run_bundle.get("acceptance_verdict")
    failure_classification = run_bundle.get("failure_classification")
    operator_return = bool(run_bundle.get("operator_return", False))

    gate_verdict = "hold"
    gate_reason = "manual review が必要です。"
    operator_review_required = True

    if not required_artifacts_complete:
        gate_verdict = "fail"
        gate_reason = "required artifact が不足しています。"
        operator_review_required = False
    elif verification_status == "fail" or acceptance_verdict == "fail":
        gate_verdict = "fail"
        gate_reason = "verification または acceptance が fail です。"
        operator_review_required = False
    elif (
        verification_status == "pass"
        and acceptance_verdict == "pass"
        and not operator_return
    ):
        gate_verdict = "pass"
        gate_reason = "required artifact が揃い、verification と acceptance が pass です。"
        operator_review_required = False
    elif failure_classification in {"provider-quota-exceeded", "provider-unavailable"}:
        gate_verdict = "hold"
        gate_reason = "provider 側の一時要因なので、manual review 付きで hold にします。"
        operator_review_required = True
    else:
        gate_verdict = "hold"
        gate_reason = "contract は概ね成立していますが、manual review 前提です。"
        operator_review_required = True

    return {
        "run_id": run_bundle.get("run_id"),
        "gate_verdict": gate_verdict,
        "gate_reason": gate_reason,
        "required_artifacts_complete": required_artifacts_complete,
        "verification_status": verification_status,
        "acceptance_verdict": acceptance_verdict,
        "operator_review_required": operator_review_required,
        "selected_backend": run_bundle.get("selected_backend"),
        "selected_route": run_bundle.get("selected_route"),
        "selected_model": run_bundle.get("selected_model"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="run bundle から PR gate verdict を評価します。")
    parser.add_argument("--root", default=".", help="project root を指定します。")
    parser.add_argument("--run-bundle", required=True, help="run bundle JSON を指定します。")
    parser.add_argument("--output", default=None, help="出力先 PR gate judgment JSON を指定します。")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    run_bundle_path = resolve_path(root, args.run_bundle)
    assert run_bundle_path is not None

    run_bundle = load_json(run_bundle_path)
    result = build_result(root, run_bundle)

    output_path = resolve_path(root, args.output)
    if output_path is None:
        output_path = root / "reports" / "pr_gate" / f"{result['run_id']}_pr_gate_judgment.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
