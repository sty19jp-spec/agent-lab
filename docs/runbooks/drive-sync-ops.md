# Drive Sync Operations Runbook

## Purpose
Provide an operational summary for the current Drive sync and retention workflows in `agent-lab`.

This document is a concise operator-facing companion to the existing detailed runbooks. It reflects the repository behavior as implemented today.

## Current Workflow Split
There are two distinct operational paths:

1. `Drive Sync (latest + history)`
   - workflow file: `.github/workflows/drive-sync.yml`
   - trigger: `push` to `main`, or `workflow_dispatch`
   - auth model: OAuth refresh token from GitHub Secrets
2. `Drive History Retention`
   - workflow file: `.github/workflows/drive-retention.yml`
   - trigger: weekly `schedule`, or `workflow_dispatch`
   - auth model: GitHub OIDC -> GCP WIF -> Drive API access token

Do not assume both workflows use the same authentication path.

## Routine Operations
### Sync execution
Use `Drive Sync (latest + history)` when the repository snapshot must be uploaded to Drive.

Expected output behavior:

- create a `.tar.gz` archive of the repository working copy
- keep one current artifact in `latest/`
- store a month-scoped archive in `history/YYYY-MM/`

### Retention execution
Use `Drive History Retention` when checking or enforcing monthly archive cleanup.

Expected output behavior:

- scheduled runs stay in dry-run mode
- manual runs can stay dry-run or perform deletion
- deletion scope is limited to `history/YYYY-MM/` folders older than the cutoff

## Runbook Shortcuts
### Manual sync

```bash
gh workflow run drive-sync.yml --ref main
gh run list --workflow "Drive Sync (latest + history)" --limit 5
gh run view <RUN_ID> --log
```

### Manual retention dry-run

```bash
gh workflow run drive-retention.yml --ref main \
  -f retain_months=12
gh run list --workflow "Drive History Retention" --limit 5
gh run view <RUN_ID> --log
```

### Manual retention delete

```bash
gh workflow run drive-retention.yml --ref main \
  -f retain_months=12 \
  -f confirm_delete=yes
```

Add `-f hard_delete=yes` only for an intentional permanent delete.

## Authentication Notes
### Sync path
`scripts/drive-sync.sh` currently requires:

- `DRIVE_FOLDER_ID`
- `DRIVE_OAUTH_CLIENT_ID`
- `DRIVE_OAUTH_CLIENT_SECRET`
- `DRIVE_OAUTH_REFRESH_TOKEN`

This path obtains an OAuth access token directly from Google.

### Retention path
`scripts/drive-history-clean.sh` currently requires:

- `GCP_WIF_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `DRIVE_FOLDER_ID`
- `ACTIONS_ID_TOKEN_REQUEST_URL`
- `ACTIONS_ID_TOKEN_REQUEST_TOKEN`

This path exchanges the GitHub OIDC token through GCP WIF and then calls Drive APIs.

## Incident Triage
### Sync job fails
Check first:

1. whether the OAuth secrets exist and are current
2. whether `DRIVE_FOLDER_ID` points to the correct parent folder
3. whether the Drive API response in the preflight log is successful

Useful log markers:

- `Obtaining OAuth access token...`
- `Preflight HTTP=`
- `Uploading`
- `Drive upload HTTP=`

### Retention job fails
Check first:

1. whether the workflow still has `id-token: write`
2. whether WIF provider and service account values are correct
3. whether the `history/` folder exists under the configured Drive root

Useful log markers:

- `Fetching GitHub OIDC token...`
- `Creating WIF credential config...`
- `Activating gcloud auth with WIF cred file...`
- `Deletion candidates`
- `DRY-RUN mode. No changes made.`

## Safety Rules
- Treat scheduled retention as audit-only unless a human intentionally triggers delete.
- Prefer dry-run before any deletion workflow_dispatch.
- Do not change scripts or secrets as part of a normal operational response unless the task explicitly requires it.
- Keep Drive folder naming consistent with `latest/` and `history/YYYY-MM/`.

## Related Documents
- `docs/RUNBOOK-drive-sync.md`
- `runbooks/drive-history-retention.md`
- `docs/drive-sync/drive-folder-structure.md`
