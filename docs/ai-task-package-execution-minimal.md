# AI Task Package Execution (Phase23)

Phase23 introduces a minimal end-to-end task package execution on top of the existing runtime.

## Added Repository Objects
- `task/`: version-controlled task packages (`task.yaml`)
- `bundle/`: version-controlled runtime bundles (`bundle.yaml`)
- `examples/`: runnable sample task and generated evidence

## Minimal Run Command
```bash
python -m runtime.entry \
  --task-package-ref task://docs-validation \
  --runtime-bundle-ref bundle://local-docs-validator \
  --trigger-type manual \
  --requested-operator Executor
```

## Expected Outputs
- Validation report: `examples/evidence/docs-validation-report.json`
- Runtime evidence: `examples/evidence/docs-validation-evidence.json`

Both outputs are repository-visible and can be reviewed in git diff/history.