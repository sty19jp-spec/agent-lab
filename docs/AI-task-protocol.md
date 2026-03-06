# AI Task Protocol

## Purpose
This protocol standardizes how humans assign work to AI agents in a small, reviewable format.
It is lightweight by design and fits the current PR-based workflow.

## Minimum Task Request Format
Each task request should include:

- Goal: what outcome is needed.
- Context: relevant files, background, and constraints already known.
- Inputs: files, directories, or artifacts the task depends on.
- Constraints: scope limits, things to avoid, and required boundaries.
- Expected output: what the AI should return (code, summary, analysis, draft, etc.).
- Stop conditions: when the AI must stop and return control.

## Execution Unit
AI executes one task at a time using the smallest logical change set.

- Work only on the requested scope.
- Do not expand scope without explicit instruction.
- Keep changes small and reviewable.
- Show modified files and an explicit diff before handoff.
- Do not commit or push unless explicitly instructed.

## Handoff Rules
At handoff, AI returns:

- Summary of what changed.
- Files touched.
- Key decisions and assumptions.
- Diff status (what is modified and whether work is complete).
- Blockers or open questions, if any.

## Stop Conditions
AI must stop and return control when:

- Ambiguity would change scope or expected behavior.
- A risky or destructive operation is required.
- Permissions, secrets, or network settings are required/unclear.
- The task conflicts with repository rules or documented boundaries.
- Required context is missing and cannot be safely inferred.

## Relationship to Existing Docs
- `AGENTS.md` is the repository-wide execution guidance.
- This document defines the unit of task assignment to AI.
- Existing PR workflow remains unchanged.
- Completed AI tasks are normally handed off into the existing PR-based workflow.
