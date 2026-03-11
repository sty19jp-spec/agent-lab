#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  bash scripts/pre-validate-pr.sh --body-file <path> --title <title> [--base <branch>]
  bash scripts/pre-validate-pr.sh --body-file <path> --validate-only [--base <branch>]

Options:
  --body-file <path>    Rendered PR body file to validate and submit.
  --title <title>       PR title. Required unless --validate-only is set.
  --base <branch>       Base branch for the PR. Defaults to main.
  --validate-only       Run local pre-validation only. Do not create the PR.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

ensure_clean_worktree() {
  git diff --quiet --ignore-submodules -- || die "working tree has unstaged changes"
  git diff --cached --quiet --ignore-submodules -- || die "working tree has staged changes"
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || die "untracked files exist"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BODY_FILE=""
TITLE=""
BASE_BRANCH="main"
VALIDATE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file)
      [[ $# -ge 2 ]] || die "missing value for --body-file"
      BODY_FILE="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || die "missing value for --title"
      TITLE="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || die "missing value for --base"
      BASE_BRANCH="$2"
      shift 2
      ;;
    --validate-only)
      VALIDATE_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${BODY_FILE}" ]] || die "--body-file is required"
if [[ "${VALIDATE_ONLY}" -eq 0 && -z "${TITLE}" ]]; then
  die "--title is required unless --validate-only is set"
fi

require_cmd git
require_cmd python3
if [[ "${VALIDATE_ONLY}" -eq 0 ]]; then
  require_cmd gh
fi

cd "${REPO_ROOT}"

[[ -f "${BODY_FILE}" ]] || die "PR body file not found: ${BODY_FILE}"

ensure_clean_worktree

git fetch --no-tags origin "${BASE_BRANCH}"

HEAD_REF="$(git branch --show-current)"
[[ -n "${HEAD_REF}" ]] || die "current branch is detached"

BASE_SHA="$(git merge-base "origin/${BASE_BRANCH}" HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"

[[ -n "${BASE_SHA}" ]] || die "failed to determine base sha against origin/${BASE_BRANCH}"
[[ -n "${HEAD_SHA}" ]] || die "failed to determine head sha"

mapfile -t CHANGED_FILES < <(git diff --name-only "${BASE_SHA}...${HEAD_SHA}")
[[ "${#CHANGED_FILES[@]}" -gt 0 ]] || die "no changed files detected between origin/${BASE_BRANCH} and HEAD"

log "PR pre-validation"
log "  branch    : ${HEAD_REF}"
log "  base      : ${BASE_BRANCH}"
log "  body file : ${BODY_FILE}"
log "  changed   : ${#CHANGED_FILES[@]} file(s)"

mapfile -t EVIDENCE_FILES < <(printf '%s\n' "${CHANGED_FILES[@]}" | grep '^examples/evidence/.*-evidence\.json$' || true)
if [[ "${#EVIDENCE_FILES[@]}" -eq 0 ]]; then
  log "  evidence  : no changed evidence JSON files; PASS"
else
  for evidence_file in "${EVIDENCE_FILES[@]}"; do
    log "  evidence  : validating ${evidence_file}"
    python3 tools/evidence_validator.py \
      --evidence-file "${evidence_file}" \
      --schema-name execution-evidence \
      --schema-version v1 \
      --policy strict \
      --ci-mode
  done
fi

python3 tools/pr_readiness_validator.py \
  --repo-root . \
  --pr-body-file "${BODY_FILE}" \
  --head-ref "${HEAD_REF}" \
  --base-sha "${BASE_SHA}" \
  --head-sha "${HEAD_SHA}"

if [[ "${VALIDATE_ONLY}" -eq 1 ]]; then
  log "Local pre-validation passed"
  exit 0
fi

log "Creating PR from validated body file"
exec gh pr create \
  --base "${BASE_BRANCH}" \
  --head "${HEAD_REF}" \
  --title "${TITLE}" \
  --body-file "${BODY_FILE}"
