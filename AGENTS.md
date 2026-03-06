# AGENTS.md (Phase6)

## Purpose
Minimal execution guide for AI agents working in this repository.
Keep operations practical, PR-based, and consistent with existing behavior.

## Source of Truth
- GitHub `main` is the source of truth.
- Local files and external systems are working copies.

## Working Model
- AI agent: implementation, repository inspection, automation, and CLI execution.
- Human: approvals, merge decisions, and GUI-only operations.
- Keep changes small, reviewable, and scoped to the task.

## Branch Workflow
1. Branch from latest `main`.
2. Use a short-lived feature branch per task.
3. Do not work directly on `main`.
4. Rebase or merge `main` as needed to resolve drift.

## PR Workflow
1. Make the smallest logical change set.
2. Verify with `git status` and `git diff`.
3. Commit with a clear message.
4. Push branch and open PR to `main`.
5. Human performs final review/merge.

Notes:
- Use current repository protections and PR process as-is.
- Do not add new governance mechanisms in this guide.

## Documentation Map
- Overview: `README.md`
- AI PR runbook: `docs/RUNBOOK-ai-pr-workflow.md`
- Drive Sync runbook: `docs/RUNBOOK-drive-sync.md`
- Drive history retention runbook: `runbooks/drive-history-retention.md`
- Architecture decision records: `docs/ADR-001-drive-sync-architecture.md`, `runbooks/adr/`

## Editing Boundaries
- Allowed: repository files required for the assigned task.
- Not allowed unless explicitly requested:
  - Secrets/credentials handling changes
  - Unrelated refactors or broad formatting-only edits
  - Changes to Drive Sync architecture docs for this task
  - Repository governance expansion (CODEOWNERS, required approvals, status checks)

## Output Expectations
- Show modified files and diff before handoff when requested.
- Keep notes concise: what changed, why, and any follow-up required.
- Do not commit or push unless explicitly instructed.
