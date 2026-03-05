#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# ---- Required env (set in GitHub Secrets or workflow env) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/drive-sync.config.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

: "${GCP_WIF_PROVIDER:?missing GCP_WIF_PROVIDER (WIF provider resource name)}"
: "${GCP_SERVICE_ACCOUNT:?missing GCP_SERVICE_ACCOUNT (service account email)}"
: "${DRIVE_FOLDER_ID:?missing DRIVE_FOLDER_ID (Drive folder id)}"

# GitHub OIDC runtime env (provided by Actions runner)
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?missing ACTIONS_ID_TOKEN_REQUEST_URL (Actions OIDC url)}"
: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?missing ACTIONS_ID_TOKEN_REQUEST_TOKEN (Actions OIDC token)}"

require_cmd curl
require_cmd jq
require_cmd gcloud
require_cmd tar

WORKDIR="$(pwd)"
OUTDIR="${WORKDIR}/.drive-sync-out"
mkdir -p "${OUTDIR}"

append_qp() {
  local url="$1"
  local qp="$2"
  if [[ "$url" == *\?* ]]; then
    printf '%s&%s' "$url" "$qp"
  else
    printf '%s?%s' "$url" "$qp"
  fi
}

# 1) Fetch GitHub OIDC token (audience = WIF provider)
log "Fetching GitHub OIDC token..."
OIDC_URL="$(append_qp "${ACTIONS_ID_TOKEN_REQUEST_URL}" "audience=//iam.googleapis.com/${GCP_WIF_PROVIDER}")"
OIDC_JSON="$(curl -fsSL -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" "${OIDC_URL}")"
OIDC_TOKEN="$(echo "${OIDC_JSON}" | jq -r '.value')"
[[ -n "${OIDC_TOKEN}" && "${OIDC_TOKEN}" != "null" ]] || die "failed to obtain OIDC token"

OIDC_TOKEN_FILE="${OUTDIR}/oidc-token.jwt"
printf '%s' "${OIDC_TOKEN}" > "${OIDC_TOKEN_FILE}"

# 2) Create external account credentials config for gcloud (WIF)
log "Creating WIF credential config..."
WIF_CRED_FILE="${OUTDIR}/wif-cred.json"
gcloud iam workload-identity-pools create-cred-config "${GCP_WIF_PROVIDER}" \
  --service-account="${GCP_SERVICE_ACCOUNT}" \
  --output-file="${WIF_CRED_FILE}" \
  --credential-source-file="${OIDC_TOKEN_FILE}" \
  --quiet

[[ -s "${WIF_CRED_FILE}" ]] || die "wif cred file not created"

# 3) Activate gcloud auth via cred file
log "Activating gcloud auth with WIF cred file..."
gcloud auth login --cred-file="${WIF_CRED_FILE}" --quiet

# 4) Obtain Drive-scoped access token
# Note: --scopes is silently ignored for external_account (WIF) credentials.
# Workaround: get a cloud-platform token first, then call generateAccessToken
# via the IAM Credentials API to obtain a Drive-scoped token explicitly.
log "Fetching base access token (cloud-platform)..."
_GCP_TOKEN="$(gcloud auth print-access-token)"
[[ -n "${_GCP_TOKEN}" ]] || die "gcloud auth print-access-token returned empty"

log "Generating Drive-scoped access token via IAM Credentials API..."
ACCESS_TOKEN="$(curl -fsSL -X POST \
  -H "Authorization: Bearer ${_GCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"scope":["https://www.googleapis.com/auth/drive"]}' \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${GCP_SERVICE_ACCOUNT}:generateAccessToken" \
  | jq -r '.accessToken')"
[[ -n "${ACCESS_TOKEN}" && "${ACCESS_TOKEN}" != "null" ]] || die "failed to generate Drive-scoped access token"

# ---- Drive API helpers ----

# drive_find_folder <name> <parent_id>  →  folder_id or empty
drive_find_folder() {
  local name="$1" parent="$2"
  local q="name='${name}' and '${parent}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
  local q_enc
  q_enc="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "${q}")"
  curl -fsSL \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://www.googleapis.com/drive/v3/files?includeItemsFromAllDrives=true&supportsAllDrives=true&q=${q_enc}&fields=files(id)" \
    | jq -r '.files[0].id // empty'
}

# drive_create_folder <name> <parent_id>  →  folder_id
drive_create_folder() {
  local name="$1" parent="$2"
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"mimeType\":\"application/vnd.google-apps.folder\",\"parents\":[\"${parent}\"]}" \
    "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true&fields=id" \
    | jq -r '.id'
}

# drive_find_or_create_folder <name> <parent_id>  →  folder_id
drive_find_or_create_folder() {
  local name="$1" parent="$2"
  local fid
  fid="$(drive_find_folder "${name}" "${parent}")"
  if [[ -z "${fid}" ]]; then
    log "  Creating folder '${name}'..."
    fid="$(drive_create_folder "${name}" "${parent}")"
  fi
  [[ -n "${fid}" && "${fid}" != "null" ]] || die "failed to find/create Drive folder '${name}'"
  printf '%s' "${fid}"
}

# drive_delete_file_if_exists <name> <parent_id>
drive_delete_file_if_exists() {
  local name="$1" parent="$2"
  local q="name='${name}' and '${parent}' in parents and trashed=false"
  local q_enc
  q_enc="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "${q}")"
  local file_id
  file_id="$(curl -fsSL \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://www.googleapis.com/drive/v3/files?includeItemsFromAllDrives=true&supportsAllDrives=true&q=${q_enc}&fields=files(id)" \
    | jq -r '.files[0].id // empty')"
  if [[ -n "${file_id}" ]]; then
    log "  Trashing existing '${name}' (${file_id})..."
    curl -fsSL -X PATCH \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"trashed":true}' \
      "https://www.googleapis.com/drive/v3/files/${file_id}?supportsAllDrives=true&fields=id" \
      >/dev/null
  fi
}

# drive_upload_file <local_path> <drive_name> <parent_id>  →  file_id
drive_upload_file() {
  local local_path="$1" drive_name="$2" parent_id="$3"
  local boundary="drivesync_boundary_$$"
  local metadata="{\"name\":\"${drive_name}\",\"parents\":[\"${parent_id}\"]}"
  local body_file="${OUTDIR}/upload_body_$$.tmp"

  {
    printf -- '--%s\r\n' "${boundary}"
    printf 'Content-Type: application/json; charset=UTF-8\r\n\r\n'
    printf '%s\r\n' "${metadata}"
    printf -- '--%s\r\n' "${boundary}"
    printf 'Content-Type: application/octet-stream\r\n\r\n'
    cat "${local_path}"
    printf '\r\n'
    printf -- '--%s--\r\n' "${boundary}"
  } > "${body_file}"

  local file_id
  file_id="$(curl -fsSL -X POST \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: multipart/related; boundary=${boundary}" \
    --data-binary "@${body_file}" \
    | jq -r '.id')"
  rm -f "${body_file}"
  [[ -n "${file_id}" && "${file_id}" != "null" ]] || die "upload failed for '${drive_name}'"
  printf '%s' "${file_id}"
}

# ---- Step 1: Create archive ----
ARCHIVE_DIR="${OUTDIR}/archives"
mkdir -p "${ARCHIVE_DIR}"

YYYYMM="$(date -u +'%Y-%m')"
ARCHIVE_LATEST="${ARCHIVE_DIR}/backup-latest.tar.gz"
ARCHIVE_HISTORY="${ARCHIVE_DIR}/backup-${YYYYMM}.tar.gz"

log "Creating archive (excluding .git, .claude, .drive-sync-out)..."
tar -czf "${ARCHIVE_LATEST}" \
  --exclude='./.git' \
  --exclude='./.claude' \
  --exclude='./.drive-sync-out' \
  -C "${WORKDIR}" .
cp "${ARCHIVE_LATEST}" "${ARCHIVE_HISTORY}"
log "Archive size: $(du -sh "${ARCHIVE_LATEST}" | cut -f1)"

# ---- Step 2: Upload to latest/ ----
log "Resolving latest/ folder..."
LATEST_FOLDER_ID="$(drive_find_or_create_folder "latest" "${DRIVE_FOLDER_ID}")"
log "latest/ id: ${LATEST_FOLDER_ID}"

log "Uploading backup-latest.tar.gz..."
drive_delete_file_if_exists "backup-latest.tar.gz" "${LATEST_FOLDER_ID}"
LATEST_FILE_ID="$(drive_upload_file "${ARCHIVE_LATEST}" "backup-latest.tar.gz" "${LATEST_FOLDER_ID}")"
log "Uploaded latest: ${LATEST_FILE_ID}"

# ---- Steps 3-4: Upload to history/YYYY-MM/ ----
log "Resolving history/ folder..."
HISTORY_FOLDER_ID="$(drive_find_or_create_folder "history" "${DRIVE_FOLDER_ID}")"
log "history/ id: ${HISTORY_FOLDER_ID}"

log "Resolving history/${YYYYMM}/ folder..."
MONTH_FOLDER_ID="$(drive_find_or_create_folder "${YYYYMM}" "${HISTORY_FOLDER_ID}")"
log "history/${YYYYMM}/ id: ${MONTH_FOLDER_ID}"

log "Uploading backup-${YYYYMM}.tar.gz..."
drive_delete_file_if_exists "backup-${YYYYMM}.tar.gz" "${MONTH_FOLDER_ID}"
HISTORY_FILE_ID="$(drive_upload_file "${ARCHIVE_HISTORY}" "backup-${YYYYMM}.tar.gz" "${MONTH_FOLDER_ID}")"
log "Uploaded history/${YYYYMM}: ${HISTORY_FILE_ID}"

log "Drive Sync complete. latest=${LATEST_FILE_ID}  history/${YYYYMM}=${HISTORY_FILE_ID}"
