# AI Output Standard

## 1 Purpose
This standard defines a minimum, shared structure for AI-generated outputs in this repository.
A common format improves consistency, review speed, and reliable handoff across:
- AI to AI communication
- AI to automation pipelines
- AI to multi-agent workflows
- AI to human review

## 2 Scope
This standard applies to AI-generated outputs for:
- documentation
- design proposals
- runbooks
- ADR
- code suggestions
- AI responses
- AI-to-AI handoff messages

## 3 Design Principles
- Lightweight: minimum required structure only.
- Reusable: same baseline works for humans, AI, and tooling.
- Markdown-first: default format is Markdown.
- Git-friendly: easy to diff, review, and version.
- Automation-friendly: machine-readable where possible without heavy schemas.

## 4 Common Output Rules
Universal rules for all AI outputs:

- Required top-level structure:
  - Title
  - Goal
  - Context or Purpose
  - Main content
  - Decisions or assumptions (when relevant)
  - Next steps or done status
- Markdown formatting rules:
  - Use clear headings with numbered sections when the document is structured.
  - Use bullet lists for scannable items.
  - Keep paragraphs short and direct.
  - Prefer stable terms across documents.
- Code block rules:
  - Use fenced code blocks with a language tag when possible.
  - Keep examples minimal and runnable where practical.
  - Separate code from explanatory text.
- Decision clarity rules:
  - State decisions explicitly.
  - Distinguish decisions from proposals and assumptions.
  - Record known constraints and open risks when they affect execution.

## 5 Output Types
Minimum structures by output type:

- Documentation:
  - Purpose
  - Scope
  - Key points
  - Decisions
- Runbook:
  - Purpose
  - Preconditions
  - Steps
  - Verification
  - Rollback or escalation path
- ADR:
  - Context
  - Decision
  - Consequences
  - Status
- Code suggestion:
  - Goal
  - Proposed change
  - Files impacted
  - Risks or tradeoffs
  - Validation approach
- AI response:
  - Answer
  - Reasoning
  - Constraints or caveats
  - Next actions
- AI-to-AI handoff:
  - Task
  - Current status
  - Inputs and constraints
  - Remaining work
  - Stop conditions

## 6 AI-to-AI Communication Rules
When one AI agent hands off to another, include at minimum:

- Task: what work unit is being transferred.
- Goal: target outcome to complete.
- Inputs: files, references, artifacts, and prior outputs.
- Constraints: scope boundaries and prohibited changes.
- Current status: what is done, in progress, or blocked.
- Expected output: required return format or artifact.
- Stop conditions: when to stop and return control.

Communication rules:
- Keep handoff messages concise and explicit.
- Prefer repository paths and concrete identifiers.
- Mark assumptions clearly when information is missing.
- Do not include secrets or credential material.

## 7 Exclusions
This standard does not define:
- Skill design
- MCP
- automation workflows
- multi-agent orchestration
- approval policy or governance workflow design
- branching strategy beyond existing repository rules

## 8 Done Condition
This standard is complete when:
- The minimum output format rules are documented in one file.
- Output types have baseline structures suitable for reuse.
- AI-to-AI handoff fields are explicitly defined.
- Exclusions and boundaries are clear.
- The document remains concise and practical.

## 9 Examples
### 9.1 Documentation output
```md
# Drive Sync Naming Guide

## 1 Purpose
Standardize folder naming for monthly backup exports.

## 2 Scope
Applies to `docs/drive-sync/` naming conventions only.

## 3 Key Points
- Use `YYYY-MM` for monthly folders.
- Keep service names lowercase and hyphenated.

## 4 Decisions
- Existing historical folder names remain unchanged.
```

### 9.2 Runbook output
```md
# RUNBOOK: Failed Sync Recovery

## 1 Purpose
Recover from repeated sync job failures.

## 2 Preconditions
- Access to runner logs
- Permission to restart the worker process

## 3 Steps
1. Confirm latest failure reason in logs.
2. Fix configuration or credential issue.
3. Restart the sync worker.

## 4 Verification
- Next scheduled sync completes.
- Error count does not increase for 30 minutes.
```

### 9.3 ADR output
```md
# ADR: Backup Manifest Format

## 1 Context
Need a diff-friendly format for backup manifests.

## 2 Decision
Use line-oriented JSON files stored in the repository.

## 3 Consequences
- Easy Git diff and review
- Requires schema discipline for compatibility

## 4 Status
Accepted
```

### 9.4 AI-to-AI handoff
```md
# AI Handoff

## Task
Update runbook wording for failure recovery.

## Goal
Deliver a concise update to `docs/RUNBOOK-drive-sync.md`.

## Inputs
- `docs/RUNBOOK-drive-sync.md`
- Recent CI failure notes

## Constraints
- Documentation only
- No unrelated file edits

## Current status
Failure scenarios drafted; verification wording pending.

## Expected output
A patch that updates only recovery-related sections.

## Stop conditions
Stop if changes require architecture or automation redesign.
```
