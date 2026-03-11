# Executor Observability Runbook

## Purpose
Define the minimum runtime observability model for Executor-driven PR creation.

This runbook keeps observability practical:
- summary artifact
- event trace
- CI artifact export

## Runtime Artifacts
Executor runtime artifacts live under `.runtime/` and must stay untracked.

Artifacts:
- `.runtime/execution-report.json`
- `.runtime/debug-trace.jsonl`

## Execution Report
`execution-report.json` is the summary artifact for one executor run.

It records:
- stable schema version
- run id
- executor name and version
- repository branch, base commit, and head commit
- workspace cleanliness and changed file inventory
- PR body artifact path and title
- canonical validator version and command
- pre-validation result
- timing information
- runtime artifact paths
- failure stage and error summary

Use it when you need a single-file answer to:
- what branch ran
- what validator version ran
- what PR body file was validated
- whether pre-validation passed
- which files were in scope
- where execution failed

## Debug Trace
`debug-trace.jsonl` is the stage-by-stage event log.

Each line is one JSON object and is intended to be grep- and jq-friendly.

Expected stages:
- `bootstrap`
- `main_sync`
- `branch_create`
- `executor_runtime`
- `pr_body_render`
- `pre_validation`
- `pr_create`
- `post_create`

Expected failure stage enum in the summary report:
- `none`
- `bootstrap`
- `main_sync`
- `branch_create`
- `executor_runtime`
- `pr_body_render`
- `pre_validation`
- `pr_create`
- `post_create`

## Operational Flow
1. `scripts/codex-task.sh` initializes the runtime artifacts and records launcher stages.
2. The executor renders the PR body to a local file.
3. `scripts/pre-validate-pr.sh` validates that exact file with `tools/pr_readiness_validator.py`.
4. The same script updates the summary report, appends debug trace events, and only then creates the PR.
5. GitHub Actions uploads the runtime artifacts so CI-side validation remains auditable.

## CI Artifact Export
Runtime observability artifacts are uploaded from the existing validator workflows.

Expected CI artifacts:
- execution report artifact containing `.runtime/execution-report.json`
- debug trace artifact containing `.runtime/debug-trace.jsonl`

This gives an audit path even when local console output is unavailable.

## Debugging Guidance
Use `execution-report.json` first for:
- run summary
- failure stage
- error summary
- changed file inventory

Use `debug-trace.jsonl` next for:
- exact stage order
- success/error transitions
- artifact handoff points
- validator version attached to pre-validation events

## Non-goals
- dashboarding
- metrics backend
- historical search UI
- cross-repository observability
- schema registry or policy engine
