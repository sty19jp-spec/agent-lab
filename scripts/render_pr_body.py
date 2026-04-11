from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a PR body from deterministic PR metadata."
    )
    parser.add_argument("--root", required=True)
    parser.add_argument("--pr-metadata", required=True)
    parser.add_argument("--template-path")
    parser.add_argument("--output")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def list_to_bullets(items: list[str]) -> str:
    if not items:
        return "- none"
    return "\n".join(f"- {item}" for item in items)


def list_to_code_bullets(items: list[str]) -> str:
    if not items:
        return "- none"
    return "\n".join(f"- `{item}`" for item in items)


def default_template(root: Path) -> Path:
    return root / "templates" / "pr-body-template.md"


def default_output(root: Path, run_id: str) -> Path:
    return root / "reports" / "pr_bodies" / f"{run_id}_pr_body.md"


def fill_template(template: str, replacements: dict[str, str]) -> str:
    body = template
    for key, value in replacements.items():
        body = body.replace(f"{{{{{key}}}}}", value)
    return body


def build_sections(metadata: dict[str, Any]) -> dict[str, str]:
    gate_verdict = metadata["gate_verdict"]
    scope = [
        "Generate deterministic branch / PR metadata from run bundle and PR gate inputs.",
        "Render a validator-compatible PR body with artifact references and gate status.",
    ]
    if gate_verdict == "hold":
        scope.append("Preserve manual review requirements in the PR-facing summary.")

    validation_lines = [
        f"- gate verdict: `{metadata['gate_verdict']}`",
        f"- verification status: `{metadata['verification_status']}`",
        f"- acceptance verdict: `{metadata['acceptance_verdict']}`",
    ]
    if gate_verdict == "hold":
        validation_lines.append(f"- manual review required: `{metadata['gate_reason']}`")
    elif gate_verdict == "fail":
        validation_lines.append(f"- blocking condition: `{metadata['gate_reason']}`")

    evidence_lines = [
        f"- run bundle: `{metadata['bundle_path']}`",
        f"- PR gate judgment: `{metadata['pr_gate_path']}`",
        f"- implementation report: `{metadata['report_path']}`",
        f"- backend evidence: `{metadata['backend_evidence_path']}`",
    ]

    if gate_verdict == "hold":
        risk_text = "Level: medium. Manual review is required because the current run is on hold and should not be merged automatically."
    elif gate_verdict == "fail":
        risk_text = "Level: high. The current run is blocked by a fail verdict, so the PR must not be merged until the evidence and validation are repaired."
    else:
        risk_text = "Level: low. Evidence and verification are complete for the current run, so the PR summary can be used as-is."

    return {
        "purpose": metadata["purpose"],
        "scope": list_to_bullets(scope),
        "changed_files": list_to_code_bullets(metadata.get("changed_files", [])),
        "validation": "\n".join(validation_lines),
        "evidence": "\n".join(evidence_lines),
        "risk": risk_text,
        "non_goals": list_to_bullets(metadata.get("non_goals", [])),
    }


def render_body(
    root: Path,
    metadata: dict[str, Any],
    template_path: Path | None = None,
    output_path: Path | None = None,
) -> tuple[str, Path]:
    resolved_template_path = template_path or default_template(root)
    resolved_output_path = output_path or default_output(root, metadata["run_id"])
    resolved_output_path.parent.mkdir(parents=True, exist_ok=True)

    template = resolved_template_path.read_text(encoding="utf-8")
    sections = build_sections(metadata)
    body = fill_template(template, sections)
    resolved_output_path.write_text(body + "\n", encoding="utf-8")
    return body, resolved_output_path


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    pr_metadata_path = Path(args.pr_metadata).resolve()
    metadata = load_json(pr_metadata_path)
    template_path = Path(args.template_path).resolve() if args.template_path else None
    output_path = Path(args.output).resolve() if args.output else None

    _, resolved_output_path = render_body(
        root=root,
        metadata=metadata,
        template_path=template_path,
        output_path=output_path,
    )
    print(str(resolved_output_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
