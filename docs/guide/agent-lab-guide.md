# Agent-Lab Guide

## 1. What agent-lab is

`agent-lab` is a repository-centered AI governance environment for controlled software execution by an AI executor.

In practical terms, it provides:

- a task launcher for starting work from canonical repository state
- a validator-aware Pull Request workflow
- runtime evidence for audit and debugging
- a merge-only governance path where final merge authority stays with a human

It is not a general autonomous platform that can safely act outside repository governance. Its center of gravity is the repository, the Pull Request, and the merge gate.

## 2. Snapshot status

**This guide describes agent-lab at the TrackA / Layer5 completed state.**

At this snapshot point, the repository has:

- a working PR-centered autonomous execution path
- local pre-validation aligned with the CI PR validator
- execution evidence and provenance support
- a stage-aware executor runtime
- bounded failure recovery
- reliability controls for safer re-execution

This guide is intentionally a snapshot. Development may continue after this point, but later work is not documented here.

## 3. Why this repository exists

The repository exists to make AI-assisted repository work governable.

The core problem it addresses is not just "how to let an AI edit files", but "how to let an AI work while preserving reviewability, auditability, and merge control".

The repository therefore treats:

- GitHub as the source of truth
- Pull Requests as the normal delivery path
- validators as merge-gate controls
- humans as final merge decision makers

## 4. Core execution model

The baseline execution model is:

Human
↓
ChatGPT (Architect / Auditor)
↓
AI Executor
↓
Pull Request
↓
Validator Chain
↓
Branch Protection
↓
Human Merge

This means:

- ChatGPT is not the repository executor in the normal path
- the AI Executor performs the implementation work
- all normal delivery still goes through a Pull Request
- validator results and branch protection gate the merge
- the human does not disappear from the loop; the human remains the final merge authority

## 5. Governance model

The repository uses a **merge-only execution model**.

Normal delivery is:

AI Executor -> feature branch -> Pull Request -> validator checks -> human merge -> `main`

The governance model depends on several linked controls:

- branch discipline for executor work
- the executor policy and executor contract that define PR-ready behavior
- required PR metadata
- local pre-validation before PR creation
- CI validator execution
- branch protection on `main`

This keeps the execution path reviewable and makes it harder to bypass the intended merge gate by accident.

## 6. Repository structure overview

At a high level:

- `docs/` contains governance, runbooks, validator specifications, and design references
- `scripts/` contains launcher and runtime shell scripts
- `tools/` contains validator implementations and related repository tools
- `examples/` contains example evidence data and related fixtures
- `registry/` contains registry-oriented repository data
- `runtime/`, `.runtime/`, and `logs/` hold runtime-oriented or generated state during operation
- `bundle/`, `task/`, and `workspace/` hold task-oriented or structured working assets

See `docs/guide/repository-map.md` for a more direct directory-by-directory map.

## 7. Main runtime / operator workflow

The current operator-facing flow is:

`make codex-task`
↓
main sync
↓
task branch creation
↓
executor run
↓
PR body render
↓
pre-validation
↓
PR creation
↓
validator pass
↓
human merge

This flow matters because the repository is designed so that the PR body used for local validation is the same PR body later submitted to GitHub.

That reduces drift between local checks and GitHub validator results.

## 8. Validator and merge gate model

The repository uses a validator chain rather than informal review alone.

Important concepts:

- **Executor policy / executor contract**
  - define the executor's operating boundaries, PR-ready completion condition, and factual PR metadata discipline
- **PR Readiness Validator**
  - checks branch naming, PR metadata completeness, evidence references, completion token, and diff scope alignment
- **Validator Chain**
  - orchestrates the validator path and provides the authoritative merge-gate result
- **Execution evidence / provenance**
  - records runtime artifacts and evidence references so execution can be audited instead of treated as a black box
- **Branch Protection**
  - makes the required validator result part of merge control on `main`

In normal operation, a PR is mergeable only after the validator path passes and a human chooses to merge it.

## 9. Setup and first-use orientation

A new reader should think of the repository in this order:

1. Read the governance model first.
2. Understand the PR-ready flow.
3. Understand the executor entrypoint.
4. Understand what evidence and validator output represent.
5. Only then start running task work.

The most practical entrypoints are:

- `Makefile`
- `scripts/codex-task.sh`
- `scripts/pre-validate-pr.sh`
- `docs/runbooks/pr-ready-flow.md`
- `docs/pr-readiness-validator.md`

## 10. Daily use flow

A normal working cycle looks like this:

1. start from the latest repository state
2. launch a task branch through the task launcher
3. make a small scoped change
4. inspect `git status` and the actual diff
5. commit the scoped change
6. render PR metadata to a local file
7. run local pre-validation on that exact file
8. open a Ready PR from that same validated file
9. wait for validator results
10. hand final merge judgment to a human

This is intentionally stricter than "edit files and push" because the repository is designed around controlled AI execution rather than unconstrained automation.

## 11. Safety boundaries and human responsibilities

The human role is intentionally narrow:

- merge judgment
- exception approval when genuinely needed
- GUI-only operations where repository controls require it

The AI Executor is expected to do the normal repository work:

- inspect files
- implement changes
- generate factual PR metadata
- validate locally
- push a branch
- open the PR

The human is not expected to run normal CLI steps on behalf of the executor in ordinary operation.

## 12. What is intentionally out of scope

This repository snapshot is not trying to be:

- a general distributed agent platform
- a direct-push automation system
- a merge-bypass workflow
- a dashboard or notification platform
- a replacement for human merge authority

It is also not a promise that every future automation idea belongs inside the current repository runtime.

## 13. What continues after this snapshot

Development continues after this snapshot, but this guide does not try to document that future work.

The important point for a new reader is that, at the TrackA Layer5 completed state, the repository already has its core governance model in place:

- PR-centered execution
- validator-aware delivery
- evidence and provenance support
- bounded recovery and reliability controls
- human-controlled merge completion
