# AI Skill and MCP Architecture (Chat23-2 / Layer3 Phase15)

## 1. Purpose
This document defines a minimal architecture for controlled capability expansion beyond repository-local execution by using Skills first and MCP second.
The design keeps AI execution practical while preserving repository governance, approval boundaries, and security boundaries.

## 2. Scope
This phase defines:
- logical roles of Skills and MCP
- selection and priority rules for capability use
- tool exposure categories and control levels
- approval and security boundaries for expanded capabilities
- example execution flows for consistent operations

This phase does not implement runtime onboarding, service provisioning, or infrastructure changes.

## 3. Non-Goals
This phase does not:
- implement specific MCP server onboarding procedures
- change repository workflows, IAM, or secret handling
- design a plugin marketplace or dynamic extension framework
- enable uncontrolled external execution
- define automation orchestration or multi-agent routing details

## 4. Definitions
- Capability expansion: adding controlled execution abilities beyond repository-only operations.
- Skill: a repository-available instruction package (`SKILL.md` with optional scripts/templates) that standardizes how the executor performs a known task pattern.
- MCP (Model Context Protocol): a controlled tool-bridge interface used when required capabilities cannot be met by repository-local tools or Skills alone.
- Tool exposure model: classification of tools by capability surface and required control level.
- Approval boundary: operations that require explicit human approval before execution.
- Security boundary: hard limits that prevent destructive actions, secret exfiltration, and governance bypass.

## 5. Design Principles
- Minimal first: prefer the smallest capability that can complete the task safely.
- Skill first: prefer repository-local, versioned, reviewable execution patterns.
- MCP second: use MCP only when Skill and local CLI cannot satisfy the requirement.
- Governance aligned: external capabilities must not bypass repository PR and review flow.
- Explicit control: classify operations as auto-allowed, approval-required, or prohibited.
- Portable architecture: avoid tight coupling to proprietary platforms.
- Automation compatible: design must remain deterministic and machine-operable.

## 6. Skill Architecture
### 6.1 Role
Skills are the default capability-expansion unit.
They encode reusable execution logic inside repository-adjacent, inspectable artifacts.

### 6.2 Structure
A Skill is expected to include:
- `SKILL.md` for trigger and workflow instructions
- optional `scripts/` for repeatable commands
- optional `assets/` or templates for standard outputs

### 6.3 Operating Model
- Skill discovery is local and explicit.
- Skill invocation is deterministic from task intent plus repository context.
- Skill execution uses existing executor tools (CLI, file edits, tests) under current boundaries.
- Skill outputs remain reviewable in repository history when persisted.

### 6.4 Why Skill First
Skills are preferred because they are:
- local by default
- versionable and auditable
- easier to secure than external tool bridges
- consistent with repository-as-source-of-truth operation

## 7. MCP Architecture
### 7.1 Role
MCP is a secondary capability layer for controlled access to non-local tools or data when local execution and Skills are insufficient.

### 7.2 Use Criteria
Use MCP only when all conditions are met:
- the task cannot be completed with repository files, local CLI, and available Skills
- the required external operation is clearly scoped
- output can be mapped back to repository-governed artifacts
- approval requirements are satisfied for the requested operation class

### 7.3 Constraints
- MCP access is opt-in and scoped per task.
- MCP operations must be logged in execution evidence.
- MCP must not introduce implicit write paths that bypass repository review.
- Implementation details for onboarding real MCP servers are out of scope for this phase.

## 8. Tool Exposure Model
Capability surfaces are grouped as follows:

- Repository-local capabilities:
  - repository files, git operations, local tests, local scripts, local documentation generation
- Host/system inspection capabilities:
  - process inspection, OS metadata reads, environment inspection, local runtime diagnostics
- External API/service capabilities:
  - remote data retrieval, third-party API calls, cloud/SaaS operations, remote write actions

Control is applied per surface using the policy matrix in Section 13.

## 9. Security Boundary
The architecture enforces:
- no secret extraction or credential exfiltration
- no destructive host-level actions
- no implicit privilege escalation through Skill or MCP paths
- no unauthorized external write actions

Security-critical operations remain approval-required even when technically possible via Skill or MCP.

## 10. Approval Boundary
Human approval is required for operations with elevated risk, including:
- external system mutations
- billing-impacting operations
- identity, permission, or credential-affecting changes
- destructive or irreversible actions

Routine repository-local work remains executor-led without human CLI intervention.

## 11. Source-of-Truth Alignment
- GitHub `main` remains the only source of truth.
- Drive remains backup and long-term archive.
- Obsidian remains human knowledge space.
- Beads remains AI external memory/context support.

Skill and MCP outputs become authoritative only after repository integration through normal branch/PR flow.
External capability use must not bypass this governance path.

## 12. Execution Priority and Selection Rules
Apply capability selection in this order:
1. Repository-only execution (no Skill, no MCP) when sufficient.
2. Skill execution when reusable local workflow adds safety or consistency.
3. MCP execution only when 1 and 2 cannot satisfy task requirements.
4. Approval gate before any approval-required operation.

Selection rules:
- Choose the least-privilege path that can complete the task.
- Avoid mixed-mode complexity unless required for task completion.
- Record why higher-tier capability (Skill or MCP) was selected.

## 13. Allowed / Approval Required / Prohibited Actions
### 13.1 Repository-Local Capabilities
- Auto-Allowed:
  - read/edit repository files in scope
  - run local lint/test/build commands
  - create branch, commit, and PR artifacts
- Approval-Required:
  - destructive history rewrites on shared branches
  - operations with potential irreversible data loss
- Prohibited:
  - secret injection or credential dumping
  - bypassing branch/PR governance controls

### 13.2 Host/System Inspection Capabilities
- Auto-Allowed:
  - non-destructive environment and process inspection required for debugging
  - local runtime diagnostics with no privilege escalation
- Approval-Required:
  - privileged system changes
  - package/system modifications outside defined task scope
- Prohibited:
  - destructive OS-level actions
  - persistence or backdoor-style host modifications

### 13.3 External API/Service Capabilities
- Auto-Allowed:
  - read-only external queries with no sensitive data mutation and no policy conflict
- Approval-Required:
  - any external write/mutation
  - operations affecting billing, IAM, secrets, or production-like state
  - network exposure changes
- Prohibited:
  - unapproved secret transfer
  - unmanaged long-lived external execution
  - external operations that circumvent repository governance

## 14. Example Flows
### 14.1 Direct Repository-Only Execution Is Enough
Task: update a design doc and open a PR.
Decision: run repository-local edits and git/PR flow only.
Reason: no external data or non-local tools are needed.

### 14.2 Skill Should Be Used
Task: generate a standardized runbook update using an existing documentation Skill.
Decision: invoke Skill workflow to ensure consistent structure and checks.
Reason: task pattern is known and fully solvable with local assets.

### 14.3 MCP Should Be Used
Task: collect a remote system inventory not available in repository or local host context.
Decision: use scoped MCP read operation, then commit summarized results to repository artifacts.
Reason: capability gap exists; MCP is required and bounded.

### 14.4 Human Approval Is Required
Task: use an MCP tool to mutate an external service configuration.
Decision: halt at approval boundary and request explicit human approval before execution.
Reason: external write action is security-critical and outside auto-allowed class.

## 15. Decision Summary
This phase adopts a minimal, controlled capability-expansion architecture:
- Skill is the primary expansion mechanism.
- MCP is a secondary, scoped fallback for true capability gaps.
- Repository-only execution remains preferred when sufficient.
- Security-critical and external mutation operations remain approval-required.
- External capabilities must never bypass repository governance.

The design is intentionally narrow so automation and future phases (Automation, Multi-agent) can build on a stable and secure baseline.
