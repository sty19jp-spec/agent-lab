# Ruleset Policy

## Purpose
Define the practical repository policy for GitHub rulesets or branch protection that enforce the PR-first model on `main`.

## Policy Baseline
Target branch:

- `main`

Repository intent:

- all normal changes arrive through a non-draft Pull Request
- merge is blocked until required validation succeeds
- branch naming and PR metadata remain validator-enforced at the PR layer

## Required Protection Outcomes
Protection for `main` should enforce:

1. Pull Request required before merge
2. required status check must pass before merge
3. direct push should be blocked in normal operation
4. repository history should remain auditable and reviewable

## Required Check Strategy
Preferred required status check:

- `Validator Chain`

Rationale:

- it is the single chain-level PASS/FAIL result
- it already depends on PR readiness validation
- it already includes evidence and provenance handling for changed evidence files
- it reduces configuration drift compared with requiring multiple overlapping checks

## PR State Expectations
Ruleset or branch protection should support this operating policy:

- Ready PRs only for merge consideration
- Draft PRs are work-in-progress and not merge candidates
- validator failures block merge until corrected

## Repository Operator Guidance
When reviewing ruleset configuration, verify:

1. target branch is `main`
2. PR merge is required
3. `Validator Chain` is configured as a required check
4. direct push is not available as a routine path
5. settings still match the documented governance model

## Change Control
Ruleset changes should be treated as governance changes, not casual repository maintenance.

Any change to required checks, bypass behavior, or merge prerequisites should be documented in the repository before it becomes the new normal.

## Non-goals
This policy does not:

- define validator internals
- require new runtime checks
- replace GitHub repository settings with documentation alone

## Related Documents
- `docs/branch-protection-governance.md`
- `docs/governance/merge-only-model.md`
- `docs/pr-readiness-validator.md`
