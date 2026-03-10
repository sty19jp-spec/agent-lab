# Branch Protection Governance (Layer5 Phase38)

## 1. Purpose
Define the final merge-gate governance for `main` by enforcing GitHub Branch Protection as the repository-level control that completes Layer5 validator-chain design.

This document is the approved governance specification for branch protection behavior in this repository.
補足: 本ドキュメントは `main` のマージ保護設定に関する運用上の正規仕様です。

## 2. Background
Layer5 Phase37 established Validator Chain governance and CI execution (`Validator Chain`) for Pull Requests.

CI execution alone is insufficient for merge protection. Without enforced branch protection on `main`, a branch can still be merged or pushed in ways that bypass intended PASS/FAIL merge gating.

Phase38 closes that gap by defining required GitHub Branch Protection settings.

## 3. Governance Objective
Establish a simple, practical, merge-only governance path for this personal/experimental repository:

AI Executor -> Pull Request -> Validator Chain -> Branch Protection -> Human Merge

Operating model constraints:
- ChatGPT remains Architect/Auditor role only.
- Codex (or equivalent execution agent) acts as Executor.
- Human role remains final merge decision only.

## 4. Branch Protection Settings
Target branch: `main`
Protection mechanism: GitHub Branch Protection Rule

Required settings:
- Require a pull request before merging: `ON`
- Required status checks: `Validator Chain` only
- Block direct push to `main`: `ON` (enforced via PR-required protection)
- Require linear history: `ON`
- Allow administrator bypass: `ON`

## 5. Required Status Check Strategy
Only `Validator Chain` is required (not each validator workflow individually).

Rationale:
- `Validator Chain` is the single authoritative merge-gate result (PASS/FAIL).
- It already orchestrates Evidence/Provenance and PR Readiness checks in deterministic order.
- Requiring each validator separately increases configuration drift risk and maintenance cost.
- A single required check keeps governance minimal, reproducible, and aligned with repository intent.

## 6. Merge Flow
Final merge flow:

1. AI Executor prepares a task-scoped feature branch and opens a PR to `main`.
2. `Validator Chain` runs on the PR and must return PASS.
3. GitHub Branch Protection enforces that merge is blocked until required check conditions are satisfied.
4. Human performs merge judgment and executes the merge.

Linear history is enabled to keep `main` history clean, auditable, and easier to trace for this repository's PR-first operating model.

## 7. Admin Bypass Policy
Administrator bypass remains enabled as an emergency safety valve.

Policy intent:
- Use only for exceptional recovery situations (for example, CI outage or urgent remediation).
- Do not use as a routine path to skip validator governance.
- Normal operation remains PR + `Validator Chain` + human merge.

## 8. Operational Note
Actual Branch Protection settings are applied and maintained in GitHub repository settings UI.

This document defines the approved governance spec (what must be configured), while GitHub UI holds the active enforcement state (how it is configured).

## 9. Completion Criteria
Phase38 governance is complete when all conditions are met:
- `docs/branch-protection-governance.md` exists and reflects the approved settings in this phase.
- The merge-gate sequence is explicitly defined as:
  AI Executor -> Pull Request -> Validator Chain -> Branch Protection -> Human Merge.
- Required status checks for `main` are defined as `Validator Chain` only.
- Direct push to `main` is defined as blocked.
- Human remains merge decision owner in the operating model.
