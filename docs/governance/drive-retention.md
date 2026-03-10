# Drive Retention Governance

## Purpose
Define the operational governance baseline for retaining and deleting Drive history artifacts created by this repository.

## Retention Model
Drive artifact layout:

- `latest/`
- `history/YYYY-MM/`

Retention intent:

- `latest/` keeps the current backup view
- `history/YYYY-MM/` keeps monthly history
- history older than the retention cutoff becomes deletion-eligible

## Default Retention Rule
Default retention period:

- 12 months

Deletion unit:

- one `history/YYYY-MM/` folder at a time

Folders that do not match `YYYY-MM` are outside the normal deletion set and should be skipped.

## Deletion Safety Model
Operational sequence:

1. dry-run first
2. human review of deletion candidates
3. explicit delete confirmation
4. optional hard delete only when intentionally chosen

Normal safety posture:

- scheduled execution is dry-run only
- manual delete requires explicit confirmation
- hard delete is exceptional because recovery is not available

## Governance Rules
- Do not treat retention cleanup as a routine background purge without review.
- Do not delete artifacts outside the documented folder pattern.
- Do not reduce the retention window casually; treat it as an operational policy change.
- Prefer trash-based deletion over hard delete when cleanup is required.

## Audit Expectations
Operational evidence for retention activity should be visible in:

- workflow execution history
- workflow logs
- the deletion candidate list for dry-run and delete executions

Manual deletion should be explainable from workflow inputs and logs without relying on undocumented operator memory.

## Exception Handling
Exceptions, such as a shorter retention window or hard delete, should be rare and tied to an explicit operational reason.

If practice changes from the documented default, update repository documentation so governance and operation stay aligned.

## Related Documents
- `runbooks/drive-history-retention.md`
- `docs/runbooks/drive-sync-ops.md`
- `docs/drive-sync/drive-folder-structure.md`
