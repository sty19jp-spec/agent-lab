# Validator Debug Runbook

## Purpose
Use this runbook when a Pull Request fails validator checks or is not clearly `PR-ready`.

This document is operational guidance only. It does not change validator policy or runtime behavior.

## Validator Surfaces
Current PR-facing validator surfaces in this repository:

- `Validator Chain`
- `PR Readiness Validator`
- `Evidence Validation`

Primary merge-gate outcome:

- `PASS`
- `FAIL`

## Fast Triage
Start with the smallest checks first:

1. Confirm the branch name matches `codex/phaseXX-<task-slug>`.
2. Confirm the PR body has non-empty sections for:
   - `Purpose`
   - `Scope`
   - `Changed files`
   - `Validation`
   - `Evidence`
   - `Risk`
   - `Non-goals`
3. Confirm the PR explicitly states `PR-ready`.
4. Confirm the diff only contains task-scoped files.
5. Confirm any evidence claims are real and match the diff.

## Local Debug Flow
### 1. Check repository state

```bash
git status --short --branch
git diff --stat origin/main...
git diff --name-only origin/main...
```

Use these outputs to catch the most common causes:

- wrong branch name
- unexpected changed files
- uncommitted local changes that were not intended for the PR

### 2. Inspect the PR body before opening or updating the PR

Create a local markdown file for the PR body if needed:

```bash
cat > /tmp/pr-body.md <<'EOF'
## Purpose
...

## Scope
...

## Changed files
...

## Validation
PR-ready

## Evidence
git status
git diff

## Risk
Low

## Non-goals
No runtime change
EOF
```

Then validate it locally:

```bash
python3 tools/pr_readiness_validator.py \
  --repo-root . \
  --pr-body-file /tmp/pr-body.md \
  --head-ref "$(git branch --show-current)" \
  --base-sha "$(git merge-base origin/main HEAD)" \
  --head-sha "$(git rev-parse HEAD)"
```

### 3. Validate changed evidence files when applicable
Run this only if the diff includes `examples/evidence/*-evidence.json`:

```bash
python3 tools/evidence_validator.py \
  --evidence-file examples/evidence/<file>-evidence.json \
  --schema-name execution-evidence \
  --schema-version v1 \
  --policy strict
```

### 4. Review workflow logs
If the PR already exists, inspect the failing GitHub Actions run:

```bash
gh run list --limit 10
gh run view <RUN_ID> --log-failed
```

Look for the first failing stage. Fix that first instead of treating the chain result as the primary error.

## Failure Patterns
### Branch validation failure
Likely causes:

- branch does not match `codex/phaseXX-<task-slug>`
- PR was opened from the wrong branch
- remote branch was not pushed

Actions:

1. rename or recreate the branch with a compliant name
2. push the head branch
3. reopen or update the PR

### Metadata validation failure
Likely causes:

- missing required section
- required section present but empty
- `Validation` or completion language does not show `PR-ready`

Actions:

1. update the PR body
2. make the metadata factual
3. rerun validation

### Diff scope failure
Likely causes:

- unrelated file edits
- generated files or local noise included in the PR
- scope expanded beyond the assigned task

Actions:

1. remove unrelated changes from the branch
2. keep the PR focused on the assigned files
3. explain any adjacent-scope file if it is strictly required

### Evidence mismatch failure
Likely causes:

- evidence section references commands not actually run
- changed files list does not match the diff
- evidence JSON or artifact references are stale

Actions:

1. update the PR body so claims match reality
2. regenerate or correct evidence artifacts if the task includes them
3. rerun the validator

## Recovery Rule
Do not bypass the failure by weakening the validator or editing around the rule unless the task explicitly requires validator work.

The correct recovery path is:

1. isolate the failing rule
2. make the minimum factual correction
3. rerun validation
4. reopen or update the PR as `PR-ready`

## Related Documents
- `docs/pr-readiness-validator.md`
- `docs/validator-chain-governance.md`
- `docs/branch-protection-governance.md`
- `docs/runbooks/pr-ready-flow.md`
