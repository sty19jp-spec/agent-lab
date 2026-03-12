# Safety and Boundaries

## Merge-only model

The repository operates under a merge-only model.

Normal delivery is:

AI Executor -> Pull Request -> validator checks -> human merge -> `main`

Direct push to `main` is not the normal operating model.

This is a governance choice, not just a workflow preference. The repository is designed so that AI-generated changes must pass through a Pull Request and its validator path before merge.

## Human responsibilities

At the TrackA Layer5 completed snapshot, the human role is intentionally narrow.

Human responsibilities are:

- merge judgment
- exception approval when genuinely required
- GUI-only operations where repository controls depend on GitHub UI

The human is not expected to perform the normal implementation or PR preparation flow in place of the executor.

## AI executor responsibilities

The AI Executor is expected to carry the normal delivery path:

- inspect repository context
- implement scoped changes
- validate locally
- prepare factual PR metadata
- push the task branch
- create the Pull Request

The repository treats this as normal executor behavior, not as a special override path.

## What requires human approval

Human approval is required for actions outside normal repository-safe execution boundaries, especially when they are destructive or security-sensitive.

Examples include:

- repository settings changes
- branch protection changes
- permissions or secret handling changes
- exceptional security-sensitive configuration changes
- destructive actions outside ordinary scoped repository work

Normal task execution, scoped file edits, validator-aware PR creation, and ordinary branch-based delivery should not require manual human CLI intervention.

## What must not be committed

The repository should not commit transient runtime artifacts or sensitive material.

Examples of things that must not be committed in normal operation:

- runtime-generated transient files under `.runtime/`
- secrets
- credentials
- `.env`-style sensitive configuration files
- private keys
- ambiguous local artifacts unrelated to the scoped task

The repository’s runtime and validator flow assumes that execution artifacts remain auditable when needed but are not accidentally added to normal PR diffs.

## Why direct push is not the operating model

Direct push bypasses the core governance path:

- Pull Request reviewability
- validator enforcement
- branch protection
- explicit human merge judgment

Because the repository is designed as an AI governance environment, bypassing those controls would remove the main safety properties the repository is trying to preserve.

## Why repository docs are the source of truth for this guide

This guide is a shareable snapshot, but it is not the normative source of truth.

The repository itself is the source of truth, especially:

- governance documents in `docs/governance/`
- runbooks in `docs/runbooks/`
- validator specifications in `docs/`
- the actual scripts and tools in `scripts/` and `tools/`

If this guide and the repository ever diverge, the repository wins.

## Allowed and forbidden operational posture

Allowed:

- scoped branch-based work
- factual PR metadata generation
- local pre-validation
- Ready PR creation
- waiting for validator pass before merge

Forbidden as normal operation:

- direct push to `main`
- validator bypass
- fabricated validation claims
- unrelated diff in a task PR
- using human merge authority as a substitute for validator discipline

## What this repository is for

At the TrackA Layer5 completed snapshot, the repository is for:

- controlled AI-assisted repository work
- validator-aware Pull Request creation
- repository-first governance
- auditable execution and merge flow

## What this repository is not for

It is not for:

- unconstrained autonomous code execution
- bypassing merge governance
- treating AI output as self-authorizing
- replacing human merge judgment with automation alone
