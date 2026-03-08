# Execution Evidence Schema (Layer5 Phase26)

## 1. Purpose
Define a fixed, practical schema for runtime execution evidence and a minimum artifact validation model.

This document standardizes evidence output from the existing runtime pipeline:

```text
task package
-> bundle resolve
-> preflight
-> execution
-> execution evidence
```

## 2. Scope
This phase is specification-first and repository-first.

In scope:
- execution evidence schema definition
- artifact validation rules
- schema validation policy
- artifact integrity contract
- validator tool interface design

Out of scope:
- replacing current runtime pipeline
- introducing approval UI
- heavy framework migration or overengineered enforcement

## 3. Runtime Compatibility Baseline
Current producer modules:
- `runtime.engine`
- `runtime.evidence`

Current evidence behavior:
- evidence is built by `runtime.evidence.build_evidence`
- evidence is persisted by `runtime.evidence.persist_evidence`
- success path uses `task.output.evidence_path` when provided
- blocked/error paths currently fall back to `examples/evidence/<run_id>.json`

Phase26 rule:
- keep current behavior for compatibility
- standardize and explicitly document fallback semantics

## 4. Evidence Schema Versioning
Introduce explicit schema metadata at the specification level.

Required metadata fields (normative):
- `schema_name`: `execution-evidence`
- `schema_version`: `v1`

Compatibility policy:
- `v1` is backward-compatible with current Phase25 evidence field structure
- minor compatible additions: add optional fields only
- breaking changes require a new major schema version (`v2`, ...)

Implementation note:
- runtime may adopt explicit emission of these metadata fields in a later phase
- until then, validator tools may inject/assume `schema_name=execution-evidence` and `schema_version=v1` from context

## 5. Fixed Execution Evidence Schema (v1)
Top-level required object keys:
- `task_evidence`
- `execution_evidence`
- `execution_summary`
- `preflight_summary`
- `close_summary`
- `run_state`
- `evidence_file`

### 5.1 `task_evidence` (required object)
Required keys:
- `task_ref` (string)
- `task_resolved` (string or null)
- `task_id` (string or null)
- `task_type` (string or null)
- `bundle_ref` (string)
- `bundle_resolved` (string or null)
- `bundle_id` (string or null)
- `bundle_version` (string or null)

### 5.2 `execution_evidence` (required object)
Required keys:
- `success` (boolean)
- `action` (string)
- `operator` (string)
- `detail` (string)
- `outputs` (object)

### 5.3 `execution_summary` (required object)
Required keys must mirror `execution_evidence` keys:
- `success`
- `action`
- `operator`
- `detail`
- `outputs`

Consistency rule:
- `execution_summary` and `execution_evidence` must be value-equivalent for shared keys.

### 5.4 `preflight_summary` (required object)
Required keys:
- `passed` (boolean)
- `gate_a` (object)
- `gate_b` (object)

Each gate object required keys:
- `gate` (string)
- `passed` (boolean)
- `reason` (string)

### 5.5 `close_summary` (required object)
Required keys:
- `run_id` (string)
- `status` (string)
- `dedup_key` (string)
- `retry_counter` (integer >= 0)

### 5.6 `run_state` (required object)
Required keys:
- `run_id` (string)
- `status` (string)
- `dedup_key` (string)
- `retry_counter` (integer >= 0)
- `started_at` (RFC3339 timestamp string)
- `ended_at` (RFC3339 timestamp string or null)
- `error` (string or null)

Cross-field rules:
- `run_state.run_id == close_summary.run_id`
- `run_state.dedup_key == close_summary.dedup_key`
- `run_state.retry_counter == close_summary.retry_counter`
- when `close_summary.status` is `closed`, `execution_evidence.success` should be `true`
- when `close_summary.status` is `blocked` or `failed`, `execution_evidence.success` should be `false`

### 5.7 `evidence_file` (required string)
Rules:
- absolute or repository-relative path string
- should point to the persisted evidence file for the same run

## 6. Artifact Contract
Artifacts are repository-visible execution outputs.

Artifact classes:
- Evidence artifact: execution evidence JSON
- Task artifact: task-specific output (for example `docs_validation` report)

### 6.1 Evidence Artifact Requirements
- must be valid JSON object
- must satisfy Execution Evidence Schema v1
- must include deterministic run identity (`run_id`, `dedup_key`, `retry_counter`)
- must be persisted under repository workspace paths

### 6.2 Task Artifact Requirements (current `docs_validation`)
Required keys:
- `task_id`
- `task_type`
- `bundle_id`
- `bundle_version`
- `checked_at`
- `checks`
- `missing_count`

`checks` item required keys:
- `path` (string)
- `exists` (boolean)
- `is_markdown` (boolean)
- `size_bytes` (integer >= 0)

Consistency rules:
- `missing_count` equals the number of `checks[].exists == false`
- `execution_evidence.outputs.validation_report` should reference this artifact path when present

## 7. Artifact Validation Rules
Validation levels:
1. `required`: hard failure if violated
2. `recommended`: warning only

Required checks:
- evidence JSON parse success
- required top-level keys present
- required nested keys present with correct primitive types
- cross-field consistency rules in section 5
- referenced task artifact path exists when `outputs.validation_report` exists

Recommended checks:
- `task_ref` and `bundle_ref` follow logical ref patterns (`task://`, `bundle://`) when logical refs are used
- `reason` values are concise and deterministic
- evidence path resides under repository root

## 8. Schema Validation Policy
Policy levels:
- `strict` (CI / policy gate): fail on any required check error
- `lenient` (local development): fail only on JSON parse or missing top-level objects

Phase26 default policy:
- local executor runs: `lenient`
- PR/CI enforcement (future): `strict`

Result contract for validators:
- `valid` (boolean)
- `errors` (list)
- `warnings` (list)
- `schema_name`
- `schema_version`
- `validated_at`

## 9. Evidence Path Fallback Clarification
Current runtime behavior:
- successful execution attempts to write evidence to `task.output.evidence_path`
- blocked/error runs currently use fallback `examples/evidence/<run_id>.json`

Phase26 clarification:
- this asymmetry is accepted for compatibility in current runtime
- validators must treat both as compliant if evidence schema is valid
- future enhancement may apply `task.output.evidence_path` to blocked/error runs when task document is available

## 10. Artifact Integrity Contract
Integrity goals:
- evidence and artifact files must be attributable to one run
- run identity must be stable for same contract + retry counter
- artifacts should be tamper-evident through repository history

Minimum integrity requirements:
- evidence contains `run_id`, `dedup_key`, `retry_counter`
- evidence references generated outputs through `execution_evidence.outputs`
- artifact files are committed/reviewed via normal PR workflow when part of deliverables

Optional future integrity extensions:
- content digest fields (`sha256`) for evidence and task artifacts
- signature metadata for external attestations

## 11. Evidence Validation Tool Interface (Design)
Phase26 defines a minimal interface only (no heavy implementation required).

Proposed CLI:

```bash
python3 -m runtime.validate_evidence \
  --evidence-file examples/evidence/docs-validation-evidence.json \
  --schema-version v1 \
  --policy strict
```

Proposed arguments:
- `--evidence-file` (required)
- `--schema-version` (default `v1`)
- `--policy` (`lenient` or `strict`, default `lenient`)
- `--artifact-file` (optional, repeatable)

Proposed outputs:
- machine-readable JSON validation result
- non-zero exit on required-check failure

Integration intent:
- local preflight/verification hooks
- CI validation step in PR workflow (future)

## 12. Governance Alignment
This schema standard remains aligned with existing governance:
- GitHub `main` as source of truth
- PR workflow as review/approval mechanism
- repository-visible evidence as audit mechanism
- no approval UI dependency
- human escalation only for destructive or security-related operations

## 13. Minimal Adoption Plan
1. Adopt this schema as the normative reference for evidence reviews.
2. Keep runtime output format compatible with current modules.
3. Add lightweight validator implementation in a follow-up phase.
4. Add CI enforcement only after validator stability is confirmed.
