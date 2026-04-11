from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

from validate_planning_reports import (
    collect_targets,
    count_unresolved_items,
    extract_declared_verdict,
    parse_sections,
    validate_report,
)


ACTION_END = "終了"
ACTION_REPLAN = "再planning"
ACTION_RESEARCH = "research"
ACTION_IMPLEMENTATION = "implementation"


@dataclass
class EvaluationResult:
    path: Path
    validator_verdict: str
    report_verdict: str | None
    unresolved_items: list[str]
    recommended_action: str
    action_reason: str
    next_step_hint: str | None
    operator_attention: list[str]
    missing_sections: list[str]
    weak_sections: list[str]
    validator_notes: list[str]

    def to_dict(self) -> dict[str, object]:
        return {
            "path": str(self.path),
            "validator_verdict": self.validator_verdict,
            "report_verdict": self.report_verdict,
            "unresolved_items": self.unresolved_items,
            "recommended_action": self.recommended_action,
            "action_reason": self.action_reason,
            "next_step_hint": self.next_step_hint,
            "operator_attention": self.operator_attention,
            "missing_sections": self.missing_sections,
            "weak_sections": self.weak_sections,
            "validator_notes": self.validator_notes,
        }


def normalize_line(raw_line: str) -> str:
    return raw_line.strip().lstrip("-").strip().replace("`", "")


def extract_unresolved_items(lines: list[str]) -> list[str]:
    in_unresolved_block = False
    items: list[str] = []

    for raw_line in lines:
        line = raw_line.strip().replace("`", "")
        if not line:
            continue
        if line.startswith("- 未確定事項:") or line == "未確定事項:":
            in_unresolved_block = True
            continue
        if line.startswith("- 仮定:") or line == "仮定:":
            in_unresolved_block = False
            continue
        if not in_unresolved_block:
            continue
        if line.startswith("-"):
            normalized = line.lstrip("-").strip()
            if normalized.lower() not in {"", "なし", "なし。", "none", "n/a"}:
                items.append(normalized)

    return items


def summarize_section(lines: list[str]) -> str | None:
    normalized_lines = [normalize_line(line) for line in lines if normalize_line(line)]
    if not normalized_lines:
        return None
    return " ".join(normalized_lines)


def infer_action_from_next_step(lines: list[str]) -> tuple[str, str] | None:
    text = summarize_section(lines)
    if text is None:
        return None

    lowered = text.lower()
    if "implementation" in lowered or "実装" in text:
        return (
            ACTION_IMPLEMENTATION,
            "次の一手で implementation への接続が明示されているため、次 cycle は implementation に進みます。",
        )
    if "research" in lowered or "調査" in text:
        return (
            ACTION_RESEARCH,
            "次の一手で research への接続が明示されているため、次 cycle は research に進みます。",
        )
    if (
        "再planning" in text
        or "replanning" in lowered
        or "planning に戻" in text
        or "planning へ戻" in text
        or "再整理" in text
        or "見直し" in text
        or "再定義" in text
    ):
        return (
            ACTION_REPLAN,
            "次の一手で planning への戻りが示されているため、次 cycle は再planning に進みます。",
        )
    if "終了" in text or "完了" in text or "close" in lowered:
        return (
            ACTION_END,
            "次の一手で追加 cycle を回さない意図が読み取れるため、現段階では終了とします。",
        )
    return None


def build_operator_attention(
    unresolved_items: list[str],
    missing_sections: list[str],
    weak_sections: list[str],
    validator_notes: list[str],
) -> list[str]:
    attention: list[str] = []

    if missing_sections:
        attention.append(
            "validator で必須見出しの欠落が見つかっているため、report 構造を補ってから再評価してください。"
        )
    if weak_sections:
        attention.append(
            "validator で内容が弱い見出しが見つかっているため、根拠や次の一手を補強してください。"
        )
    if unresolved_items:
        attention.extend(
            [
                f"未確定事項が残っています: {item}"
                for item in unresolved_items
            ]
        )
    attention.extend(validator_notes)
    return attention


def evaluate_report(path: Path) -> EvaluationResult:
    validation = validate_report(path)
    text = path.read_text(encoding="utf-8")
    sections = parse_sections(text)

    report_verdict = None
    if "最終判定" in sections:
        report_verdict = extract_declared_verdict(sections["最終判定"])

    unresolved_items = extract_unresolved_items(sections.get("仮定 / 未確定事項", []))
    unresolved_count = count_unresolved_items(sections.get("仮定 / 未確定事項", []))
    next_step_hint = summarize_section(sections.get("次の一手", []))
    operator_attention = build_operator_attention(
        unresolved_items=unresolved_items,
        missing_sections=validation.missing_sections,
        weak_sections=validation.weak_sections,
        validator_notes=validation.notes,
    )

    if validation.verdict == "fail":
        recommended_action = ACTION_REPLAN
        action_reason = (
            "planning validator が fail を返しており、report 構造か判定語彙に問題があるため、まず再planning が必要です。"
        )
    elif report_verdict in {None, "fail"}:
        recommended_action = ACTION_REPLAN
        action_reason = (
            "report 自身の最終判定が fail 相当であり、このまま次 profile に進める条件を満たしていないため、再planning に戻します。"
        )
    else:
        inferred = infer_action_from_next_step(sections.get("次の一手", []))
        if inferred is not None:
            recommended_action, action_reason = inferred
        elif unresolved_count > 0:
            recommended_action = ACTION_RESEARCH
            action_reason = (
                "未確定事項が残っており、次の一手から行き先も読めないため、まず research で前提確認を行います。"
            )
        elif report_verdict == "pass":
            recommended_action = ACTION_END
            action_reason = (
                "report は pass で、未確定事項も残っていませんが、次 cycle の行き先が明示されていないため、現段階では終了とします。"
            )
        elif report_verdict == "conditional-pass":
            recommended_action = ACTION_REPLAN
            action_reason = (
                "report は conditional-pass ですが、次に進む先が明示されていないため、再planning で handoff を明確にします。"
            )
        else:
            recommended_action = ACTION_END
            action_reason = (
                "追加 cycle を要求する明示がなく、未確定事項も残っていないため、現段階では終了とします。"
            )

    return EvaluationResult(
        path=path,
        validator_verdict=validation.verdict,
        report_verdict=report_verdict,
        unresolved_items=unresolved_items,
        recommended_action=recommended_action,
        action_reason=action_reason,
        next_step_hint=next_step_hint,
        operator_attention=operator_attention,
        missing_sections=validation.missing_sections,
        weak_sections=validation.weak_sections,
        validator_notes=validation.notes,
    )


def print_result(result: EvaluationResult) -> None:
    print(f"file: {result.path}")
    print(f"validator_verdict: {result.validator_verdict}")
    print(f"report_verdict: {result.report_verdict or 'missing'}")
    print(f"unresolved_items: {len(result.unresolved_items)}")
    print(f"recommended_action: {result.recommended_action}")
    print(f"next_step_hint: {result.next_step_hint or 'none'}")
    print(f"action_reason: {result.action_reason}")
    if result.operator_attention:
        print("operator_attention:")
        for item in result.operator_attention:
            print(f"- {item}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="planning report の validator 結果と report 内容を使って次 action を返します。"
    )
    parser.add_argument(
        "targets",
        nargs="*",
        help="評価対象の planning report パス。省略時は reports/planning/*.md を対象にします。",
    )
    parser.add_argument(
        "--root",
        default=".",
        help="project root を指定します。省略時はカレントディレクトリです。",
    )
    parser.add_argument(
        "--format",
        choices={"text", "json"},
        default="text",
        help="出力形式を指定します。省略時は text です。",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    targets, missing_targets = collect_targets(root, args.targets)

    if missing_targets:
        for missing_target in missing_targets:
            print(
                f"error: planning report が見つかりません: {missing_target}",
                file=sys.stderr,
            )
        if not targets:
            return 1

    if not targets:
        print("planning report が見つかりませんでした。", file=sys.stderr)
        return 1

    results = [evaluate_report(path) for path in targets]
    if args.format == "json":
        payload: object
        if len(results) == 1:
            payload = results[0].to_dict()
        else:
            payload = [result.to_dict() for result in results]
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    for result in results:
        print_result(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
