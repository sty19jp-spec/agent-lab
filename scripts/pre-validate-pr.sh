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

resolve_python() {
  if command -v python >/dev/null 2>&1; then
    printf 'python'
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf 'python3'
    return
  fi
  die "missing command: python or python3"
}

ensure_clean_worktree() {
  git diff --quiet --ignore-submodules -- || die "working tree has unstaged changes"
  git diff --cached --quiet --ignore-submodules -- || die "working tree has staged changes"
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || die "untracked files exist"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PYTHON_BIN="$(resolve_python)"

BODY_FILE=""
TITLE=""
BASE_BRANCH="main"
VALIDATE_ONLY=0
REPORT_FILE="${REPO_ROOT}/.runtime/execution-report.json"

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
if [[ "${VALIDATE_ONLY}" -eq 0 ]]; then
  require_cmd gh
fi

cd "${REPO_ROOT}"

[[ -f "${BODY_FILE}" ]] || die "PR body file not found: ${BODY_FILE}"

ensure_clean_worktree

mkdir -p "${REPO_ROOT}/.runtime"
git check-ignore -q "${REPORT_FILE}" || die "runtime report must be ignored by git: ${REPORT_FILE}"
if git ls-files --error-unmatch "${REPORT_FILE}" >/dev/null 2>&1; then
  die "runtime report is tracked by git: ${REPORT_FILE}"
fi

git fetch --no-tags origin "${BASE_BRANCH}"

HEAD_REF="$(git branch --show-current)"
[[ -n "${HEAD_REF}" ]] || die "current branch is detached"

BASE_SHA="$(git merge-base "origin/${BASE_BRANCH}" HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"

[[ -n "${BASE_SHA}" ]] || die "failed to determine base sha against origin/${BASE_BRANCH}"
[[ -n "${HEAD_SHA}" ]] || die "failed to determine head sha"
VALIDATOR_VERSION="$(git rev-parse HEAD:tools/pr_readiness_validator.py)"

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
    "${PYTHON_BIN}" tools/evidence_validator.py \
      --evidence-file "${evidence_file}" \
      --schema-name execution-evidence \
      --schema-version v1 \
      --policy strict \
      --ci-mode
  done
fi

set +e
"${PYTHON_BIN}" tools/pr_readiness_validator.py \
  --repo-root . \
  --pr-body-file "${BODY_FILE}" \
  --head-ref "${HEAD_REF}" \
  --base-sha "${BASE_SHA}" \
  --head-sha "${HEAD_SHA}"
VALIDATION_STATUS=$?
set -e

REPORT_TIMESTAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
"${PYTHON_BIN}" - <<'PYEOF' "${REPORT_FILE}" "${HEAD_REF}" "${VALIDATOR_VERSION}" "${BODY_FILE}" "${VALIDATION_STATUS}" "${REPORT_TIMESTAMP}" "${CHANGED_FILES[@]}"
import json
import sys

report_file = sys.argv[1]
branch = sys.argv[2]
validator_version = sys.argv[3]
pr_body_file = sys.argv[4]
validation_status = sys.argv[5] == "0"
timestamp = sys.argv[6]
changed_files = sys.argv[7:]

with open(report_file, "w", encoding="utf-8") as fh:
    json.dump(
        {
            "branch": branch,
            "validator_version": validator_version,
            "pr_body_file": pr_body_file,
            "pre_validation_passed": validation_status,
            "changed_files": changed_files,
            "timestamp": timestamp,
        },
        fh,
        indent=2,
    )
    fh.write("\n")
PYEOF

if [[ "${VALIDATION_STATUS}" -ne 0 ]]; then
  die "pre-validation failed; see ${REPORT_FILE}"
fi

if [[ "${VALIDATE_ONLY}" -eq 1 ]]; then
  log "Local pre-validation passed"
  log "  report    : ${REPORT_FILE}"
  exit 0
fi

log "Creating PR from validated body file"
log "  report    : ${REPORT_FILE}"
exec gh pr create \
  --base "${BASE_BRANCH}" \
  --head "${HEAD_REF}" \
  --title "${TITLE}" \
  --body-file "${BODY_FILE}"
