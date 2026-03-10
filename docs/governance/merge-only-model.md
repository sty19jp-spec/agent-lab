# Merge-Only Model

## Purpose
Define the repository governance model for change delivery: work lands on `main` by Pull Request merge only.

## Normative Flow
Approved delivery path:

AI Executor -> feature branch -> Pull Request -> validator checks -> human merge -> `main`

Disallowed normal path:

- direct push to `main`

## Roles
### AI Executor
Responsible for:

- branch creation
- scoped implementation or documentation changes
- local verification
- commit, push, and PR preparation

### Human
Responsible for:

- approvals
- GUI-only operations when needed
- final merge decision

### Repository Governance
Responsible for:

- blocking non-compliant merges through rulesets and required checks

## Merge Rule
A change is eligible for merge only when:

1. it is proposed through a PR to `main`
2. required validator checks pass
3. the PR is complete and reviewable
4. a human chooses to merge it

## Direct Push Policy
Direct pushes to `main` are outside the normal operating model and should be blocked by repository protection settings.

Emergency bypass, if available in GitHub settings, is an exception path and not part of normal execution.

## Why This Model Exists
The merge-only path keeps:

- scope reviewable
- validator output auditable
- human merge authority explicit
- repository history aligned with PR evidence

## Non-goals
This model does not:

- require humans to perform normal CLI work
- grant AI agents merge authority
- replace validator logic with manual judgment alone

## Related Documents
- `docs/branch-protection-governance.md`
- `docs/validator-chain-governance.md`
- `docs/runbooks/pr-ready-flow.md`
