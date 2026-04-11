# Workflow rollback

1. Checkout `chore/adopt-harness-bootstrap`.
2. Copy files from `reports/adoption/workflow_baseline/` back into `.github/workflows/`.
3. Remove `ci-verifier.yml` if full rollback to the pre-adoption set is required.
4. Commit the rollback diff on the adoption branch.
