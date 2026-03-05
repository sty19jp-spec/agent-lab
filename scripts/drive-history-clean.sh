#!/usr/bin/env bash
# drive-history-clean.sh
# Deletes old YYYY-MM history folders from Google Drive.
#
# Usage:
#   drive-history-clean.sh [--retain-months N] [--confirm --delete] [--hard-delete]
#
# Modes:
#   (default)                  dry-run: list folders that would be deleted
#   --confirm --delete         actually move folders to Trash
#   --confirm --delete \
#     --hard-delete            permanently delete (skip Trash)
#
# Required env vars (same as drive-sync.sh):
#   GCP_WIF_PROVIDER, GCP_SERVICE_ACCOUNT, DRIVE_FOLDER_ID
#   ACTIONS_ID_TOKEN_REQUEST_URL, ACTIONS_ID_TOKEN_REQUEST_TOKEN
#
set -euo pipefail

log()  { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { log "INFO  $*"; }
warn() { log "WARN  $*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# ---- Parse args ----
RETAIN_MONTHS=12
DO_CONFIRM=false
DO_DELETE=false
DO_HARD_DELETE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --retain-months)
      shift
      RETAIN_MONTHS="${1:?--retain-months requires a value}"
      ;;
    --confirm)   DO_CONFIRM=true ;;
    --delete)    DO_DELETE=true  ;;
    --hard-delete) DO_HARD_DELETE=true ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

# --hard-delete requires both --confirm and --delete
if $DO_HARD_DELETE && ! ($DO_CONFIRM && $DO_DELETE); then
  die "--hard-delete requires --confirm --delete"
fi

# --delete requires --confirm
if $DO_DELETE && ! $DO_CONFIRM; then
  die "--delete requires --confirm"
fi

DRY_RUN=true
if $DO_CONFIRM && $DO_DELETE; then
  DRY_RUN=false
fi

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/drive-sync.config.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

: "${GCP_WIF_PROVIDER:?missing GCP_WIF_PROVIDER}"
: "${GCP_SERVICE_ACCOUNT:?missing GCP_SERVICE_ACCOUNT}"
: "${DRIVE_FOLDER_ID:?missing DRIVE_FOLDER_ID}"
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?missing ACTIONS_ID_TOKEN_REQUEST_URL}"
: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?missing ACTIONS_ID_TOKEN_REQUEST_TOKEN}"

require_cmd curl
require_cmd jq
require_cmd gcloud

WORKDIR="$(pwd)"
OUTDIR="${WORKDIR}/.drive-sync-out"
mkdir -p "${OUTDIR}"

append_qp() {
  local url="$1" qp="$2"
  if [[ "$url" == *\?* ]]; then printf '%s&%s' "$url" "$qp"
  else printf '%s?%s' "$url" "$qp"; fi
}

# ---- Auth (same pattern as drive-sync.sh) ----
log "Fetching GitHub OIDC token..."
OIDC_URL="$(append_qp "${ACTIONS_ID_TOKEN_REQUEST_URL}" "audience=//iam.googleapis.com/${GCP_WIF_PROVIDER}")"
OIDC_JSON="$(curl -fsSL -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${OIDC_URL}")"
OIDC_TOKEN="$(echo "${OIDC_JSON}" | jq -r '.value')"
[[ -n "${OIDC_TOKEN}" && "${OIDC_TOKEN}" != "null" ]] || die "failed to obtain OIDC token"

OIDC_TOKEN_FILE="${OUTDIR}/oidc-token.jwt"
printf '%s' "${OIDC_TOKEN}" > "${OIDC_TOKEN_FILE}"

log "Creating WIF credential config..."
WIF_CRED_FILE="${OUTDIR}/wif-cred.json"
gcloud iam workload-identity-pools create-cred-config "${GCP_WIF_PROVIDER}" \
  --service-account="${GCP_SERVICE_ACCOUNT}" \
  --output-file="${WIF_CRED_FILE}" \
  --credential-source-file="${OIDC_TOKEN_FILE}" \
  --quiet
[[ -s "${WIF_CRED_FILE}" ]] || die "wif cred file not created"

log "Activating gcloud auth with WIF cred file..."
gcloud auth login --cred-file="${WIF_CRED_FILE}" --quiet

log "Fetching access token (drive scope)..."
ACCESS_TOKEN="$(gcloud auth print-access-token \
  --scopes=https://www.googleapis.com/auth/drive)"
[[ -n "${ACCESS_TOKEN}" ]] || die "gcloud auth print-access-token returned empty"

# ---- Find history folder inside DRIVE_FOLDER_ID ----
log "Looking up 'history' folder under Drive folder ${DRIVE_FOLDER_ID} ..."
HISTORY_QUERY="name='history' and '${DRIVE_FOLDER_ID}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
HISTORY_RESP="$(curl -fsSL \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "$(append_qp "https://www.googleapis.com/drive/v3/files" \
    "q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "${HISTORY_QUERY}")&fields=files(id,name)")")"

HISTORY_FOLDER_ID="$(echo "${HISTORY_RESP}" | jq -r '.files[0].id // empty')"
[[ -n "${HISTORY_FOLDER_ID}" ]] || die "Could not find 'history' folder under ${DRIVE_FOLDER_ID}"
info "Found history folder: ${HISTORY_FOLDER_ID}"

# ---- List YYYY-MM subfolders ----
log "Listing YYYY-MM subfolders inside history ..."
MONTH_QUERY="'${HISTORY_FOLDER_ID}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
MONTH_QUERY_ENC="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "${MONTH_QUERY}")"

ALL_RESP="$(curl -fsSL \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "$(append_qp "https://www.googleapis.com/drive/v3/files" \
    "q=${MONTH_QUERY_ENC}&fields=files(id,name)&pageSize=1000")")"

# ---- Calculate cutoff (retain_months ago, first day of that month) ----
# e.g. today=2026-03 retain=12 → cutoff=2025-03
CUTOFF="$(python3 -c "
import sys
from datetime import date, timedelta

today = date.today()
retain = int(sys.argv[1])
# shift back retain_months months
year  = today.year
month = today.month - retain
while month <= 0:
    month += 12
    year  -= 1
print(f'{year:04d}-{month:02d}')
" "${RETAIN_MONTHS}")"
info "Retain months: ${RETAIN_MONTHS}  |  Cutoff: ${CUTOFF} (folders older than this will be removed)"

# ---- Identify targets ----
# Only touch names matching YYYY-MM exactly
YYYY_MM_RE='^[0-9]{4}-[0-9]{2}$'

mapfile -t NAMES < <(echo "${ALL_RESP}" | jq -r '.files[].name')
mapfile -t IDS   < <(echo "${ALL_RESP}" | jq -r '.files[].id')

DELETE_NAMES=()
DELETE_IDS=()

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  id="${IDS[$i]}"

  # Safety: skip anything that is not YYYY-MM
  if ! [[ "${name}" =~ ${YYYY_MM_RE} ]]; then
    warn "Skipping non-YYYY-MM folder: '${name}' (${id})"
    continue
  fi

  if [[ "${name}" < "${CUTOFF}" ]]; then
    DELETE_NAMES+=("${name}")
    DELETE_IDS+=("${id}")
  fi
done

# ---- Report ----
info "Total YYYY-MM folders found : ${#NAMES[@]}"
info "Folders to delete           : ${#DELETE_NAMES[@]}"
if [[ "${#DELETE_NAMES[@]}" -eq 0 ]]; then
  info "Nothing to delete. Exiting."
  exit 0
fi

echo ""
echo "---- Deletion candidates (older than ${CUTOFF}) ----"
for i in "${!DELETE_NAMES[@]}"; do
  echo "  ${DELETE_NAMES[$i]}  (id: ${DELETE_IDS[$i]})"
done
echo "----------------------------------------------------"
echo ""

if $DRY_RUN; then
  info "DRY-RUN mode. No changes made."
  info "To delete, re-run with: --confirm --delete"
  exit 0
fi

# ---- Delete ----
if $DO_HARD_DELETE; then
  MODE_LABEL="permanent delete"
else
  MODE_LABEL="move to Trash"
fi
info "Mode: ${MODE_LABEL}"

FAILED=0
for i in "${!DELETE_IDS[@]}"; do
  id="${DELETE_IDS[$i]}"
  name="${DELETE_NAMES[$i]}"

  if $DO_HARD_DELETE; then
    HTTP_STATUS="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "https://www.googleapis.com/drive/v3/files/${id}")"
  else
    HTTP_STATUS="$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"trashed":true}' \
      "https://www.googleapis.com/drive/v3/files/${id}?fields=id")"
  fi

  if [[ "${HTTP_STATUS}" =~ ^2 ]]; then
    info "Deleted: ${name} (${id})  HTTP ${HTTP_STATUS}"
  else
    warn "FAILED : ${name} (${id})  HTTP ${HTTP_STATUS}"
    FAILED=$(( FAILED + 1 ))
  fi
done

if [[ "${FAILED}" -gt 0 ]]; then
  die "${FAILED} folder(s) failed to delete. Check warnings above."
fi

info "Done. ${#DELETE_IDS[@]} folder(s) deleted."
