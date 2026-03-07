# AI Handoff Stop Escalation Standard (Phase11)

## 1. Purpose
Phase11 defines a minimal, reusable standard for when an AI agent must stop execution and escalate during AI-to-AI handoff.
The goal is safe continuation of work without adding heavy governance.

## 2. Scope
This standard applies when work is transferred between AI agents in this repository, including:
- implementation handoff
- review handoff
- recovery handoff after blocked execution
- automation-driven reroute between agents

This standard is for stop/escalation behavior only.

## 3. Design Principles
- Minimal: only the fields needed to stop safely and continue work.
- Explicit: each stop must include a concrete reason and next action.
- Repository-first: prefer local evidence (files, logs, diffs, command output).
- Non-blocking by default: continue autonomously unless a stop trigger is reached.
- Human-in-the-loop only when required by risk or missing authority.

## 4. Stop Trigger Categories
An agent must stop and escalate when one or more of the following occurs:

- Scope ambiguity with behavior impact:
  - ambiguity would change implementation behavior, file scope, or acceptance criteria.
- Boundary conflict:
  - requested action conflicts with repository rules, AGENTS.md boundaries, or explicit task constraints.
- Risky or destructive operation:
  - irreversible delete/reset, credential mutation, or host/system risk outside allowed boundaries.
- Permission or authority block:
  - required approval/escalation is unavailable or denied.
- Missing critical context:
  - required spec, artifact, or acceptance condition cannot be inferred safely.
- Unrecoverable execution failure:
  - repeated retries fail and no safe fallback path remains.

## 5. Stop Severity
Use the lowest severity that preserves safety:

- S1 (Soft stop):
  - work can continue after one explicit clarification or missing input.
- S2 (Hard stop):
  - no safe continuation path exists without approval, policy exception, or new constraints.

## 6. Required Escalation Payload
When escalating, handoff must include:

- Task: the exact work unit being executed.
- Goal: expected outcome.
- Current status: done / in-progress / blocked.
- Stop reason: mapped to one trigger category.
- Severity: S1 or S2.
- Evidence: concrete file paths, command results, or error messages.
- What was attempted: retries or fallback actions already performed.
- Requested decision: exact approval/clarification needed.
- Safe next step: smallest valid continuation step after resolution.

## 7. Handoff Message Template
```md
# STOP Escalation Handoff

## Task

## Goal

## Current status

## Stop reason
- Category:
- Severity: S1 | S2

## Evidence
- Files:
- Commands:
- Errors:

## What was attempted

## Requested decision

## Safe next step
```

## 8. Escalation Flow
1. Detect stop trigger.
2. Attempt safe local recovery within current scope.
3. If unresolved, emit escalation payload.
4. Transfer control to next agent or human approver.
5. Resume only after requested decision is explicit.

## 9. Non-Goals
This standard does not define:
- broad approval governance design
- branching strategy changes
- CI policy redesign
- credential architecture changes
- non-repository organizational workflows

## 10. Done Condition
This standard is complete when:
- stop triggers are explicit and actionable.
- severity levels are defined.
- escalation payload fields are standardized.
- handoff template is reusable across agents.
- guidance remains concise and practical.

## 11. Relationship to Other Phases
- Phase8: defines the task assignment contract.
- Phase9: defines output structure and handoff formatting baseline.
- Phase10: defines execution boundary and guardrails.
- Phase11 (this doc): defines when execution must stop and how escalation is handed off safely.

## 12. Post-Merge Local Sync Rule

After any Pull Request is merged, the executor or human must synchronize the local main branch before starting the next task.

Default command:

git switch main && git pull --ff-only

Rationale:
GitHub-side merges do not guarantee that local environments are synchronized.

Execution rule:
- No new task execution should begin until local main is confirmed up-to-date.
- Executors should propose or perform local sync before starting a new task if merge occurred outside the current environment.

## 13. Retry Ceiling and No Silent Loop Rule

Agents must not continue retrying indefinitely.

If the same or materially similar failure occurs repeatedly without producing new evidence, the agent must stop and escalate.

Minimum rule:
- after 2 repeated failed retries with no new evidence, emit a blocked execution report
- do not continue silent looping
- include the last known error, attempted fixes, and the exact next required decision
