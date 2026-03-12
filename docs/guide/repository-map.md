# Repository Map

This file gives a short map of the major top-level areas of `agent-lab` at the TrackA Layer5 completed snapshot.

## Top-level directories

- `docs/`
  - Governance, validator specifications, runbooks, and design references.
- `scripts/`
  - Launcher and runtime shell scripts used by the executor-oriented workflow.
- `tools/`
  - Validator implementations and related repository utilities.
- `examples/`
  - Example evidence files and related fixtures.
- `registry/`
  - Registry-oriented data maintained by the repository.
- `runtime/`
  - Runtime-oriented repository content that is separate from transient `.runtime/` state.
- `logs/`
  - Repository-local logging outputs and related operational artifacts.
- `task/`
  - Task-oriented repository material.
- `bundle/`
  - Bundled or packaged repository assets.
- `workspace/`
  - Working-space content used by repository tasks and templates.
- `drive-sync-structure/`
  - Drive-related structure or supporting material for the repository’s backup-oriented components.

## Key top-level files

- `README.md`
  - Main repository entrypoint.
- `Makefile`
  - Operator-facing command entrypoints, including task start.
- `AGENTS.md`
  - Repository-local instructions and operating constraints for AI agents.
- `get_refresh_token.py`
  - Utility related to repository-specific Drive integration support.

## Runtime-related paths to know

- `.runtime/`
  - Transient runtime evidence and execution state. This is not normal committed task output.
- `scripts/codex-task.sh`
  - Main task launcher entrypoint.
- `scripts/pre-validate-pr.sh`
  - Local pre-validation and PR creation wrapper aligned with the validator flow.

## Read this after the map

For actual operation, use this order:

1. `docs/guide/agent-lab-guide.md`
2. `docs/guide/setup-and-usage.md`
3. `docs/guide/safety-and-boundaries.md`
