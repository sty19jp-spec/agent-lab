# AI Task Unit Standard (Phase12)

## 1. Purpose
Phase12 defines the minimum practical unit of work for AI executors in this repository.
This standard is repository-first, PR-based, and optimized for Codex app for Windows as the primary executor.

## 2. Effective Rule Source
For Phase12 execution, repository-local standards are the only effective rule source.
Do not depend on docs/OPERATING-RULES-execution unless that file is added to this repository later.

Current alignment baseline:
- docs/AI-task-protocol.md
- docs/ai-work-contract.md (Phase8)
- docs/ai-output-standard.md (Phase9)
- docs/ai-execution-boundary.md (Phase10)
- docs/ai-handoff-stop-escalation.md (Phase11)

## 3. Design Principles
- Lightweight: minimum rules needed to execute safely and review quickly.
- Practical: rules must be directly usable in daily repository work.
- Repository-first: task state is judged from branches, diffs, files, and PRs.
- Executor-friendly: clear default path with narrow exceptions.
- Autonomy-first: executors proceed without waiting, unless stop triggers are reached.

## 4. Task Definition
A task unit is one smallest reviewable outcome that can be completed and validated within repository boundaries.

Minimum task definition fields:
- Goal
- Scope (files or directories in scope)
- Constraints (what not to change)
- Done condition (repository-visible)

## 5. Default Mapping Rule
Default rule:
- 1 task = 1 branch = 1 PR

Rationale:
- preserves clear traceability
- keeps review and rollback simple
- keeps handoff and escalation small

Exception rule:
- multiple tasks may share one branch/PR only when they are inseparable and produce one atomic outcome.
- if tasks can be reviewed or reverted independently, they must be split.

## 6. Task Size Expectation
Default rule:
- one task should produce one logical change set that a reviewer can understand quickly from one PR.
- a task should stay narrow enough to hand off safely without hidden context.

Practical size signals for one task:
- one primary goal
- one dominant change intent
- limited file set related to that intent
- no mixed unrelated concerns

Exception rule:
- if the change introduces a second independent goal, treat it as another task.

## 7. Task Boundary Rules
Default rule:
- edit only files needed for the stated goal.
- avoid unrelated refactor, formatting sweep, or governance/process expansion.

Exception rule:
- minimal adjacent edits are allowed only when required to keep the repository working (for example, broken reference fix caused by the task).

## 8. Task Type Handling
Default rule:
- docs task, code task, and fix task follow the same task-unit model and mapping (1:1:1).

Task-specific emphasis:
- docs task: done is document clarity and repository consistency.
- code task: done is behavior change plus basic validation evidence.
- fix task: done is reproducible issue resolution plus regression guard.

Exception rule:
- do not create separate handling frameworks per task type; only adjust done evidence depth.

## 9. Task Start Condition
A task starts when all are true:
- branch exists from up-to-date main
- goal/scope/constraints/done condition are explicit
- required inputs are present in repository or provided artifacts
- no unresolved stop trigger from Phase11 rules

## 10. Task Done Condition
Minimum done condition (all required):
- scoped change is implemented
- diff is reviewable and limited to task boundary
- repository-visible evidence supports completion
- handoff-ready summary can be produced without hidden context

Repository-visible evidence examples:
- modified files and diff
- test or validation output when relevant
- updated documentation when behavior/usage changed

## 11. Task Split Condition
Split immediately when one or more occurs:
- second independent goal appears
- file scope expands beyond original boundary in a non-adjacent area
- review complexity prevents quick understanding as one PR
- stop/escalation payload would become multi-issue and ambiguous
- risk profile changes (for example, doc-only to infra-impacting change)

## 12. Handoff Compatibility Rule
Task units must remain compatible with stop/escalation/handoff standards.

Default rule:
- each task must be handoffable with one clear status: done, in-progress, or blocked.
- escalation payload must reference one task goal and one decision request.

Exception rule:
- if a handoff needs multiple independent decision requests, split the task first.

## 13. Acceptable vs Non-Acceptable Task Units
Acceptable:
- update one runbook section and linked references for one operational policy change.
- fix one script failure mode and add targeted validation evidence.
- add one new standard doc file aligned with existing Layer2 rules.

Non-acceptable:
- combine runbook rewrite, CI redesign, and secret handling updates in one task.
- mix unrelated bug fixes across different subsystems in one PR.
- include broad repository formatting changes with a feature change.

## 14. Relationship to Other Standards
- Phase8 (ai-work-contract): defines request contract fields.
- Phase9 (ai-output-standard): defines output/handoff formatting.
- Phase10 (ai-execution-boundary): defines allowed vs prohibited execution boundary.
- Phase11 (ai-handoff-stop-escalation): defines stop triggers and escalation payload.
- Phase12 (this doc): defines the practical work unit size and mapping model.
