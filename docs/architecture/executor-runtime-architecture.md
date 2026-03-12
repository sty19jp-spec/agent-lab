# Executor Runtime Architecture

## Purpose

Describe the final Layer5 executor runtime architecture as implemented in this repository.

Layer5 architecture is a single-repository, PR-centered governance runtime. It is not a general distributed execution platform.

## Overview

Execution path:

launcher
↓
stage runtime
↓
execution evidence
↓
failure recovery
↓
execution reliability
↓
pre-validation
↓
PR creation
↓
validator chain
↓
human merge

Concrete repository flow:

`make codex-task`
↓
`scripts/codex-task.sh`
↓
executor runtime libraries in `scripts/lib/`
↓
PR body render
↓
`scripts/pre-validate-pr.sh`
↓
`tools/pr_readiness_validator.py`
↓
`gh pr create --body-file`
↓
GitHub validator checks
↓
human merge to `main`

## Pipeline Stages

The stage-aware runtime uses these stages:

- `bootstrap`
- `main_sync`
- `branch_create`
- `executor_runtime`
- `pr_body_render`
- `pre_validation`
- `pr_create`
- `post_create`

These stages provide explicit execution boundaries for tracing, failure classification, retry handling, and recovery decisions.

## Runtime Layers

### 1. Launcher Layer

Primary responsibility:

- start from controlled repository state
- sync to canonical `origin/main`
- create a compliant task branch
- initialize runtime context

Primary components:

- `Makefile`
- `scripts/codex-task.sh`

Guarantees:

- task launch starts from canonical repository state
- branch naming follows current governance
- runtime artifacts are configured before executor work begins

Non-goals:

- long-running orchestration
- multi-repo coordination
- bypassing merge-only delivery

### 2. Stage Runtime Layer

Primary responsibility:

- stage-aware execution control
- explicit stage transitions
- bounded retries and resume-safe state updates

Primary components:

- `scripts/lib/executor-runtime.sh`
- `scripts/lib/executor-stage.sh`

Guarantees:

- controlled stage transitions
- explicit stage status and retry state
- single-repository execution contract

Non-goals:

- general workflow engine behavior
- parallel execution fabric

### 3. Evidence Layer

Primary responsibility:

- produce auditable execution artifacts
- preserve traceability for debugging and review

Primary artifacts:

- `.runtime/execution-report.json`
- `.runtime/debug-trace.jsonl`
- `.runtime/execution-state.json`
- `.runtime/failure-report.json`
- `.runtime/reliability-metrics.json`

Guarantees:

- execution state is inspectable
- failure location is reconstructable
- runtime evidence remains outside the committed diff

Non-goals:

- dashboarding
- historical search platform
- external analytics backend

### 4. Failure Recovery Layer

Primary responsibility:

- bounded retry orchestration
- resume-safe recovery
- deterministic PR reconciliation
- run locking

Primary guarantees:

- retryable failures are retried within explicit limits
- non-retryable failures stop execution
- ambiguous external state stops instead of guessing
- duplicate PR creation is avoided through guarded reconciliation

Non-goals:

- merge conflict automation
- force push or history rewrite recovery
- validator bypass

### 5. Reliability Layer

Primary responsibility:

- idempotency classification
- runtime consistency validation
- self-diagnostics
- observational failure analytics

Primary components:

- `scripts/lib/executor-health.sh`
- reliability logic inside `scripts/lib/executor-runtime.sh`
- reliability logic inside `scripts/lib/executor-failure.sh`

Guarantees:

- safe stage re-entry semantics
- limited safe repair only
- bootstrap self-check before risky execution
- reliability metrics without changing validator authority

Non-goals:

- sandbox isolation
- policy-driven distributed scheduling
- cross-repository orchestration

## Validation Path

Validation path is intentionally strict:

1. render the PR body to a file
2. run local pre-validation against that exact file
3. submit the PR with `gh pr create --body-file <same file>`
4. run GitHub validator checks against the created PR
5. hand final merge judgment to a human

This keeps the local validation artifact and the submitted GitHub artifact identical.

## Human Boundary

Human role in Layer5:

- merge judgment
- exception approval when explicitly required
- GUI-only operations

Executor role in Layer5:

- repository inspection
- implementation
- validation
- evidence generation
- PR creation

The human is not part of the normal CLI execution path and does not perform standard repository operations for the executor.

## Architecture Guarantees

- Layer5 is repository-first and merge-only.
- The runtime is stage-aware enough for controlled execution.
- Evidence and provenance are auditable.
- Recovery stays inside repository-safe bounds.
- Reliability controls improve re-execution safety without weakening validators.

## Layer5 Non-goals

- distributed agent platform
- multi-repo automation fabric
- sandbox platform implementation
- broader orchestration beyond the repository governance core
