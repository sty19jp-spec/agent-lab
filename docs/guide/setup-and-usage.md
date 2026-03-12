# Setup and Usage

## Prerequisites

At the TrackA Layer5 completed snapshot, practical use assumes:

- Git
- GitHub access appropriate for branch push and PR creation
- the repository checked out locally
- Codex CLI available in the shell environment used for executor work
- the repository’s existing scripts and validator tooling available from the checked-out working copy

Depending on the environment, Node and Python may also be required because the repository contains shell scripts and validator tooling that rely on them.

## Repository clone / inspection

Typical first steps are:

1. clone the repository
2. inspect the top-level layout
3. read the key governance and runbook documents
4. inspect `Makefile` and `scripts/`

Useful orientation files:

- `README.md`
- `docs/governance/merge-only-model.md`
- `docs/runbooks/pr-ready-flow.md`
- `docs/pr-readiness-validator.md`
- `docs/executor-contract.md`

Before starting task work, confirm you are operating on a clean repository state.

## Main entrypoint for task start

The main executor entrypoint is:

```bash
make codex-task TASK=<task-name>
```

This launcher is designed to:

- validate the task argument
- bootstrap the executor CLI environment
- enforce clean-state stop conditions
- sync local `main` to canonical `origin/main`
- create and switch to a task branch
- launch the executor runtime

The repository expects task work to begin from this controlled path rather than from ad hoc branch handling.

## Branch / task workflow

The normal branch flow is:

1. start from the latest `main`
2. create a compliant executor branch
3. keep the diff scoped to the current task
4. commit the scoped change
5. push the branch
6. open a Ready PR

Branch discipline matters because branch naming is validated and non-compliant names are expected to fail the repository’s PR readiness checks.

## PR creation flow at a high level

The repository’s validator-aware PR creation flow is:

1. implement the task
2. inspect the actual diff
3. render the PR body to a local file
4. run local pre-validation on that exact file
5. create the PR from that same file

The relevant script is:

```bash
bash scripts/pre-validate-pr.sh --body-file <path> --validate-only
```

Then, when ready:

```bash
bash scripts/pre-validate-pr.sh --body-file <path> --title "<pr title>"
```

The important design rule is that the validated PR body file and the submitted PR body file must be the same artifact.

## Daily workflow

A practical daily flow is:

1. confirm repository status with `git status`
2. start work from the task launcher
3. make a narrow, task-scoped change
4. inspect `git diff --stat` and `git diff`
5. commit only the intended files
6. render PR metadata
7. run local pre-validation
8. create the PR
9. watch validator results
10. stop at PR-ready state and hand off for human merge judgment

This repository assumes the executor should carry work through implementation, validation, push, and PR creation rather than stopping early at code-only completion.

## How to read validator results

There are two levels to look for:

- the PR-specific readiness result
- the overall validator chain result

Operationally:

- a passing PR readiness result means the PR body, branch naming, evidence references, and diff scope satisfy the repository’s rules
- a passing validator chain means the merge-gate path is satisfied

If validation fails, inspect:

- the actual changed files
- the exact PR body that was submitted
- the validator output
- the related runbooks and validator docs in `docs/`

Do not treat a local draft description as authoritative if it differs from the file actually submitted to GitHub.

## Common operator mistakes to avoid

- starting work from a dirty repository
- using a non-compliant branch name
- changing more files than the task actually requires
- writing PR metadata before checking the real diff
- validating one PR body and submitting a different one
- listing commands as evidence instead of using repository-visible evidence
- trying to use direct push as a normal path
- assuming merge is complete once code is written but before the PR is validator-clean
