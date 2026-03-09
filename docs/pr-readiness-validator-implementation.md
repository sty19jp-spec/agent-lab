# PR Readiness Validator Implementation Specification (Layer5 Phase36)

## Purpose
Define the concrete implementation model for the Phase35 PR Readiness Validator design so it can run in GitHub Actions and gate merge decisions.

This phase implements validator execution and CI wiring. It does not change governance decisions from Phase35.

## Execution Architecture
Components:
- Validator script: `tools/pr_readiness_validator.py`
- CI workflow: `.github/workflows/pr-readiness-validator.yml`

Architecture flow:
1. Pull Request (or manual dispatch) triggers workflow.
2. Workflow checks out repository and prepares Python runtime.
3. Workflow invokes validator script with PR context.
4. Validator evaluates required checks.
5. Validator prints `PASS` or `FAIL`.
6. Workflow succeeds on `PASS`, fails on `FAIL`.

## Validation Flow
Event
-> Collect PR context (body, branch, diff base/head)
-> Run validator script
-> Execute checks in order:
   1. Diff Scope Validation
   2. Metadata Validation
   3. Evidence Validation
   4. Branch Validation
   5. Completion Condition Validation
-> Emit final result (`PASS`/`FAIL`)
-> Return exit status (0 on PASS, non-zero on FAIL)

## Validator Script Responsibilities
Script: `tools/pr_readiness_validator.py`

Responsibilities:
- parse PR metadata body
- inspect changed files from git diff
- validate branch naming against required regex
- validate metadata sections and non-empty values
- validate evidence references and metadata consistency
- validate completion condition (`PR-ready`)
- output final result as `PASS` or `FAIL`
- exit non-zero on failure

Inputs:
- PR event payload (`GITHUB_EVENT_PATH`) for pull_request
- explicit override inputs for workflow_dispatch (head/base/body)

Output contract:
- stdout: `PASS` or `FAIL`
- stderr: optional diagnostics
- exit code:
  - `0` when PASS
  - non-zero when FAIL

## GitHub Actions Workflow Responsibilities
Workflow: `.github/workflows/pr-readiness-validator.yml`

Triggers:
- `pull_request`
- `workflow_dispatch`

Responsibilities:
- checkout repository with enough history for diff
- install Python
- collect PR/body/branch inputs
- run validator script
- fail workflow if validator exits non-zero

## Validation Rule Mapping
### 1) Diff Scope Validation
- ensure changed files remain within task scope declaration and allowed adjacent scope
- reject unrelated or prohibited file changes

### 2) Metadata Validation
Required non-empty sections in PR body:
- Purpose
- Scope
- Changed files
- Validation
- Evidence
- Risk
- Non-goals

### 3) Evidence Validation
- evidence references in PR metadata must be resolvable
- evidence claims must be consistent with changed files and validation statements

### 4) Branch Validation
- head branch must match:
  - `codex/phase[0-9]+-.*`

### 5) Completion Condition Validation
- PR must explicitly satisfy completion condition:
  - `PR-ready`

## PASS / FAIL Semantics
- `PASS`: all required checks pass
- `FAIL`: one or more required checks fail

No soft-pass is defined in base Phase36 behavior.

## Failure Behavior
Policy:
- `FAIL` -> Merge Block

Operational effect:
- validator non-zero exit causes workflow failure
- failing workflow blocks merge path under governance policy

## CI Runtime Notes
- pull_request path is authoritative for merge gating
- workflow_dispatch is for manual re-check and diagnostics
- workflow_dispatch must provide explicit PR body input to validate required metadata sections

## Non-goals (Phase36)
- introducing override/exception merge path
- replacing existing governance model
- implementing repository setting changes in this document
