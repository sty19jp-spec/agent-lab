# AI Automation Introduction Architecture

## 1. Purpose
Define a safe, minimal, repository-aware, and auditable architecture for introducing AI automation in `agent-lab` under the existing approval model.

## 2. Scope
This document covers automation design boundaries for repository and CI-facing operations in this project.
It applies to architecture, audit, and execution flow definitions only.

## 3. Non-Goals
- Implementing new workflows or CI pipelines.
- Modifying GitHub Actions behavior.
- Changing secrets, IAM, or external service connectivity.
- Introducing new governance frameworks beyond current repository rules.

## 4. Definitions
- Automation: repeatable AI-assisted operation executed from a defined trigger.
- Trigger: event or schedule that starts an automation flow.
- Evidence: repository-visible proof of what ran and what changed.
- Approval boundary: operations that require explicit human approval before execution.
- Execution boundary: hard limits that classify operations as allowed, approval-required, or prohibited.

## 5. Design Principles
- Safe: reject risky operations that can expose credentials or damage systems.
- Minimal: automate only the smallest unit that improves reliability or speed.
- Repository-aware: align with repository structure, branch/PR workflow, and documented constraints.
- Auditable: produce clear evidence trails in commits, logs, and PR metadata.
- Compatible with approval model: preserve human control for sensitive or policy-impacting actions.

## 6. Automation Categories
- Monitoring automation: passive checks and status observation.
- Scheduled checks automation: periodic health, drift, or policy checks.
- CI status automation: pipeline state collection and reporting.
- Workflow operation automation: controlled reruns and related operational support.
- Change automation (approval-required): config/repository settings updates after explicit approval.

## 7. Trigger Model
- Manual trigger: human requests execution for a specific task.
- Event trigger: repository or CI state change starts a check/report flow.
- Schedule trigger: time-based periodic checks run at defined intervals.
- Escalation trigger: automation detects approval-required or prohibited intent and stops for human decision.

## 8. Execution Boundary
Execution model:

Human  
Å´  
ChatGPT (architecture / audit)  
Å´  
Codex (execution)  
Å´  
Repository / CI

Boundary intent:
- ChatGPT defines architecture and auditing expectations.
- Codex performs scoped execution within repository/CI limits.
- Execution remains design-compatible with current repository protections.

## 9. Approval Boundary
Human approval is required before any automation that changes:
- repository configuration behavior,
- repository settings, or
- policy-impacting operational controls.

Default rule: if classification is unclear, treat as approval-required until confirmed.

## 10. Evidence Rules
Each automation run should provide repository-visible evidence:
- trigger type and timestamp,
- requested action,
- executed commands or operation summary,
- resulting artifact (diff, status, log, or PR),
- final classification (allowed / approval-required / prohibited),
- stop/escalation reason when not executed.

Evidence must be concise, reviewable, and attributable to a single task/run.

## 11. Source-of-Truth Alignment
- GitHub `main` remains the source of truth.
- Local workspace state is a working copy.
- Automation outcomes should converge back to branch + PR review flow.
- No automation bypasses repository review and approval expectations.

## 12. Human / ChatGPT / Codex Roles
- Human:
  - sets intent, provides approvals, and makes final merge/policy decisions.
- ChatGPT:
  - defines architecture, classifies risk, and validates audit/evidence standards.
- Codex:
  - executes approved, scoped operations and records execution evidence.

## 13. Allowed / Approval Required / Prohibited Automation
Allowed:
- monitoring,
- scheduled checks,
- CI status inspection,
- workflow rerun.

Approval Required:
- configuration changes,
- repository settings updates.

Prohibited:
- secrets modification,
- IAM changes,
- destructive operations.

## 14. Example Flows
1. Scheduled CI health check (Allowed)
- Trigger: schedule.
- Action: inspect CI status and summarize failures.
- Output: report artifact and optional issue/PR comment.

2. Workflow rerun request (Allowed)
- Trigger: human request after transient CI failure.
- Action: rerun specified workflow.
- Output: rerun identifier and updated status evidence.

3. Repository setting update request (Approval Required)
- Trigger: proposal to adjust repository configuration.
- Action: classify as approval-required and halt until approval.
- Output: escalation note with requested approval scope.

4. Secret rotation command request (Prohibited)
- Trigger: command intent includes secret mutation.
- Action: stop execution.
- Output: boundary violation report with safer alternative path.

## 15. Decision Summary
- Automation introduction is design-only in this phase.
- Default automation focus is observability and operational support.
- Sensitive control-plane and security-impacting actions remain gated or blocked.
- The architecture enforces safety, minimalism, auditability, repository alignment, and approval compatibility.
