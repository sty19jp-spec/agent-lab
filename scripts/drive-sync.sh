#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# ---- Required env (set in GitHub Secrets or workflow env) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/drive-sync.config.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  source "${CONFIG_FILE}"
fi

: "${DRIVE_FOLDER_ID:?missing DRIVE_FOLDER_ID (Drive folder id)}"

: "${DRIVE_OAUTH_CLIENT_ID:?missing DRIVE_OAUTH_CLIENT_ID}"
: "${DRIVE_OAUTH_CLIENT_SECRET:?missing DRIVE_OAUTH_CLIENT_SECRET}"
: "${DRIVE_OAUTH_REFRESH_TOKEN:?missing DRIVE_OAUTH_REFRESH_TOKEN}"

require_cmd curl
require_cmd jq
require_cmd tar
require_cmd python3

WORKDIR="$(pwd)"
OUTDIR="${WORKDIR}/.drive-sync-out"
mkdir -p "${OUTDIR}"

# ---- OAuth access token ----
log "Obtaining OAuth access token..."

ACCESS_TOKEN="$(
curl -s https://oauth2.googleapis.com/token \
  -d client_id="${DRIVE_OAUTH_CLIENT_ID}" \
  -d client_secret="${DRIVE_OAUTH_CLIENT_SECRET}" \
  -d refresh_token="${DRIVE_OAUTH_REFRESH_TOKEN}" \
  -d grant_type=refresh_token \
  | jq -r '.access_token'
)"

[[ -n "${ACCESS_TOKEN}" && "${ACCESS_TOKEN}" != "null" ]] || die "failed to obtain OAuth access token"

# ---- Preflight: inspect root Drive folder ----
log "DEBUG: DRIVE_FOLDER_ID len=${#DRIVE_FOLDER_ID} q=$(printf %q "$DRIVE_FOLDER_ID")"
log "Preflight: inspecting Drive folder ${DRIVE_FOLDER_ID}..."
_PREFLIGHT_BODY="${OUTDIR}/preflight.json"
_PREFLIGHT_HTTP="$(curl -sS -o "${_PREFLIGHT_BODY}" -w '%{http_code}' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://www.googleapis.com/drive/v3/files/${DRIVE_FOLDER_ID}?supportsAllDrives=true&fields=id,name,driveId,capabilities")"
log "Preflight HTTP=${_PREFLIGHT_HTTP}"
cat "${_PREFLIGHT_BODY}" >&2

# ---- Drive API helpers ----

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

drive_create_folder() {
  local name="$1" parent="$2"
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"mimeType\":\"application/vnd.google-apps.folder\",\"parents\":[\"${parent}\"]}" \
    "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true&fields=id" \
    | jq -r '.id'
}

drive_find_or_create_folder() {
  local name="$1" parent="$2"
  local fid
  fid="$(drive_find_folder "${name}" "${parent}")"
  if [[ -z "${fid}" ]]; then
    log "  Creating folder '${name}'..." >&2
    fid="$(drive_create_folder "${name}" "${parent}")"
  fi
  [[ -n "${fid}" && "${fid}" != "null" ]] || die "failed to find/create Drive folder '${name}'"
  printf '%s' "${fid}"
}

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

drive_upload_file() {
  local local_path="$1" drive_name="$2" parent_id="$3"
  local boundary="drivesync_boundary_$$"
  local metadata="{\"name\":\"${drive_name}\",\"parents\":[\"${parent_id}\"]}"
  local body_file="${OUTDIR}/upload_body_$$.tmp"
  local resp_file="${OUTDIR}/upload_resp_$$.json"

  python3 - "${boundary}" "${metadata}" "${local_path}" "${body_file}" <<'PYEOF'
import sys
boundary, metadata, file_path, output_path = sys.argv[1:]
with open(file_path, 'rb') as f:
    file_data = f.read()
with open(output_path, 'wb') as out:
    out.write(('--' + boundary + '\r\n').encode())
    out.write(b'Content-Type: application/json; charset=UTF-8\r\n')
    out.write(b'\r\n')
    out.write(metadata.encode('utf-8'))
    out.write(b'\r\n')
    out.write(('--' + boundary + '\r\n').encode())
    out.write(b'Content-Type: application/gzip\r\n')
    out.write(b'\r\n')
    out.write(file_data)
    out.write(b'\r\n')
    out.write(('--' + boundary + '--\r\n').encode())
PYEOF

  local http_code
  http_code="$(curl -sS -X POST \
    -o "${resp_file}" -w '%{http_code}' \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: multipart/related; boundary=${boundary}" \
    --data-binary "@${body_file}")"
  rm -f "${body_file}"

  log "Drive upload HTTP=${http_code} (${drive_name})" >&2
  if [[ "${http_code}" != "200" && "${http_code}" != "201" ]]; then
    echo "Drive upload error body:" >&2
    cat "${resp_file}" >&2
    rm -f "${resp_file}"
    die "upload failed for '${drive_name}' (HTTP ${http_code})"
  fi

  local file_id
  file_id="$(jq -r '.id' "${resp_file}")"
  rm -f "${resp_file}"
  [[ -n "${file_id}" && "${file_id}" != "null" ]] || die "upload succeeded but no id returned for '${drive_name}'"
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
