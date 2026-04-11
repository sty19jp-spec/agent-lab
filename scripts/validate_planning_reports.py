from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path


REQUIRED_SECTIONS = [
    "目的",
    "今回やらないこと",
    "現在地",
    "対象範囲",
    "仮定 / 未確定事項",
    "前提依存",
    "推奨の進め方",
    "主なリスク",
    "次の一手",
    "最終判定",
]

VALID_VERDICTS = {"pass", "conditional-pass", "fail"}


@dataclass
class ValidationResult:
    path: Path
    verdict: str
    declared_verdict: str | None
    missing_sections: list[str]
    weak_sections: list[str]
    notes: list[str]


def parse_sections(text: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current: str | None = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if line.startswith("## "):
            current = line[3:].strip()
            sections[current] = []
            continue
        if current is not None:
            sections[current].append(line)

    return sections


def extract_declared_verdict(lines: list[str]) -> str | None:
    for raw_line in lines:
        line = raw_line.strip().replace("`", "")
        for verdict in VALID_VERDICTS:
            if f"- {verdict}" == line or line == verdict:
                return verdict
    return None


def section_has_meaningful_content(lines: list[str], section_name: str) -> bool:
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            continue
        if section_name == "最終判定" and line in {
            "- pass / conditional-pass / fail",
            "pass / conditional-pass / fail",
            "- `pass` / `conditional-pass` / `fail`",
        }:
            continue
        if line in {"-", "- 仮定:", "- 未確定事項:", "  -"}:
            continue
        return True
    return False


def count_unresolved_items(lines: list[str]) -> int:
    in_unresolved_block = False
    count = 0

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
            normalized = line.lstrip("-").strip().lower()
            if normalized not in {"", "なし", "なし。", "none", "n/a"}:
                count += 1

    return count


def validate_report(path: Path) -> ValidationResult:
    text = path.read_text(encoding="utf-8")
    sections = parse_sections(text)

    missing_sections: list[str] = []
    weak_sections: list[str] = []
    notes: list[str] = []

    for section in REQUIRED_SECTIONS:
        if section not in sections:
            missing_sections.append(section)
            continue
        if not section_has_meaningful_content(sections[section], section):
            weak_sections.append(section)

    declared_verdict = None
    unresolved_items = 0
    if "最終判定" in sections:
        declared_verdict = extract_declared_verdict(sections["最終判定"])
        if declared_verdict is None:
            notes.append("最終判定の語彙が `pass / conditional-pass / fail` に一致しません。")
    if "仮定 / 未確定事項" in sections:
        unresolved_items = count_unresolved_items(sections["仮定 / 未確定事項"])

    if missing_sections or declared_verdict == "fail" or declared_verdict is None:
        verdict = "fail"
    elif weak_sections or unresolved_items > 0 or declared_verdict == "conditional-pass":
        verdict = "conditional-pass"
    else:
        verdict = "pass"

    if verdict == "conditional-pass" and unresolved_items > 0:
        notes.append(f"未確定事項に実質的な保留項目が {unresolved_items} 件あります。")
    if declared_verdict == "conditional-pass" and unresolved_items == 0 and not weak_sections:
        notes.append(
            "`conditional-pass` が宣言されていますが、未確定事項の保留項目は機械的には検出されませんでした。"
        )

    return ValidationResult(
        path=path,
        verdict=verdict,
        declared_verdict=declared_verdict,
        missing_sections=missing_sections,
        weak_sections=weak_sections,
        notes=notes,
    )


def collect_targets(root: Path, targets: list[str]) -> tuple[list[Path], list[Path]]:
    if targets:
        resolved_targets: list[Path] = []
        missing_targets: list[Path] = []
        for target in targets:
            candidate = Path(target)
            if not candidate.is_absolute():
                candidate = root / candidate
            candidate = candidate.resolve()
            if candidate.exists():
                resolved_targets.append(candidate)
            else:
                missing_targets.append(candidate)
        return resolved_targets, missing_targets
    return sorted((root / "reports" / "planning").glob("*.md")), []


def print_result(result: ValidationResult) -> None:
    print(f"file: {result.path}")
    print(f"verdict: {result.verdict}")
    print(f"declared_verdict: {result.declared_verdict or 'missing'}")
    print(
        "missing_sections: "
        + (", ".join(result.missing_sections) if result.missing_sections else "none")
    )
    print(
        "weak_sections: "
        + (", ".join(result.weak_sections) if result.weak_sections else "none")
    )
    if result.notes:
        print("notes:")
        for note in result.notes:
            print(f"- {note}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="planning report の最小 validator を実行します。"
    )
    parser.add_argument(
        "targets",
        nargs="*",
        help="検査対象の planning report パス。省略時は reports/planning/*.md を対象にします。",
    )
    parser.add_argument(
        "--root",
        default=".",
        help="project root を指定します。省略時はカレントディレクトリです。",
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
        return 1

    if not targets:
        print("planning report が見つかりませんでした。", file=sys.stderr)
        return 1

    results = [validate_report(path) for path in targets]
    for result in results:
        print_result(result)

    return 1 if any(result.verdict == "fail" for result in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
