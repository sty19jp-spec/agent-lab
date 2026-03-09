# Executor Policy (Layer5 Phase34)

## 1. Purpose
This document defines the operational Executor Policy for autonomous execution up to PR-ready state.

Completion condition for Executor work is **PR-ready**, not implementation-only completion.

## 2. Execution Policy
Executor (Codex CLI) may autonomously execute task-scoped work through PR preparation, including:
- workspace inspection
- workspace cleanup (weak cleanup policy only)
- branch normalization
- diff validation
- validator execution
- commit
- push
- PR creation
- PR metadata generation

Executor autonomy is bounded by task scope and policy constraints in this document.

## 3. PR-Ready Completion Condition
Executor is complete only when all of the following are true:
- task-scoped changes are implemented
- diff scope is compliant
- required validation is passing (or an explicitly allowed non-blocking condition is documented)
- branch state is normalized
- remote branch is pushed
- PR metadata is generated from factual execution evidence
- **Ready PR** is created (not Draft)

## 4. Workspace Cleanup Policy (Weak Cleanup)

### 4.1 Allowed Cleanup Targets
Executor may clean up only when ownership is clearly executor-owned and created during the current task:
- generated files created by the Executor during the current task
- temporary files created by the Executor during the current task
- executor-owned files
- reproducible transient artifacts created by the Executor during the current task

### 4.2 Forbidden Cleanup Targets
Executor must not clean up:
- unknown files
- user files
- credentials
- `.env`
- secrets
- private keys
- files with ambiguous ownership

### 4.3 Cleanup Decision Rule
- clearly executor-owned -> cleanup allowed
- clearly forbidden -> cleanup denied
- ambiguous ownership -> preserve and report

Human-authored or human-placed files are outside automatic cleanup scope by default.

## 5. Branch Normalization Policy

### 5.1 Branch Naming Rule
Executor branch naming must follow:
- `codex/phaseXX-<task-scope>`

Examples:
- `codex/phase34-executor-policy`
- `codex/phase34-validator-pr-readiness`

### 5.2 Pre-PR Branch Normalization Requirements
Before PR creation, Executor must ensure:
- explicit base branch is identified
- compliant head branch name is used
- remote branch is pushed
- no detached HEAD
- no local-only hidden state required for PR creation

## 6. Diff Scope Policy

### 6.1 Allowed Diff Scope
- task scope files
- minimal supporting files directly required by the task
- documentation directly required by the task
- validator or evidence-related files directly required by the task

### 6.2 Forbidden Diff Scope
- unrelated files
- opportunistic cleanup outside task scope
- unrelated refactor
- secrets or environment files
- another task's files

### 6.3 Stop Behavior
If unrelated diff cannot be safely isolated, Executor must stop and report the blocking condition before PR creation.

## 7. PR Metadata Generation Policy
Executor must automatically generate PR metadata from actual executed work.

PR must be created as **Ready PR** (not Draft PR).

PR body must include all sections below:
- Purpose
- Scope
- Changed files
- Validation
- Evidence
- Risk
- Non-goals

All PR metadata must be factual and derived from executed commands, produced artifacts, and actual diffs.
Fabricated validation claims are prohibited.

## 8. Validator Failure Policy
Required validator retry policy:
- retry up to **3 times**

Expected behavior:
1. validator fails
2. Executor applies scoped fix
3. rerun validator
4. repeat up to maximum 3 retries
5. if still failing, stop
6. do not create PR

PR creation is allowed only after required validation passes, or after a documented non-blocking condition explicitly allowed by policy.
If validation remains blocking after 3 retries, execution must stop before PR creation.

## 9. Codex CLI Operational Mapping
This policy maps to standard Codex CLI execution patterns.

Typical command examples:
- `git status`
- `git diff`
- `git add`
- `git commit`
- `git push`
- `gh pr create`

These are illustrative command patterns only.
This policy does not introduce scripts, workflow files, or repository automation changes.

## 10. Human Approval Boundary

### 10.1 Executor-Autonomous Operations
Executor may autonomously perform:
- `git status`
- `git diff`
- `git add`
- `git commit`
- `git push`
- PR creation
- task-scoped file edits
- validator execution
- branch normalization
- safe cleanup of executor-owned files

### 10.2 Human Approval Required
Human approval is required for:
- repository settings changes
- branch protection changes
- permissions changes
- secrets changes
- IAM changes
- destructive operations outside task-scoped reversible cleanup
- security-sensitive configuration changes

## 11. Phase34 Fixed Decisions (Normative)
The following are fixed by Phase34 and mandatory:
- completion condition = PR-ready
- PR type = Ready PR
- branch naming = `codex/phaseXX-<task-scope>`
- cleanup model = weak cleanup
- validator retry limit = 3
