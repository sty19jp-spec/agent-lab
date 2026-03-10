#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Dict, List, Optional, Sequence, Tuple

REQUIRED_SECTIONS: Sequence[str] = (
    "Purpose",
    "Scope",
    "Changed files",
    "Validation",
    "Evidence",
    "Risk",
    "Non-goals",
)
BRANCH_REGEX = re.compile(r"^codex/phase[0-9]+-.*$")
COMPLETION_TOKEN = "pr-ready"
ALLOWED_ADJACENT_ROOTS: Sequence[str] = (
    "docs/",
    "tools/",
    ".github/workflows/",
)
ALLOWED_PATH_PREFIXES: Sequence[str] = (
    "scripts/",
    "tools/",
    "docs/",
    ".github/",
    "tests/",
    "examples/",
    "runtime/",
    "registry/",
)


class PRReadinessValidator:
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.errors: List[str] = []
        self.warnings: List[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def _run_git(self, *args: str) -> str:
        try:
            out = subprocess.check_output(["git", *args], cwd=self.repo_root, stderr=subprocess.STDOUT, text=True)
            return out.strip()
        except subprocess.CalledProcessError as exc:
            self.error(f"git command failed: git {' '.join(args)} :: {exc.output.strip()}")
            return ""

    def _extract_sections(self, body: str) -> Dict[str, str]:
        # Supports markdown headings: #, ##, ###
        heading_pattern = re.compile(r"^\s{0,3}#{1,3}\s+(.+?)\s*$")
        lines = body.splitlines()
        sections: Dict[str, List[str]] = {}
        current: Optional[str] = None

        def normalize(name: str) -> str:
            return re.sub(r"\s+", " ", name.strip().lower())

        required_lookup = {normalize(name): name for name in REQUIRED_SECTIONS}

        for line in lines:
            m = heading_pattern.match(line)
            if m:
                key_norm = normalize(m.group(1))
                current = required_lookup.get(key_norm)
                if current is not None and current not in sections:
                    sections[current] = []
                continue
            if current is not None:
                sections[current].append(line)

        return {k: "\n".join(v).strip() for k, v in sections.items()}

    def _extract_paths(self, text: str) -> List[str]:
        cleaned: List[str] = []

        def add(candidate: str) -> None:
            norm = candidate.strip().strip("`").rstrip(".,:;").lstrip("./")
            if not norm or "/" not in norm or norm in cleaned:
                return

            if norm.startswith("codex/"):
                return

            if not any(norm.startswith(prefix) for prefix in ALLOWED_PATH_PREFIXES):
                return

            cleaned.append(norm)

        for line in text.splitlines():
            for candidate in re.findall(r"`([^`]+)`", line):
                add(candidate)

            stripped = line.strip()
            if stripped.startswith(("- ", "* ")):
                stripped = stripped[2:].strip()

            for candidate in re.findall(r"(?<!\S)([./A-Za-z0-9_*?\[\]-]+(?:/[./A-Za-z0-9_*?\[\]-]+)+)(?!\S)", stripped):
                add(candidate)

        return cleaned

    def _matches_declared_path(self, declared: str, actual: str) -> bool:
        if any(ch in declared for ch in "*?[]"):
            return fnmatch.fnmatch(actual, declared)
        return declared == actual

    def _parse_pr_context(self, event_path: Optional[Path], args: argparse.Namespace) -> Tuple[str, str, str, str]:
        pr_body = ""
        head_ref = args.head_ref or ""
        base_sha = args.base_sha or ""
        head_sha = args.head_sha or ""

        if event_path is not None and event_path.exists():
            try:
                payload = json.loads(event_path.read_text(encoding="utf-8"))
            except Exception as exc:  # pragma: no cover
                self.error(f"failed to parse event payload: {exc}")
                payload = {}

            pr = payload.get("pull_request") if isinstance(payload, dict) else None
            if isinstance(pr, dict):
                if not args.head_ref:
                    head = pr.get("head") if isinstance(pr.get("head"), dict) else {}
                    if isinstance(head.get("ref"), str):
                        head_ref = head["ref"]
                if not args.base_sha:
                    base = pr.get("base") if isinstance(pr.get("base"), dict) else {}
                    if isinstance(base.get("sha"), str):
                        base_sha = base["sha"]
                if not args.head_sha:
                    head = pr.get("head") if isinstance(pr.get("head"), dict) else {}
                    if isinstance(head.get("sha"), str):
                        head_sha = head["sha"]
                if isinstance(pr.get("body"), str):
                    pr_body = pr.get("body", "")

        if args.pr_body_file:
            body_path = (self.repo_root / args.pr_body_file).resolve()
            if not body_path.exists():
                self.error(f"pr body file not found: {args.pr_body_file}")
            else:
                pr_body = body_path.read_text(encoding="utf-8")

        if args.pr_body:
            pr_body = args.pr_body

        if not head_ref:
            # Fallback for workflow_dispatch/local run.
            head_ref = os.getenv("GITHUB_HEAD_REF") or os.getenv("GITHUB_REF_NAME") or self._run_git("branch", "--show-current")

        if not head_sha:
            head_sha = self._run_git("rev-parse", "HEAD")

        if not base_sha:
            merge_base = self._run_git("merge-base", "origin/main", "HEAD")
            if merge_base:
                base_sha = merge_base

        return pr_body, head_ref, base_sha, head_sha

    def _validate_branch(self, head_ref: str) -> None:
        if not head_ref:
            self.error("branch validation failed: head branch is empty")
            return
        if not BRANCH_REGEX.fullmatch(head_ref):
            self.error(f"branch validation failed: '{head_ref}' does not match {BRANCH_REGEX.pattern}")

    def _validate_metadata(self, pr_body: str) -> Dict[str, str]:
        if not pr_body.strip():
            self.error("metadata validation failed: PR body is empty")
            return {}

        sections = self._extract_sections(pr_body)
        for sec in REQUIRED_SECTIONS:
            if sec not in sections:
                self.error(f"metadata validation failed: missing section '{sec}'")
                continue
            if not sections[sec].strip():
                self.error(f"metadata validation failed: section '{sec}' is empty")

        joined = "\n".join(sections.values()).lower()
        if COMPLETION_TOKEN not in joined:
            self.error("completion condition validation failed: 'PR-ready' token not found in PR metadata")

        return sections

    def _changed_files(self, base_sha: str, head_sha: str, override_file: Optional[str]) -> List[str]:
        if override_file:
            p = (self.repo_root / override_file).resolve()
            if not p.exists():
                self.error(f"changed files override not found: {override_file}")
                return []
            return [line.strip() for line in p.read_text(encoding="utf-8").splitlines() if line.strip()]

        if not base_sha or not head_sha:
            self.error("diff scope validation failed: base/head sha is missing")
            return []

        out = self._run_git("diff", "--name-only", f"{base_sha}...{head_sha}")
        return [line.strip() for line in out.splitlines() if line.strip()]

    def _validate_diff_scope(self, changed: List[str], declared_changed: List[str], scope_text: str, head_ref: str) -> None:
        if not changed:
            self.error("diff scope validation failed: no changed files detected")
            return

        forbidden_patterns = (
            re.compile(r"(^|/)\.env($|\.)"),
            re.compile(r"(^|/).*secret.*", re.IGNORECASE),
            re.compile(r"(^|/).*private[_-]?key.*", re.IGNORECASE),
            re.compile(r"(^|/)id_rsa($|\.)"),
        )

        for path in changed:
            for pat in forbidden_patterns:
                if pat.search(path):
                    self.error(f"diff scope validation failed: forbidden file pattern detected: {path}")

        changed_set = set(changed)
        if declared_changed:
            missing_decl = sorted(p for p in changed if not any(self._matches_declared_path(spec, p) for spec in declared_changed))
            extra_decl = sorted(
                spec for spec in declared_changed if not any(self._matches_declared_path(spec, path) for path in changed_set)
            )
            if extra_decl:
                self.error("diff scope validation failed: Changed files section lists non-diff files: " + ", ".join(extra_decl))

            slug_part = head_ref.split("-", 1)[1] if "-" in head_ref else ""
            keywords = [k for k in re.split(r"[-_]+", slug_part.lower()) if len(k) >= 3 and k not in {"phase", "codex"}]
            scope_lower = scope_text.lower()
            for p in missing_decl:
                in_adjacent_root = any(p.startswith(root) for root in ALLOWED_ADJACENT_ROOTS)
                path_lower = p.lower()
                has_keyword = any(k in path_lower for k in keywords) if keywords else False
                adjacent_allowed = "adjacent" in scope_lower
                if in_adjacent_root and (has_keyword or adjacent_allowed):
                    self.warn(f"adjacent scope allowance applied for file: {p}")
                else:
                    self.error(f"diff scope validation failed: undeclared/out-of-scope file in diff: {p}")

    def _validate_evidence(self, evidence_text: str, validation_text: str, changed: List[str]) -> None:
        evidence_refs = self._extract_paths(evidence_text)
        if not evidence_refs:
            self.error("evidence validation failed: no local evidence references found in Evidence section")
            return

        resolvable: List[str] = []
        for ref in evidence_refs:
            rp = (self.repo_root / ref).resolve()
            if rp.exists():
                resolvable.append(ref)
            else:
                self.error(f"evidence validation failed: referenced path not found: {ref}")

        for ref in resolvable:
            if ref.endswith(".json"):
                rp = (self.repo_root / ref).resolve()
                try:
                    data = json.loads(rp.read_text(encoding="utf-8"))
                except Exception as exc:
                    self.error(f"evidence validation failed: JSON parse error in {ref}: {exc}")
                    continue
                if not isinstance(data, dict):
                    self.error(f"evidence validation failed: evidence JSON root must be object: {ref}")

        if not validation_text.strip():
            self.error("evidence validation failed: Validation section is empty")

        changed_set = set(changed)
        referenced_changed = [p for p in evidence_refs if p in changed_set]
        if not referenced_changed:
            self.warn("evidence section does not directly reference changed files; accepted if external evidence paths are valid")

    def run(self, args: argparse.Namespace) -> int:
        event_path = None
        if args.event_path:
            event_path = (self.repo_root / args.event_path).resolve() if not Path(args.event_path).is_absolute() else Path(args.event_path)
        else:
            env_ep = os.getenv("GITHUB_EVENT_PATH")
            if env_ep:
                event_path = Path(env_ep)

        pr_body, head_ref, base_sha, head_sha = self._parse_pr_context(event_path, args)
        self._validate_branch(head_ref)

        sections = self._validate_metadata(pr_body)
        changed = self._changed_files(base_sha, head_sha, args.changed_files_file)
        declared_changed = self._extract_paths(sections.get("Changed files", "")) if sections else []

        self._validate_diff_scope(changed, declared_changed, sections.get("Scope", "") if sections else "", head_ref)
        self._validate_evidence(
            sections.get("Evidence", "") if sections else "",
            sections.get("Validation", "") if sections else "",
            changed,
        )

        for w in self.warnings:
            print(f"WARN: {w}", file=sys.stderr)
        for e in self.errors:
            print(f"ERROR: {e}", file=sys.stderr)

        if self.errors:
            print("FAIL")
            return 1

        print("PASS")
        return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PR Readiness Validator")
    parser.add_argument("--event-path", help="Path to GitHub event JSON (defaults to GITHUB_EVENT_PATH)")
    parser.add_argument("--pr-body", help="Override PR body text")
    parser.add_argument("--pr-body-file", help="Path to PR body markdown file")
    parser.add_argument("--head-ref", help="Override head branch name")
    parser.add_argument("--base-sha", help="Override base commit sha")
    parser.add_argument("--head-sha", help="Override head commit sha")
    parser.add_argument("--changed-files-file", help="File containing changed files list, one path per line")
    parser.add_argument("--repo-root", default=".", help="Repository root path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    validator = PRReadinessValidator(repo_root=repo_root)
    return validator.run(args)


if __name__ == "__main__":
    raise SystemExit(main())
