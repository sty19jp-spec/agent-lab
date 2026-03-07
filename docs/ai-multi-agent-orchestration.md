# AI Multi-Agent Orchestration (Phase15)

## 1. Purpose
Define the minimum multi-agent orchestration model for this repository so multiple AI agents can collaborate safely, simply, and auditablely while preserving GitHub `main` as the single source of truth.

## 2. Scope
This document defines:
- the minimum role set (Architect, Executor, Auditor)
- handoff and context transfer rules between those roles
- task routing for design, execution, audit, retry, and review
- failure handling and escalation boundaries
- repository-visible evidence requirements for traceability

This document applies to repository work executed through branch + PR flow.

## 3. Non-Goals
- No workflow redesign.
- No CI policy change.
- No IAM or secrets model change.
- No new runtime infrastructure or external ticketing system.
- No autonomous agent mesh or dynamic role explosion.
- No replacement of human approvals where already required.

## 4. Agent Roles
### 4.1 Architect Agent
Responsibilities:
- define task intent, scope, constraints, and done condition
- produce execution-ready guidance when task behavior is ambiguous
- decide split/merge of task units when complexity grows

Must not:
- perform primary implementation
- approve its own design quality as final audit
- bypass repository constraints or operating rules

### 4.2 Executor Agent
Responsibilities:
- implement scoped repository changes
- run relevant checks/validation
- produce branch/commit/PR artifacts and handoff-ready status

Must not:
- redefine architecture without explicit Architect handback
- self-certify final compliance when independent audit is required
- claim completion without repository-visible evidence

### 4.3 Auditor Agent
Responsibilities:
- verify alignment with scope, constraints, and standards
- classify findings (pass / changes required / blocked)
- confirm evidence sufficiency for completion claim

Must not:
- rewrite task scope silently
- become primary implementer except explicitly assigned retry path
- override human approval boundaries

## 5. Orchestration Model
Baseline chain:

Human
-> Architect Agent
-> Executor Agent
-> Auditor Agent
-> Repository (PR review/merge)

Minimum orchestration rules:
1. One active owner per task stage (no shared ambiguous ownership).
2. Architect produces or confirms execution contract before implementation.
3. Executor performs implementation and evidence capture.
4. Auditor evaluates output against contract and standards.
5. Any reopen loops route back to the minimum prior stage only (Audit -> Execute or Execute -> Architect), not full-mesh broadcast.

## 6. Task Routing
Default routing by task class:
- architecture/design ambiguity -> Architect
- implementation/edit/test execution -> Executor
- compliance/evidence/review quality gate -> Auditor
- execution retry after fixable failure -> Executor
- retry requiring scope reinterpretation -> Architect, then Executor
- final review verdict for completion claim -> Auditor

Routing decision rule:
1. Route by primary uncertainty:
   - "what to build" uncertainty -> Architect
   - "how to change repo safely" uncertainty -> Executor
   - "is this acceptable and evidenced" uncertainty -> Auditor
2. If uncertainty spans multiple categories, split into sequential handoffs.
3. If no safe route is clear, stop and escalate to Human.

## 7. Context Transfer
Every agent-to-agent handoff must include a compact, explicit payload:
- Task: single goal statement
- Scope: files/directories in scope
- Constraints: explicit "must not change"
- Status: done / in-progress / blocked
- Evidence: branch, commit(s), PR link (if exists), check results
- Open Decisions: exact unresolved questions
- Next Owner: Architect | Executor | Auditor

Transfer rules:
1. Repository artifacts are primary context; chat memory is secondary.
2. Handoff text must reference concrete file paths and/or PR artifacts.
3. Missing any required field makes handoff invalid and returns to sender for correction.
4. Next Owner field is mandatory to prevent ambiguous responsibility.

## 8. Failure Handling
### 8.1 Agent failure
- If an agent cannot continue, emit blocked handoff payload with last valid state.
- Reassign only the failed stage to another agent in the same role.

### 8.2 Execution error
- Executor retries with small, evidence-backed fix attempts.
- After repeated failure without new evidence, stop and escalate using repository-visible error context.

### 8.3 Context loss
- Recover from repository artifacts first (branch, diff, commits, PR).
- If recovery cannot restore safe scope/constraints, route to Architect for contract re-baseline.

### 8.4 Invalid handoff
- Receiver rejects handoff when required fields are missing or contradictory.
- Work does not proceed until corrected handoff is provided.

Stop and escalate conditions:
- boundary conflict with operating rules
- missing authority/approval
- unresolved scope ambiguity with behavioral impact
- repeated failures with no new evidence

## 9. Evidence Model
Minimum evidence remains repository-visible and PR-centered:
1. scoped change in tracked files
2. commit(s) on task branch
3. PR targeting `main`
4. concise PR description of goal/result
5. explicit note of verified vs not verified

Role-specific evidence:
- Architect: task contract and routing decision captured in PR or linked doc update
- Executor: diff + validation output summary
- Auditor: pass/fail decision and findings in PR comments or review summary

Non-compliant evidence:
- completion claims supported only by chat text
- hidden local notes without repository linkage

## 10. Governance Alignment
This model preserves existing repository governance:
- GitHub `main` remains the single source of truth.
- Design/execution separation is explicit (Architect vs Executor).
- Audit is separated from primary execution (Auditor role).
- Human remains approver for merge and exceptional escalation.
- No changes to CI, IAM, secrets, or external connectivity.
- No expansion into heavyweight governance or process frameworks.

## 11. Example Flows
### 11.1 Standard flow (pass)
1. Architect defines scoped contract.
2. Executor implements and opens PR with evidence.
3. Auditor reviews, confirms alignment, marks pass.
4. Human performs final merge decision.

### 11.2 Retry flow (execution issue)
1. Auditor flags implementation defect.
2. Executor receives defect-focused handoff and applies fix.
3. Auditor re-checks only affected scope and evidence.
4. Human merges when criteria are satisfied.

### 11.3 Escalation flow (scope ambiguity)
1. Executor detects behavior-impacting ambiguity.
2. Executor stops and routes back to Architect with evidence.
3. Architect clarifies contract; Executor resumes.
4. Auditor verifies against updated contract.

## 12. Decision Summary
- Start with exactly three core roles: Architect, Executor, Auditor.
- Use linear stage ownership with controlled back-routing, not mesh orchestration.
- Require structured handoff payloads to keep ownership explicit.
- Keep failures recoverable through repository-first context.
- Keep completion evidence lightweight, PR-based, and auditable.
- Preserve current operating boundaries and human approval model.
