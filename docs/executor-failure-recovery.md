# Executor Failure Recovery

This document defines the minimal Phase48 failure recovery behavior for the shell-based executor runtime.

## Purpose

The executor keeps the existing PR-ready flow, but adds deterministic recovery controls for executor-owned runtime state.

## Recovery scope

- Retry orchestration stays stage-aware and uses the existing shell runtime modules.
- Resume is allowed only for safe stages: `main_sync`, `branch_create`, `executor_runtime`, `pr_body_render`, and `pre_validation`.
- `pr_create` is not auto-resumed. It may only be reconciled by checking whether a PR already exists for the current head branch and whether the existing PR body matches the rendered local artifact.
- `post_create` remains best-effort only.

## Retry policy

- Maximum stage retry attempts: `2`
- Backoff schedule:
  - first retry: `2` seconds
  - second retry: `5` seconds
- Retryable failure classes:
  - `transient_command_error`
  - `transient_network_error`
  - `gh_api_temporary_error`
- All other failure classes are treated as non-retryable.

## Runtime state and evidence

Runtime artifacts stay under `.runtime/` and are not committed.

- `.runtime/execution-state.json`: current resumable state for the active run
- `.runtime/failure-report.json`: structured terminal failure evidence
- `.runtime/execution-report.json`: summary artifact
- `.runtime/debug-trace.jsonl`: stage and recovery event log
- `.runtime/run.lock`: single-run lock file

The execution state records:

- `run_id`
- `current_stage`
- `completed_stages`
- `failed_stage`
- `failure_class`
- `retry_count_by_stage`
- `branch_name`
- `commit_head`
- `pr_body_file`
- `last_updated_at`

The failure report records the failing stage, command, exit code, failure class, retryability, retry attempt, resume eligibility, repository status summary, and suggested operator action.

## Run lock

- If `.runtime/run.lock` already exists, the executor stops immediately.
- Phase48 does not support forced lock takeover.
- Lock cleanup happens only for the current executor process.

## Resume rules

- Resume must be explicitly requested with `EXECUTOR_RESUME=1` or `RESUME=1`.
- Resume uses `.runtime/execution-state.json` as the canonical local recovery state.
- `branch_create` may resume only when the expected branch already exists locally and matches the recorded branch name.
- Ambiguous external state stops execution instead of guessing.

## Self-healing boundary

Allowed:

- retrying `git fetch`
- retrying temporary `gh` failures
- refreshing remote metadata
- recreating missing runtime artifacts
- regenerating the PR body artifact path
- reconciling an already-created branch
- reconciling an already-created PR during `pr_create`

Forbidden:

- auto-resolving merge conflicts
- modifying tracked files outside the declared task scope
- force push, force reset, or rewrite-based recovery
- validator bypass
- workflow or governance mutation
