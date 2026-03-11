# Executor Runtime Stabilization

## Purpose
Define the stabilized shell-based executor runtime contract for the autonomous PR pipeline.

This phase keeps the runtime shell-first and compatible with the current PR-ready flow.

## Scope
This stabilization covers:
- explicit executor stages
- stage state handling
- failure classification
- bounded retry policy for transient commands
- run contract between launcher, pre-validation, and PR creation

This phase does not change:
- validator rules
- GitHub workflow policy
- branch protection
- merge governance

## Runtime Stages
The executor runtime uses these fixed stages:
- `bootstrap`
- `main_sync`
- `branch_create`
- `executor_runtime`
- `pr_body_render`
- `pre_validation`
- `pr_create`
- `post_create`

Each stage records:
- `stage_status`
- `started_at`
- `ended_at`
- `retry_count`
- `fail_classification`

## Failure Classification
Failures are classified as:
- `config_error`
- `repo_state_error`
- `validation_error`
- `transient_command_error`
- `unknown_error`

## Failure Policy
Hard-stop behavior applies to:
- `bootstrap`
- `main_sync`
- `branch_create`
- `pre_validation`
- `pr_create`

Best-effort behavior applies to:
- `post_create`

Retry policy:
- no retry for deterministic config, repository-state, or validation failures
- bounded retry only for transient command failures

## Run Contract
Runtime input:
- repository working-copy state
- task name / task description
- shell execution environment

Runtime output:
- rendered PR body artifact
- `.runtime/execution-report.json`
- `.runtime/debug-trace.jsonl`
- PR URL when PR creation succeeds

## Runtime Modules
Shell helpers are split into:
- `scripts/lib/executor-runtime.sh`
- `scripts/lib/executor-stage.sh`
- `scripts/lib/executor-failure.sh`

Entrypoints remain:
- `scripts/codex-task.sh`
- `scripts/pre-validate-pr.sh`

## Compatibility Rules
The stabilized runtime preserves:
- the shell-first architecture
- canonical validator execution through `tools/pr_readiness_validator.py`
- pre-validation wrapper entrypoint `scripts/pre-validate-pr.sh`
- same-artifact PR body validation and submission
- `.runtime/` as untracked runtime-only storage

## Operational Note
The goal of this phase is runtime stability, not redesign.

If the runtime fails, the report and trace should identify:
- which stage failed
- how it failed
- whether retry occurred
- whether the failure was deterministic or transient
