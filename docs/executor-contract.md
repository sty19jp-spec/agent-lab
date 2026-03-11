# Executor Contract

## 1. Purpose
Define the minimum operational contract an Executor must follow to create a validator-pass Pull Request from the start.

This document is executor-facing and aligned to current enforced repository behavior.

## 2. Scope
This contract covers:
- branch naming for Executor work
- required PR metadata
- diff scope discipline
- the minimum `PR-ready` condition
- the practical PR creation flow

This contract does not change validators, workflows, templates, or runtime behavior.

## 3. Branch Naming Rule
Executor branches must follow this pattern:
- `codex/phase<number>-<task-slug>`

Current validator enforcement accepts:
- `codex/phase[0-9]+-.*`

Examples:
- `codex/phase42-executor-contract`
- `codex/phase41-codex-task-launcher`

Non-compliant branch names are expected to fail validation.

## 4. PR Metadata Schema
Every Executor-created PR must include these exact non-empty sections:
- `Purpose`
- `Scope`
- `Changed files`
- `Validation`
- `Evidence`
- `Risk`
- `Non-goals`

Operational rules:
- PR metadata must describe the actual PR, not the intended task.
- `Scope` must explain the actual work represented by the diff.
- `Changed files` must be generated from the actual changed paths.
- `Validation` must include the literal token `PR-ready`.
- `Evidence` must reference repository-visible files, artifacts, or factual result statements tied to the PR contents.
- `Risk` and `Non-goals` must stay specific to the current PR.

## 5. Diff Scope Rule
The PR diff must stay inside task scope.

Operational rules:
- `git diff --name-only <base>...<head>` is the source of truth for changed paths.
- `Changed files` should list the exact repository paths from the diff.
- Prefer exact paths over broad patterns.
- Do not include files in `Changed files` that are not in the actual diff.
- Do not omit changed files from PR metadata.
- If an adjacent file is required for the same task, explain that dependency explicitly in `Scope`.
- No unrelated cleanup, refactor, or cross-task edits are allowed.

Current validator-aware note:
- Path extraction is strict and mismatch between PR metadata and the actual diff can fail validation.
- Repository-root files need extra care. If a root file such as `Makefile` is changed, declare it explicitly in `Scope` and `Evidence` in addition to reflecting the actual diff.

## 6. PR-ready Definition
A PR is `PR-ready` only when all of the following are true:
- the workspace is clean before PR creation
- the branch name matches the required Executor pattern
- the diff contains no unrelated files
- required PR metadata sections are complete and factual
- `Changed files` matches the actual diff
- `Evidence` is not command names only
- required validators pass
- the PR is open as a Ready PR, not Draft

## 7. Executor PR Creation Procedure
1. Create a compliant branch name before implementation.
2. Make only the scoped change required by the task.
3. Verify there is no unrelated diff in the workspace.
4. Run task-local validation as required by the task.
5. Commit the scoped change.
6. Push the branch to origin.
7. Inspect the actual diff with `git diff --name-only origin/main...HEAD` or an equivalent base/head diff.
8. Generate PR metadata from the actual diff and actual validation results.
9. Ensure `Changed files` matches the changed paths exactly.
10. Ensure `Scope` explains any adjacent file that is required for correctness or validation.
11. Ensure `Evidence` names concrete files, artifacts, or result statements tied to the PR.
12. Create the PR as Ready PR with the required metadata sections.
13. Confirm validator status after PR creation and fix metadata or scope issues before treating the task as complete.

## 8. Failure Prevention Notes
Prevent these known failure patterns:
- `Changed files` not matching the actual diff
- metadata written too broadly for the real diff
- evidence written as command names only
- branch naming mismatch
- unrelated diff included in the PR

Practical guardrails:
- build the PR body after checking the final diff
- keep `Changed files` path-by-path and factual
- keep `Scope` narrow enough to explain every changed file
- use evidence lines that mention the changed file and what it proves
- remove unrelated edits before commit and before PR creation

## 9. Future Alignment Note
This contract is the current reference point for future Executor guidance, PR template alignment, and validator-documentation alignment.

This task does not implement those downstream changes.
