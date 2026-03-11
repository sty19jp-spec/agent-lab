# PR-Ready Flow Runbook

## Purpose
Define the standard executor flow from task start to a `PR-ready` Pull Request.

This runbook is intentionally minimal and aligned to the current validator and branch-protection model in this repository.

## Operating Model
Delivery path:

AI Executor -> feature branch -> scoped edits -> local review -> commit -> push -> Pull Request -> validator checks -> human merge

Completion condition:

- `PR-ready`

## Standard Flow
1. Start from the latest `main`.
2. Create a short-lived branch named `codex/phaseXX-<task-slug>`.
3. Keep the change set limited to the assigned scope.
4. Review with `git status` and `git diff`.
5. Commit with a clear, task-specific message.
6. Fetch `origin` and rebase onto `origin/main`.
7. Push the branch to GitHub.
8. Open a Ready PR with complete metadata.
9. Wait for validator checks before human merge.

Conflict-prevention rule:

- immediately before PR creation, rebase the task branch onto `origin/main`
- if the rebase surfaces conflicts, resolve them before pushing or opening the PR

## Scope Discipline
Allowed:

- files explicitly requested by the task
- minimal adjacent documentation changes required for consistency

Not allowed unless the task explicitly requires it:

- unrelated refactors
- broad formatting cleanup
- validator or runtime logic changes for a documentation-only task
- mixing multiple task domains into one PR

## Minimum Local Checks
Before opening the PR:

```bash
git status --short --branch
git diff --stat
git diff
```

Use these checks to confirm:

- branch name is correct
- only intended files changed
- the final diff matches the stated task

## PR Body Requirements
Every operational PR should include non-empty content for:

- `Purpose`
- `Scope`
- `Changed files`
- `Validation`
- `Evidence`
- `Risk`
- `Non-goals`

Required completion token:

- `PR-ready`

## Evidence Expectations
For standard documentation or governance tasks, the minimum evidence is usually:

- `git status`
- `git diff`

Evidence must be factual. Do not claim commands, tests, or artifacts that were not actually produced.

## Ready PR Checklist
Mark the PR ready only when all of the following are true:

1. the branch name is compliant
2. the diff is scoped
3. the PR body is complete and factual
4. the PR is not a Draft
5. the work is represented as `PR-ready`

## Common Failure Modes
- PR body sections are present but empty
- branch name does not match the validator pattern
- `Changed files` in the PR body does not match the actual diff
- unrelated local files were committed by accident
- the PR is opened as Draft even though validation is complete

## Handoff Rule
Human responsibility starts at merge judgment.

Executor responsibility ends only when the branch is pushed, the PR is open, and the PR metadata accurately supports a `PR-ready` review state.

## Related Documents
- `docs/RUNBOOK-ai-pr-workflow.md`
- `docs/pr-readiness-validator.md`
- `docs/governance/merge-only-model.md`
- `docs/governance/ruleset-policy.md`
