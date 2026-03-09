# Validator Chain Governance (Layer5 Phase37)

## Purpose
Define governance for validator-chain execution so Pull Requests are evaluated by a deterministic multi-validator path before merge.

This phase introduces chain-level orchestration in GitHub Actions. It does not replace existing validator logic.

## Scope
In scope:
- chain orchestration workflow design and implementation
- ordered execution of PR readiness and evidence/provenance checks
- chain-level PASS/FAIL merge-gate semantics

Out of scope:
- changing runtime behavior
- changing registry behavior
- changing validator core logic
- adding override/exception merge paths

## Governance Baseline
This chain is consistent with:
- `docs/pr-readiness-validator.md` (Phase35)
- `docs/pr-readiness-validator-implementation.md` (Phase36)
- existing evidence/provenance validation workflow and strict validator behavior

Normative merge rule:
- merge allowed only when chain result is PASS
- any validator failure yields FAIL and blocks merge

## Chain Architecture
Workflow:
- `.github/workflows/validator-chain.yml`

Validators in chain:
1. Evidence/Provenance Validator (`tools/evidence_validator.py`) for changed evidence files
2. PR Readiness Validator (`tools/pr_readiness_validator.py`)

Execution order:
1. Run evidence/provenance validation
2. If evidence/provenance validation passes, run PR readiness validation
3. Publish chain result

## Trigger Model
Triggers:
- `pull_request`
- `workflow_dispatch`

`pull_request` path is authoritative for merge-gate behavior.
`workflow_dispatch` is for manual verification and recovery checks.

## Validator Responsibilities in Chain
### PR Readiness Validator Stage
Validates:
- diff scope
- required PR metadata sections
- evidence references in PR metadata
- branch naming (`codex/phase[0-9]+-.*`)
- completion condition token (`PR-ready`)

Stage failure behavior:
- fail stage
- stop chain progression to downstream stage

### Evidence/Provenance Stage
Validates changed files matching:
- `examples/evidence/*-evidence.json`

Validation mode:
- strict (`--policy strict`)
- CI portability mode (`--ci-mode`)

If no matching evidence file is changed, stage is treated as PASS (not applicable).

Provenance handling:
- provenance integrity checks are enforced through `tools/evidence_validator.py` in strict mode
- this stage satisfies Evidence -> Provenance governance ordering before PR readiness

## PASS / FAIL Semantics
Chain output is binary:
- PASS
- FAIL

PASS condition:
- all required chain stages succeed

FAIL condition:
- any required stage fails

## Failure Behavior
Policy:
- FAIL -> Merge Block

Operational behavior:
- failing stage returns non-zero
- final chain-result job returns non-zero when any required stage failed
- PR remains non-mergeable under governance policy until chain is PASS

## Workflow Responsibilities
Chain workflow responsibilities:
- checkout repository with sufficient history for diff
- setup Python runtime
- execute validator stages in order
- compute and emit final PASS/FAIL status
- fail workflow run on FAIL

## Operational Notes
- no auto-merge behavior is introduced in Phase37
- no exception or override path is introduced in Phase37
- chain remains deterministic and auditable via workflow logs

## Non-goals
- implementing new validator rule sets beyond existing validator responsibilities
- replacing existing validator documents
- modifying repository settings from this phase document
