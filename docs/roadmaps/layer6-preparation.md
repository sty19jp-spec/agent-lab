# Layer6 Preparation

## Purpose

Define the preparation themes for Layer6 after the formal closeout of Layer5.

This document is preparation only. It is not an implementation design.

## Why Layer6 Is Separate

Layer5 closes the single-repository governance core:

- PR-ready autonomous execution
- validator-aware PR creation
- auditable execution evidence
- repository-safe recovery and reliability
- human merge boundary

Layer6 is separate because it moves beyond that core boundary. The remaining themes are expansion topics, not missing Layer5 governance requirements.

## Candidate Themes

### Executor Sandbox

Theme:

- stronger execution isolation around the executor runtime

Why deferred:

- Layer5 already provides repository-safe operational controls without introducing a sandbox platform

### Multi-Repo Execution

Theme:

- coordinated execution across more than one repository

Why deferred:

- Layer5 is intentionally single-repository and PR-centered

### Agent Orchestration Expansion

Theme:

- broader multi-agent coordination beyond the current executor-focused flow

Why deferred:

- Layer5 only needs one controlled executor path to satisfy governance core requirements

### Cross-Repository Automation

Theme:

- automation that spans repository boundaries or produces repository-to-repository workflows

Why deferred:

- Layer5 constrains execution to the current repository as the source of truth

## Suggested Sequencing

1. Sandbox isolation
2. Multi-repo execution
3. Cross-repository automation
4. Broader orchestration expansion

This order keeps safety boundaries ahead of execution expansion.

## Dependencies Inherited From Layer5

Layer6 should inherit, not replace:

- merge-only PR delivery
- validator-aware PR metadata discipline
- same-artifact pre-validation and submission
- runtime evidence and provenance
- stage-aware execution control
- bounded recovery and reliability controls
- human merge authority

## Boundary Statement

Layer5:

- single-repository governance core
- PR-ready autonomous execution
- evidence and validator consistency
- self-healing runtime within repository-safe bounds

Layer6:

- expansion beyond the single-repository governance core
- sandbox isolation
- multi-repo execution
- broader agent orchestration
- cross-repository automation

## Non-goals

- implementing Layer6 features in this phase
- defining workflow or validator changes
- redesigning the Layer5 runtime
- committing to a full Layer6 architecture
