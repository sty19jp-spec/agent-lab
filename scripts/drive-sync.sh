#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# ---- Required env (set in GitHub Secrets or workflow env) ----
: "${GCP_WIF_PROVIDER:?missing GCP_WIF_PROVIDER (WIF provider resource name)}"
: "${GCP_SERVICE_ACCOUNT:?missing GCP_SERVICE_ACCOUNT (service account email)}"
: "${DRIVE_FOLDER_ID:?missing DRIVE_FOLDER_ID (Drive folder id)}"

# GitHub OIDC runtime env (provided by Actions runner)
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?missing ACTIONS_ID_TOKEN_REQUEST_URL (Actions OIDC url)}"
: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?missing ACTIONS_ID_TOKEN_REQUEST_TOKEN (Actions OIDC token)}"

require_cmd curl
require_cmd jq
require_cmd gcloud

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
OIDC_URL="$(append_qp "${ACTIONS_ID_TOKEN_REQUEST_URL}" "audience=${GCP_WIF_PROVIDER}")"
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

# 4) Access token confirm
log "Checking access token..."
ACCESS_TOKEN="$(gcloud auth print-access-token)"
[[ -n "${ACCESS_TOKEN}" ]] || die "gcloud auth print-access-token returned empty"

# 5) Drive API connectivity (folder list)
log "Drive API connectivity check..."
curl -fsSL \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://www.googleapis.com/drive/v3/files?q='${DRIVE_FOLDER_ID}'+in+parents&fields=files(id,name)" \
  >/dev/null

log "OK: WIF auth + access token + Drive API connectivity passed (skeleton)."
