# Sample Task: docs validation

This sample task validates that repository-local documentation files exist and writes a validation report.

## Task Package Ref
- `task://docs-validation`

## Runtime Bundle Ref
- `bundle://local-docs-validator`

## Run
```bash
python -m runtime.entry \
  --task-package-ref task://docs-validation \
  --runtime-bundle-ref bundle://local-docs-validator \
  --trigger-type manual \
  --requested-operator Executor
```

## Evidence Outputs
- `examples/evidence/docs-validation-report.json`
- `examples/evidence/docs-validation-evidence.json`