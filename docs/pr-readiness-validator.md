# PR Readiness Validator Specification (Layer5 Phase35)

## Purpose
Define a deterministic validator that decides whether an AI-Executor-created Pull Request is safe to merge.

This validator evaluates PR readiness under the Layer5 governance model and enforces merge gating based on objective checks.

## Execution Model
Operating model:

Human
-> ChatGPT (Architect / Auditor)
-> AI Executor (Codex CLI / Claude Code)
-> Pull Request
-> PR Readiness Validator
-> Human Merge

Execution rule:
- Human merges only PRs that receive `PASS`.
- `FAIL` blocks merge.

## Validation Rules
A PR is `PASS` only when all required checks pass:
1. Diff Scope Validation
2. Metadata Validation
3. Evidence Validation
4. Branch Validation
5. Completion Condition Validation

Any single failed check yields `FAIL`.

## Diff Scope Validation
### Objective
Ensure PR changes stay within assigned task scope, with controlled adjacent-scope allowance.

### Required checks
- Changed files must belong to task scope.
- Adjacent scope changes are allowed only when directly required for correctness, traceability, or validation of the same task.
- No unrelated file changes are allowed.

### Adjacent scope allowance
Adjacent changes are acceptable only when all conditions hold:
- direct dependency from task files
- minimal footprint
- clearly explained in PR `Scope`
- no expansion into another task domain

### Fail conditions
- unrelated files changed
- opportunistic refactor outside task
- broad cleanup outside task
- another task's files included

## Metadata Validation
### Objective
Ensure PR body contains required governance metadata.

### Required non-empty sections
- Purpose
- Scope
- Changed files
- Validation
- Evidence
- Risk
- Non-goals

### Required checks
- each section exists
- each section has non-empty content
- section claims are factual and aligned with executed work

### Fail conditions
- missing section
- empty section
- materially inconsistent or fabricated validation claims

## Evidence Validation
### Objective
Ensure evidence references exist and are consistent with PR metadata.

### Required checks
- evidence references listed in PR `Evidence` are resolvable (file path, artifact, command result, or recorded execution output)
- evidence statements are consistent with:
  - changed files listed in PR metadata
  - validation commands/results listed in PR metadata
  - actual PR diff
- evidence does not contradict validator outputs or execution outcomes

### Fail conditions
- missing/unresolvable evidence references
- mismatch between evidence and metadata
- mismatch between evidence and actual diff/validation results

## Branch Validation
### Objective
Ensure branch naming and branch state are compliant.

### Naming rule
Head branch must match:
- `codex/phaseXX-<task-slug>`

Example:
- `codex/phase35-pr-readiness-validator`

### Required checks
- branch name matches required pattern
- branch is not detached
- PR head branch is pushed and resolvable remotely

### Fail conditions
- non-compliant branch name
- detached/headless state
- missing remote head branch

## Completion Condition Validation
### Objective
Enforce the Executor completion condition defined by Phase34.

### Normative rule
Executor completion condition is:
- `PR-ready`

### Required checks
- PR indicates completion at PR-ready level (not implementation-only)
- required validations are completed and reported
- PR is created as Ready PR (not Draft)

### Fail conditions
- completion described as implementation-only
- required validation incomplete or not reported
- PR remains Draft

## Validator Output
Allowed output values:
- `PASS`
- `FAIL`

Output contract:
- `PASS`: all checks pass
- `FAIL`: one or more checks fail, with failure reasons

## Failure Behavior
Policy:
- `FAIL` -> Merge Block

Operational rule:
- PRs with `FAIL` must not be merged
- Human merge is allowed only for `PASS` PRs

## Future Extension
Potential extensions (non-normative for Phase35):
- machine-readable policy profile for task-specific scope boundaries
- confidence scoring in addition to PASS/FAIL
- stronger evidence attestation links between PR metadata and artifacts
- CI integration profile for automatic merge-gate enforcement across repositories
- auto-merge support remains out of scope for Phase35 and may be specified in a future phase
