# AI Execution Boundary

## 1. Purpose
This document defines the minimum execution boundary for AI agents operating in this repository.
The boundary is intentionally lightweight: it enables safe but highly autonomous AI-driven development while blocking only catastrophic host-level damage or credential exfiltration.

## 2. Execution Model
Execution flow:

Human
↓
ChatGPT (architecture / auditing)
↓
AI Agents (Codex / Claude Code)
↓
Repository / CI / Infrastructure

AI agents are the primary executors. Humans handle approvals and final decisions when needed, but routine implementation and operations are executed by AI agents.

## 3. Operation Categories
Operations are grouped into three categories:
- Allowed Operations
- Approval Required Operations
- Prohibited Operations

## 4. Allowed Operations
Nearly all development and sandbox infrastructure operations are allowed in this repository.

Examples:
- git operations
- gh CLI operations
- file system operations
- docker build / run / compose
- terraform apply
- gcloud compute / storage operations
- package installation
- CI execution
- workflow reruns
- local server startup
- network port exposure
- environment setup
- script execution

These are allowed because repository resources, infrastructure, and accounts are treated as disposable sandbox environments designed for rapid iteration.

## 5. Approval Required Operations
Approval-required operations are intentionally rare.

Examples:
- changes affecting real billing accounts
- modification of personal user accounts
- operations outside the sandbox infrastructure

In this repository, these cases should be exceptional, not part of normal execution.

## 6. Prohibited Operations
Only catastrophic host-level actions are prohibited.

Examples:
- `rm -rf /`
- disk formatting
- deleting the operating system
- kernel-level destruction
- credential exfiltration
- dumping secret storage

These are blocked because they can destroy the host machine or leak credentials.

## 7. Execution Halt Conditions
AI agents must halt execution when:
- the operating environment becomes corrupted
- a command loop is detected
- an unrecoverable OS error occurs

Outside these conditions, agents should attempt autonomous recovery and continue execution.

## 8. Boundary Violation Reporting
If a prohibited action is detected, the agent must output:

`STOP: execution boundary reached`

The report must include:
- requested action
- reason
- suggested alternative

## 9. Design Principle
This boundary must remain:
- lightweight
- practical
- repository-focused

Do not expand this document into heavy governance frameworks or enterprise security models.
If an operation cannot be clearly classified, agents should treat it as Allowed unless it risks host-level destruction or credential exfiltration.
