# Executor Reliability Layer

This document defines the minimal Phase49 reliability layer added on top of the shell executor failure-recovery runtime.

## Purpose

The reliability layer improves re-execution safety, runtime consistency, self-diagnostics, and failure analytics without changing validator behavior, branch policy, or the existing PR-ready flow.

## Reliability controls

- Stage idempotency classes:
  - `pure_read`
  - `convergent_write`
  - `guarded_side_effect`
- `branch_create` and runtime artifact generation are treated as convergent writes.
- `pr_create` remains a guarded side effect and relies on deterministic PR reconciliation instead of duplicate creation.

## Runtime consistency

- `.runtime/execution-state.json` now carries an explicit schema version.
- Runtime state is validated before execution continues.
- Safe repair is limited to:
  - filling missing safe defaults in runtime state
  - recreating missing optional runtime artifacts
  - clearing a stale run lock only when the PID is dead and lock metadata matches the persisted runtime state
- Corrupted or non-repairable state fails fast.

## Health check

The launcher performs a runtime self-check during bootstrap:

- verifies repository access with `git`
- verifies required dependencies such as `codex`
- validates runtime directory integrity
- validates state and lock consistency before lock acquisition

## Failure analytics

Observational metrics are written to `.runtime/reliability-metrics.json`.

The metrics include:

- total run counts
- failure counts by class
- retry totals by stage
- stage duration totals and last duration
- repair attempt totals and outcomes

These metrics are operational diagnostics only. They do not change validator behavior or PR readiness rules.

## Additional helper

Phase49 adds `scripts/lib/executor-health.sh` as a small helper library so runtime self-checks and limited safe repair stay isolated from the main launcher flow.
