# AI Task Routing and Execution Graph (Phase18)

## 1. Purpose
Define a minimal, deterministic execution graph for multi-agent task delivery in this repository.
The graph fixes how tasks are routed, retried, stopped, escalated, and evidenced.

## 2. Scope
This standard defines:
- task classes used in multi-agent execution
- routing between Architect, Executor, and Auditor
- fixed execution sequence and controlled retry paths
- stop conditions and human escalation points
- evidence propagation across graph nodes

This standard applies to branch + PR based repository work targeting main.

## 3. Non-Goals
- workflow redesign or CI redesign
- IAM, secrets, or infrastructure policy redesign
- dynamic uncontrolled graph expansion
- agent swarm routing
- autonomous role expansion beyond Architect / Executor / Auditor

## 4. Task Model
Minimum task classes:
- architecture task: clarify intent, scope, constraints, done condition
- implementation task: apply repository changes and validation
- audit task: verify scope, constraints, and evidence sufficiency
- retry task: corrective re-execution after a failed implementation or audit
- escalation task: blocked-state transfer to Human with explicit decision request

Optional minimal class:
- merge-readiness task: final audit check that PR evidence is complete for human merge judgment

## 5. Task Routing Model
Routing rule by primary uncertainty:
- architecture task -> Architect
- implementation task -> Executor
- audit task -> Auditor
- retry task -> Executor by default; route to Architect first when failure cause is spec ambiguity
- escalation task -> Human (not an agent)

Role constraints:
- Architect does not perform primary implementation
- Executor does not self-approve final audit
- Auditor does not silently redefine scope

## 6. Execution Graph
Base deterministic graph:

Human request -> Architect -> Executor -> Auditor -> Human merge judgment

Static node set:
- N0: Human request/input
- N1: Architect contract lock
- N2: Executor execution
- N3: Auditor decision
- N4: Human merge judgment / close

Allowed transitions:
- N0 -> N1
- N1 -> N2
- N2 -> N3
- N3 (pass) -> N4
- N3 (changes required) -> N2
- N2 (spec ambiguity) -> N1
- N2/N3 (blocked) -> Human escalation

Parallel execution policy:
- Allowed only inside N2 when tasks are independent, same goal, and no file-level dependency conflict
- Each parallel branch must have fixed task IDs and deterministic join order (lexicographic task ID)
- Join before N3; no direct parallel branch bypass to audit completion

Parallel execution prohibited when:
- branches modify overlapping files or shared acceptance criteria
- ordering affects behavior, evidence, or audit verdict
- branch split would produce ambiguous ownership or ambiguous done condition

Determinism controls:
- fixed role set and fixed node set
- explicit Next Owner in every handoff
- retry ceiling and fixed back-edges only
- repository artifacts (files, commits, PR) as primary state source

## 7. Task Dependency
Minimum dependency chain:
1. Spec/design decision locked (N1 output)
2. Execution completed against locked contract (N2 output)
3. Audit completed against same contract and evidence (N3 output)
4. Completion evidence confirmed merge-ready (N3 -> N4 gate)

Dependency rules:
- no execution before contract lock
- no audit pass without execution evidence
- no completion claim without PR-level evidence
- if dependency is unresolved, route to stop/escalation path

## 8. Retry Graph
Retry routing is fixed by failure type:
- Executor fail (implementation defect, command failure): N2 -> retry task (Executor) -> N3
- Auditor fail (changes required): N3 -> retry task (Executor) -> N3
- Missing input / ambiguous task: N2 or N3 -> Architect clarification (N1) -> N2
- Repeated failure: after 2 retries without new evidence -> escalation task -> Human

Retry rules:
- one retry unit addresses one failure cluster only
- each retry must add new evidence (new commit, updated result summary, or explicit failed-check delta)
- silent looping is prohibited

## 9. Stop Conditions
Automatic execution must stop when any of the following is true:
- input is ambiguous and changes behavior or scope
- operation requires explicit approval under active constraints
- destructive action is requested (irreversible delete/reset, major rollback, data loss risk)
- required dependency is unresolved
- retry ceiling reached
- evidence is insufficient for next handoff/audit gate

Stop output must include: stop reason, last valid node, attempted actions, required decision.

## 10. Human Escalation
Escalate to Human when any of the following applies:
- permissions, secrets, IAM, or network exposure decision is needed
- destructive change requires explicit human judgment
- policy conflict with AGENTS.md or repository standards
- spec conflict between task contract and existing architecture decisions
- repeated failure reached retry ceiling
- final merge judgment is required

Escalation payload minimum:
- task and goal
- current node and status
- concrete evidence (files, commits, PR/check state)
- exact decision request
- smallest safe next step after decision

## 11. Evidence Propagation
Evidence generation by node:
- N1 (Architect): locked task contract (goal/scope/constraints/done condition/routing decision)
- N2 (Executor): changed files, commit(s), validation notes, retry notes when applicable
- N3 (Auditor): pass/fail decision, findings, evidence sufficiency verdict
- N4 (Human): merge decision and closure state

Handoff evidence package (mandatory each edge):
- task ID or task label
- next owner
- changed files list (if any)
- commit hash list (if any)
- PR URL/status (if exists)
- result summary (implemented, verified, blocked, changes required)
- open risks or unresolved decisions

PR/commit/changed-files handling:
- completion claim requires branch commit(s) + PR targeting main
- changed files must stay within declared scope
- audit checks that claimed outcome maps directly to diff and PR summary

## 12. Example Execution
Example A (standard pass):
1. Architect defines contract for docs/ai-execution-graph.md.
2. Executor creates doc and commits on feature branch.
3. Auditor verifies required sections, scope limits, and evidence completeness.
4. Human reviews PR and decides merge.

Example B (audit fail then retry):
1. Auditor finds missing Retry Graph section and marks changes required.
2. Retry task routes to Executor.
3. Executor adds missing section, commits delta, updates PR summary.
4. Auditor re-checks only affected scope and marks pass.
5. Human performs merge judgment.

Optional controlled parallel example (inside N2):
1. Executor splits implementation into T1 (content draft) and T2 (example scenarios) with non-overlapping sections.
2. T1 and T2 run in parallel under fixed IDs.
3. Results are joined in deterministic order (T1 then T2) before audit.
4. Auditor evaluates joined artifact once.

## 13. Decision Summary
- Use a fixed graph with three agent roles and human escalation endpoint.
- Route tasks by uncertainty type, not by ad hoc agent choice.
- Allow parallelism only as controlled Executor-internal branches with deterministic join.
- Enforce fixed retry back-edges with retry ceiling and no silent loop.
- Treat evidence propagation as mandatory edge data for every handoff.
- Preserve PR-based, repository-visible, lightweight governance-aligned execution.
