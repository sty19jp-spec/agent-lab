# AI Task Registry (Layer5 Phase24)

## 1. Purpose
Define a lightweight in-repository AI Task Registry for deterministic task and bundle discovery, and fix the Codex CLI execution rule for Executor runs.

This phase is specification-first and keeps existing Phase23 runtime behavior.

## 2. Scope
Applies to:
- repository registry structure (`task/`, `bundle/`, `runtime/`)
- deterministic discovery rules for task packages
- deterministic resolution rules for runtime bundles
- Codex CLI execution policy for runtime invocation

Out of scope:
- external service orchestration changes
- governance expansion beyond existing PR/evidence workflow
- destructive or security-sensitive automation changes

## 3. Registry Structure
Canonical repository layout:

```text
task/
  registry.yaml
  <task-slug>/
    task.yaml

bundle/
  registry.yaml
  <bundle-slug>/
    bundle.yaml

runtime/
  registry.yaml
  entry.py
  loader.py
  discovery.py
  policy.py
  engine.py
  evidence.py
```

Registry intent:
- `task/registry.yaml`: source list of managed task package refs.
- `bundle/registry.yaml`: source list of managed runtime bundle refs.
- `runtime/registry.yaml`: runtime policy metadata including executor mode.

## 4. Task Discovery Rules (Deterministic)
Task refs accepted by runtime:
- direct file path
- direct directory path (resolved to `task.yaml`)
- logical ref `task://<task-slug>`
- logical ref with version suffix `task://<task-slug>@<version>` (suffix ignored for local resolution)

Deterministic resolution order for task refs:
1. If input path exists and is a file: use that file.
2. If input path exists and is a directory: use `<dir>/task.yaml`.
3. Otherwise resolve logical candidates in fixed order:
   - `task/<task-slug>/task.yaml`
   - `task/<task-slug>.yaml`
4. First existing file wins.
5. If no candidate exists, discovery fails for task package.

Constraint rules:
- `<task-slug>` should be unique in repository.
- `task.yaml.task_id` should be stable across revisions.
- `task.yaml.bundle` must point to a resolvable bundle ref.

## 5. Bundle Registry Rules
Bundle refs accepted by runtime:
- direct file path
- direct directory path (resolved to `bundle.yaml`)
- logical ref `bundle://<bundle-slug>`
- logical ref with version suffix `bundle://<bundle-slug>@<version>` (suffix ignored for local resolution)

Deterministic resolution order for bundle refs:
1. If input path exists and is a file: use that file.
2. If input path exists and is a directory: use `<dir>/bundle.yaml`.
3. Otherwise resolve logical candidates in fixed order:
   - `bundle/<bundle-slug>/bundle.yaml`
   - `bundle/<bundle-slug>.yaml`
4. First existing file wins.
5. If no candidate exists, discovery fails for runtime bundle.

Constraint rules:
- `<bundle-slug>` should be unique in repository.
- `bundle.yaml.bundle_id` should match logical slug for traceability.
- `bundle.yaml.executor` must align with requested operator in runtime preflight.

## 6. Codex CLI Execution Rule
Executor baseline for this project:
- Codex CLI runs in autonomous mode equivalent to `codex --ask-for-approval never`.
- Interactive approval UI is not part of normal execution.
- Human escalation is required only for destructive or security-related operations.
- WSL Ubuntu is the baseline execution environment.
- GitHub repository (`main`) remains source of truth.

Reference runtime invocation:

```bash
python3 -m runtime.entry \
  --task-package-ref task://docs-validation \
  --runtime-bundle-ref bundle://local-docs-validator \
  --trigger-type manual \
  --requested-operator Executor
```

Required outputs:
- execution report artifact (task-defined)
- execution evidence JSON (repository-visible)

## 7. Governance Alignment
This registry is consistent with existing controls:
- Gate A: canonical set validation
- Gate B: task validation / bundle validation / task-bundle binding
- PR-based review and merge flow
- evidence-first audit trail

## 8. Phase24 Minimal Adoption Rules
- Keep registry manifests small and explicit.
- Prefer adding new tasks/bundles under canonical directories.
- Avoid introducing runtime coupling to registry manifests in this phase.
- Expand only when a new task or bundle is introduced.
