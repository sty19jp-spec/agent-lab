# AI Work Contract Standard (Phase8)

## 1. Purpose
Phase8 defines a standard request format for assigning one unit of work to AI agents (for example, Codex and Claude Code).
The goal is consistent, reusable task instructions with lightweight governance.

This standard is part of Layer2 (AI work standardization) and assumes:
- GitHub `main` is the source of truth.
- Local workspace is a working copy.
- Execution baseline is WSL Ubuntu.

## 2. Design Principles
- Keep contracts small, explicit, and execution-ready.
- Prefer scope clarity over process overhead.
- Separate execution contract (Phase8) from output formatting standards (Phase9).
- Keep agent-agnostic wording so the same contract works for Codex and Claude Code.
- Avoid heavy governance fields that slow execution.

## 3. Core Contract Fields
The standard contract structure is:
- Task ID
- Goal
- Non-Goals
- Inputs
- Constraints
- Done Condition
- Review Points
- Security Boundary

However, the true minimal execution core is:
- Goal
- Non-Goals
- Inputs
- Constraints
- Done Condition
- Security Boundary

These six fields are sufficient to run work safely and consistently.

## 4. Recommended Operational Fields
These fields are recommended for operations but are not part of the minimal execution core:
- Task ID
  - Useful for traceability across issues, branches, PRs, and handoff notes.
- Review Points
  - Useful for faster human/AI review and quality checks at handoff.

## 5. Optional Fields
Optional fields may be added only when useful for a specific task, for example:
- Context
- Assumptions
- Stop Conditions
- References

Rules for optional fields:
- They must not duplicate core fields.
- They must not introduce heavy governance.
- Keep them short and task-specific.

Do not add mandatory governance fields such as Priority, Deadline, Approval Flow, ticket-routing fields, or agent-specific branching instructions.

Note on output granularity:
- If a task needs strict output detail (for example, summary depth, diff detail, or test evidence), specify it inside `Constraints`.
- Do not add a new mandatory output field in Phase8.

## 6. Minimal Template
```md
Goal:
Non-Goals:
Inputs:
Constraints:
Done Condition:
Security Boundary:
```

## 7. Example
```md
Task ID: P8-EXAMPLE-001
Goal:
- Draft `docs/ai-work-contract.md` for Phase8 with a minimal, reusable structure.

Non-Goals:
- No implementation of skills, MCP, automations, or multi-agent routing.
- No edits outside `docs/ai-work-contract.md`.

Inputs:
- `AGENTS.md`
- `docs/AI-task-protocol.md`
- Layer2 roadmap assumptions for Phase8.

Constraints:
- Design/documentation only.
- Keep text concise and practical.
- Keep governance lightweight.
- Specify required output granularity here when needed.

Done Condition:
- `docs/ai-work-contract.md` exists with agreed sections and field definitions.
- Content clearly separates core fields from recommended fields.

Review Points:
- No over-engineering.
- Clear boundary between Phase8 and Phase9.
- Reusable by Codex and Claude Code.
- Consistent with GitHub-as-source-of-truth.

Security Boundary:
- No secrets in docs.
- No credential handling changes.
- No external system mutations.
```

## 8. Relationship to Phase9 / Phase10 / Phase11
- Phase8 (this doc): Defines the work assignment contract itself.
- Phase9: Defines output/docs formatting and handoff standards. Keep output granularity rules there; in Phase8, only add task-specific output detail under `Constraints`.
- Phase10: Handles automation and execution integration concerns.
- Phase11: Handles advanced orchestration such as multi-agent coordination.

Phase8 intentionally stays minimal so later phases can evolve without changing the core work contract.
