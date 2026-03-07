# AI Knowledge Integration Baseline

## 1. Purpose
This document defines the baseline rules for how AI executors access and interpret knowledge during task execution.
It clarifies authoritative sources, priority order, and ingestion boundaries so execution remains consistent and automation-compatible.

## 2. Knowledge Source Definition
The system uses four knowledge sources:

- Repository knowledge (GitHub): version-controlled implementation and operational knowledge used by executors.
- Human knowledge (Obsidian): human-authored thinking space for drafts and exploration.
- Backup knowledge (Google Drive): retained copies and backup artifacts.
- AI memory and task context (Beads): runtime task context, execution state, and AI memory anchors.

## 3. Repository as Source of Truth
For AI task execution, the GitHub repository is the authoritative knowledge source.
If conflicts exist between repository content and external notes or backups, repository content takes precedence unless explicitly overridden by a human task contract.

## 4. Knowledge Hierarchy
AI executors must apply the following priority order:

Tier 1:
Repository knowledge

Tier 2:
Execution context (task contract, runtime context)

Tier 3:
External knowledge (Obsidian, Drive)

## 5. Repository Knowledge Rules
Allowed repository knowledge includes executor-relevant, reviewable, versioned artifacts such as:

- `docs/`
- `runbooks/`
- `runbooks/adr/`
- `spec/`
- `architecture/`

Forbidden content in the repository includes:

- personal notes
- research drafts
- credentials
- private data

## 6. Knowledge Visibility Classes
Class A: Automation readable
- Intended for AI and automation consumption.
- Examples: docs, runbooks, spec.

Class B: Human readable
- Intended primarily for human iteration and interpretation.
- Examples: design drafts, research.

Class C: External only
- Must remain outside repository execution scope.
- Examples: Obsidian private notes.

## 7. Automation-Readable Knowledge
Automation and AI executors may read repository content from these directories:

- `docs/`
- `runbooks/`
- `scripts/`
- `configs/`
- `spec/`

Access outside these paths should be treated as opt-in and explicitly scoped by task contract.

## 8. Knowledge Ingestion Boundary
External knowledge must pass through a lightweight ingestion flow before becoming execution-authoritative in the repository:

Obsidian research
->
validation
->
documentation
->
repository docs

Only validated and documented knowledge becomes repository knowledge.

## 9. Architecture Overview
Knowledge ecosystem flow:

Human thinking
->
Obsidian
->
GitHub repository (source of truth)
->
Drive backup
->
AI executor

## 10. Examples
Repository-readable knowledge paths:

- `docs/`
- `runbooks/`
- `runbooks/adr/`
- `spec/`

## 11. Done Condition
This baseline is complete when AI executors consistently treat repository content as authoritative, apply the hierarchy, and ingest external knowledge only through the defined validation-to-documentation boundary.
