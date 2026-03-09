# Execution Evidence Provenance (Layer5 Phase29)

## 1. Purpose
Define a practical provenance model for execution evidence so each run can be traced by identity, runtime fingerprint, repository state, and execution context.

This phase is specification-first and keeps runtime changes minimal.

## 2. Scope
In scope:
- provenance model for runtime evidence JSON
- execution identity field definitions
- runtime fingerprint field definitions
- repository-state traceability model
- alignment rules for evidence and registry metadata

Out of scope:
- heavy runtime refactor
- approval UI changes
- replacing the current evidence schema versioning strategy

## 3. Compatibility Baseline
Current state:
- runtime emits `task_evidence`, `execution_evidence`, `execution_summary`, `preflight_summary`, `close_summary`, `run_state`
- validator enforces current required schema keys
- registry persists evidence copy under `registry/data/evidence/` and metadata under `registry/data/index.json`

Phase29 rule:
- provenance fields are additive and backward-compatible
- existing evidence without provenance remains valid

## 4. Provenance Model
Provenance is represented as an optional top-level object in execution evidence:

```json
{
  "provenance": {
    "execution_identity": {},
    "runtime_fingerprint": {},
    "repository_state": {},
    "execution_context": {}
  }
}
```

Registry metadata MAY persist a flattened or nested equivalent under each registry entry.

## 5. Execution Identity
`provenance.execution_identity` fields:
- `executor_id` (string): stable identifier for the concrete executor instance/session (for example codex session id or automation runner id).
- `executor_type` (string): executor class, expected values include `codex-cli`, `automation-bot`, `human-assisted`.
- `operator` (string): canonical operator role (`Architect`, `Executor`, `Auditor`, `Human`). Must align with `execution_evidence.operator`.

Minimum rule:
- `operator` is required when `execution_identity` exists.

## 6. Runtime Fingerprint
`provenance.runtime_fingerprint` fields:
- `runtime_name` (string): runtime implementation name (for example `agent-lab-runtime`).
- `runtime_version` (string): runtime version or build identifier.
- `bundle_version` (string or null): runtime bundle version for the run.
- `task_version` (string or null): task definition version when available.

Compatibility rule:
- `bundle_version` should match `task_evidence.bundle_version` when both exist.

## 7. Repository State
`provenance.repository_state` fields:
- `repository_commit` (string): git commit SHA used for execution context.
- `repository_branch` (string): branch name used at execution time.
- `repository_dirty` (boolean, optional): whether tracked changes existed during execution.

Traceability rule:
- when available, `repository_commit` should be the primary join key for CI/audit reconstruction.

## 8. Execution Context
`provenance.execution_context` fields:
- `execution_timestamp` (RFC3339 string): canonical execution timestamp.
- `trigger_type` (string): `manual`, `schedule`, or `event_stub`.
- `retry_counter` (integer >= 0, optional): copy of retry context for joins.

Consistency rules:
- `trigger_type` should align with loader/preflight trigger used by runtime.
- when `retry_counter` exists, it should equal `run_state.retry_counter`.

## 9. Evidence and Registry Alignment
Evidence-level source of truth:
- canonical provenance should live in execution evidence JSON (`provenance` object).

Registry-level alignment:
- registry entries should persist key provenance fields for query/history use.
- registry metadata should reference registry-owned archived evidence path.
- provenance in registry must be derived from evidence and immutable run context, not manually edited annotations.

Recommended registry metadata extensions (additive):
- `executor_id`
- `executor_type`
- `runtime_name`
- `runtime_version`
- `task_version`
- `repository_commit`
- `repository_branch`
- `execution_timestamp`
- `trigger_type`

## 10. Validation Expectations
Phase29 validator expectation (minimal):
- accept evidence with or without `provenance`
- when `provenance` exists, enforce type checks and consistency checks for overlapping fields (`operator`, `bundle_version`, `retry_counter`)

CI/audit expectation:
- provenance fields should be queryable in registry for run history and incident reconstruction.

## 11. Adoption Plan
1. Adopt this document as normative provenance reference.
2. Add optional `provenance` emission in runtime evidence (future incremental patch).
3. Extend validator with optional provenance checks (future incremental patch).
4. Extend registry indexing for provenance query fields (future incremental patch).
5. Add CI checks once field emission and validator behavior are stable.

## 12. Governance Alignment
This provenance model remains aligned with project controls:
- GitHub repository is source of truth
- evidence and provenance remain repository-visible
- no interactive approval dependency for normal execution
- escalation remains limited to destructive/security-related operations

## 13. Phase32 Validator Integrity Checks
Phase32 extends `tools/evidence_validator.py` to make provenance machine-verifiable when provenance exists.

Validation layers:
- Layer1: provenance schema/type checks for `execution_identity`, `runtime_fingerprint`, `repository_state`, `execution_context`
- Layer2: provenance presence/completeness handling tied to `run_state` compatibility rules
- Layer3: repository commit integrity check (`provenance.repository_state.repository_commit` vs `git rev-parse HEAD`)
- Layer4: timestamp integrity checks for RFC3339 format, non-future values, and consistency with `run_state` timestamps

Compatibility rule:
- evidence without `provenance` remains acceptable for backward compatibility
- provenance integrity checks are enforced when provenance is present
