#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage:
  bash scripts/pre-validate-pr.sh --body-file <path> --title <title> [--base <branch>]
  bash scripts/pre-validate-pr.sh --body-file <path> --validate-only [--base <branch>]

Options:
  --body-file <path>    Rendered PR body file to validate and submit.
  --title <title>       PR title. Required unless --validate-only is set.
  --base <branch>       Base branch for the PR. Defaults to main.
  --head-ref <branch>   Override head branch name.
  --base-sha <sha>      Override base commit SHA.
  --head-sha <sha>      Override head commit SHA.
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
RUNTIME_DIR="${REPO_ROOT}/.runtime"
TRACE_FILE="${CODEX_DEBUG_TRACE_FILE:-${RUNTIME_DIR}/debug-trace.jsonl}"

BODY_FILE=""
TITLE=""
BASE_BRANCH="main"
VALIDATE_ONLY=0
REPORT_FILE="${CODEX_EXECUTION_REPORT_FILE:-${RUNTIME_DIR}/execution-report.json}"
HEAD_REF_OVERRIDE=""
BASE_SHA_OVERRIDE=""
HEAD_SHA_OVERRIDE=""
RUN_ID="${CODEX_RUN_ID:-}"
EXECUTOR_NAME="${CODEX_EXECUTOR_NAME:-codex-cli}"
EXECUTOR_VERSION="${CODEX_EXECUTOR_VERSION:-unknown}"
CURRENT_STAGE="bootstrap"
REPORT_FINALIZED=0
FAILURE_STAGE="none"
ERROR_SUMMARY=""
VALIDATOR_VERSION="unknown"
VALIDATOR_COMMAND=""
PRE_VALIDATION_RESULT="fail"
BASE_COMMIT=""
HEAD_COMMIT=""
HEAD_REF=""
WORKSPACE_CLEAN_BOOL="false"
STARTED_AT=""
STARTED_MS=""
UNTRACKED_FILES_NL=""
CHANGED_FILES_NL=""

now_iso() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

now_ms() {
  "${PYTHON_BIN}" - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

append_trace() {
  local stage="$1"
  local status="$2"
  local message="$3"
  local artifact="${4:-}"
  local validator_version="${5:-}"

  mkdir -p "${RUNTIME_DIR}"
  "${PYTHON_BIN}" - <<'PYEOF' "${TRACE_FILE}" "${stage}" "${status}" "${message}" "${artifact}" "${validator_version}"
import json
import sys
from datetime import datetime, timezone

trace_file, stage, status, message, artifact, validator_version = sys.argv[1:]
event = {
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "stage": stage,
    "status": status,
    "message": message,
}
if artifact:
    event["artifact"] = artifact
if validator_version:
    event["validator_version"] = validator_version

with open(trace_file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=True) + "\n")
PYEOF
}

load_existing_context() {
  local context

  if [[ ! -f "${REPORT_FILE}" ]]; then
    STARTED_AT="$(now_iso)"
    STARTED_MS="$(now_ms)"
    [[ -n "${RUN_ID}" ]] || RUN_ID="$(date -u +'%Y%m%dT%H%M%SZ')-$$"
    return
  fi

  context="$("${PYTHON_BIN}" - <<'PYEOF' "${REPORT_FILE}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

print("\t".join([
    data.get("run_id", ""),
    data.get("executor", {}).get("name", ""),
    data.get("executor", {}).get("version", ""),
    data.get("timing", {}).get("started_at", ""),
    str(data.get("timing", {}).get("started_ms", "")),
]))
PYEOF
)"

  IFS=$'\t' read -r loaded_run_id loaded_executor_name loaded_executor_version loaded_started_at loaded_started_ms <<< "${context}"
  RUN_ID="${RUN_ID:-${loaded_run_id}}"
  EXECUTOR_NAME="${EXECUTOR_NAME:-${loaded_executor_name}}"
  EXECUTOR_VERSION="${EXECUTOR_VERSION:-${loaded_executor_version}}"
  STARTED_AT="${loaded_started_at:-$(now_iso)}"
  STARTED_MS="${loaded_started_ms:-$(now_ms)}"

  [[ -n "${RUN_ID}" ]] || RUN_ID="$(date -u +'%Y%m%dT%H%M%SZ')-$$"
}

write_report() {
  local finished_at="$1"
  local finished_ms="$2"

  "${PYTHON_BIN}" - <<'PYEOF' "${REPORT_FILE}" "${STARTED_AT}" "${STARTED_MS}" "${finished_at}" "${finished_ms}" "${RUN_ID}" "${EXECUTOR_NAME}" "${EXECUTOR_VERSION}" "${HEAD_REF}" "${BASE_COMMIT}" "${HEAD_COMMIT}" "${WORKSPACE_CLEAN_BOOL}" "${UNTRACKED_FILES_NL}" "${CHANGED_FILES_NL}" "${BODY_FILE}" "${TITLE}" "${VALIDATOR_VERSION}" "${PRE_VALIDATION_RESULT}" "${VALIDATOR_COMMAND}" "${FAILURE_STAGE}" "${ERROR_SUMMARY}" "${TRACE_FILE}"
import json
import sys

(
    report_file,
    started_at,
    started_ms,
    finished_at,
    finished_ms,
    run_id,
    executor_name,
    executor_version,
    branch,
    base_commit,
    head_commit,
    workspace_clean,
    untracked_files_nl,
    changed_files_nl,
    body_file,
    title,
    validator_version,
    pre_validation_result,
    validator_command,
    failure_stage,
    error_summary,
    trace_file,
) = sys.argv[1:]

untracked_files = [line for line in untracked_files_nl.splitlines() if line]
changed_files = [line for line in changed_files_nl.splitlines() if line]
started_ms_int = int(started_ms) if started_ms else 0
finished_ms_int = int(finished_ms) if finished_ms else started_ms_int
duration_ms = finished_ms_int - started_ms_int if finished_ms_int >= started_ms_int else 0

report = {
    "schema_version": "phase46-v1",
    "run_id": run_id,
    "executor": {
        "name": executor_name,
        "version": executor_version,
    },
    "repository": {
        "branch": branch,
        "base_commit": base_commit,
        "head_commit": head_commit,
        "workspace_clean": workspace_clean == "true",
        "changed_files_count": len(changed_files),
        "changed_files": changed_files,
        "untracked_files_count": len(untracked_files),
        "untracked_files": untracked_files,
    },
    "pr": {
        "body_file": body_file,
        "title": title,
        "readiness_token": "PR-ready",
    },
    "validation": {
        "validator_version": validator_version,
        "pre_validation_result": pre_validation_result,
        "validator_command": validator_command,
    },
    "timing": {
        "started_at": started_at,
        "started_ms": started_ms_int,
        "finished_at": finished_at,
        "finished_ms": finished_ms_int,
        "duration_ms": duration_ms,
    },
    "artifacts": {
        "execution_report": ".runtime/execution-report.json",
        "debug_trace": ".runtime/debug-trace.jsonl",
    },
    "debug": {
        "trace_enabled": True,
        "failure_stage": failure_stage,
        "error_summary": error_summary,
    },
}

with open(report_file, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")
PYEOF
}

finalize_failure() {
  local message="$1"

  trap - ERR
  if [[ "${REPORT_FINALIZED}" -eq 1 ]]; then
    printf 'ERROR: %s\n' "${message}" >&2
    exit 1
  fi

  FAILURE_STAGE="${CURRENT_STAGE}"
  ERROR_SUMMARY="${message}"
  PRE_VALIDATION_RESULT="fail"
  append_trace "${CURRENT_STAGE}" "error" "${message}" "" "${VALIDATOR_VERSION}"
  write_report "$(now_iso)" "$(now_ms)"
  REPORT_FINALIZED=1
  printf 'ERROR: %s\n' "${message}" >&2
  exit 1
}

die() {
  finalize_failure "$*"
}

on_err() {
  finalize_failure "command failed during ${CURRENT_STAGE}: ${BASH_COMMAND}"
}

trap on_err ERR

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
    --head-ref)
      [[ $# -ge 2 ]] || die "missing value for --head-ref"
      HEAD_REF_OVERRIDE="$2"
      shift 2
      ;;
    --base-sha)
      [[ $# -ge 2 ]] || die "missing value for --base-sha"
      BASE_SHA_OVERRIDE="$2"
      shift 2
      ;;
    --head-sha)
      [[ $# -ge 2 ]] || die "missing value for --head-sha"
      HEAD_SHA_OVERRIDE="$2"
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

CURRENT_STAGE="bootstrap"
mkdir -p "${RUNTIME_DIR}"
git check-ignore -q "${REPORT_FILE}" || die "runtime report must be ignored by git: ${REPORT_FILE}"
git check-ignore -q "${TRACE_FILE}" || die "debug trace must be ignored by git: ${TRACE_FILE}"
if git ls-files --error-unmatch "${REPORT_FILE}" >/dev/null 2>&1; then
  die "runtime report is tracked by git: ${REPORT_FILE}"
fi
if git ls-files --error-unmatch "${TRACE_FILE}" >/dev/null 2>&1; then
  die "debug trace is tracked by git: ${TRACE_FILE}"
fi

load_existing_context
: >> "${TRACE_FILE}"
append_trace "bootstrap" "ok" "initialized PR pre-validation wrapper" ".runtime/debug-trace.jsonl"

mapfile -t UNTRACKED_FILES < <(git ls-files --others --exclude-standard)
UNTRACKED_FILES_NL="$(printf '%s\n' "${UNTRACKED_FILES[@]}")"
if git diff --quiet --ignore-submodules -- && git diff --cached --quiet --ignore-submodules -- && [[ "${#UNTRACKED_FILES[@]}" -eq 0 ]]; then
  WORKSPACE_CLEAN_BOOL="true"
else
  WORKSPACE_CLEAN_BOOL="false"
fi

ensure_clean_worktree

if [[ -z "${BASE_SHA_OVERRIDE}" ]]; then
  git fetch --no-tags origin "${BASE_BRANCH}"
fi

HEAD_REF="${HEAD_REF_OVERRIDE}"
if [[ -z "${HEAD_REF}" ]]; then
  HEAD_REF="$(git branch --show-current)"
fi
[[ -n "${HEAD_REF}" ]] || die "current branch is detached"

BASE_SHA="${BASE_SHA_OVERRIDE}"
if [[ -z "${BASE_SHA}" ]]; then
  BASE_SHA="$(git merge-base "origin/${BASE_BRANCH}" HEAD)"
fi
HEAD_SHA="${HEAD_SHA_OVERRIDE}"
if [[ -z "${HEAD_SHA}" ]]; then
  HEAD_SHA="$(git rev-parse HEAD)"
fi

[[ -n "${BASE_SHA}" ]] || die "failed to determine base sha against origin/${BASE_BRANCH}"
[[ -n "${HEAD_SHA}" ]] || die "failed to determine head sha"
VALIDATOR_VERSION="$(git rev-parse HEAD:tools/pr_readiness_validator.py)"
BASE_COMMIT="${BASE_SHA}"
HEAD_COMMIT="${HEAD_SHA}"
VALIDATOR_COMMAND="${PYTHON_BIN} tools/pr_readiness_validator.py --repo-root . --pr-body-file ${BODY_FILE} --head-ref ${HEAD_REF} --base-sha ${BASE_SHA} --head-sha ${HEAD_SHA}"

mapfile -t CHANGED_FILES < <(git diff --name-only "${BASE_SHA}...${HEAD_SHA}")
[[ "${#CHANGED_FILES[@]}" -gt 0 ]] || die "no changed files detected between origin/${BASE_BRANCH} and HEAD"
CHANGED_FILES_NL="$(printf '%s\n' "${CHANGED_FILES[@]}")"

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

CURRENT_STAGE="pr_body_render"
append_trace "pr_body_render" "ok" "received rendered PR body file for validation" "${BODY_FILE}"

CURRENT_STAGE="pre_validation"
trap - ERR
set +e
"${PYTHON_BIN}" tools/pr_readiness_validator.py \
  --repo-root . \
  --pr-body-file "${BODY_FILE}" \
  --head-ref "${HEAD_REF}" \
  --base-sha "${BASE_SHA}" \
  --head-sha "${HEAD_SHA}"
VALIDATION_STATUS=$?
set -e
trap on_err ERR

if [[ "${VALIDATION_STATUS}" -ne 0 ]]; then
  PRE_VALIDATION_RESULT="fail"
  die "pre-validation failed; see ${REPORT_FILE}"
fi
PRE_VALIDATION_RESULT="pass"
append_trace "pre_validation" "ok" "canonical validator passed" "" "${VALIDATOR_VERSION}"

if [[ "${VALIDATE_ONLY}" -eq 1 ]]; then
  FAILURE_STAGE="none"
  ERROR_SUMMARY=""
  write_report "$(now_iso)" "$(now_ms)"
  REPORT_FINALIZED=1
  log "Local pre-validation passed"
  log "  report    : ${REPORT_FILE}"
  log "  trace     : ${TRACE_FILE}"
  exit 0
fi

CURRENT_STAGE="pr_create"
log "Creating PR from validated body file"
log "  report    : ${REPORT_FILE}"
PR_URL="$(gh pr create \
  --base "${BASE_BRANCH}" \
  --head "${HEAD_REF}" \
  --title "${TITLE}" \
  --body-file "${BODY_FILE}")"
append_trace "pr_create" "ok" "created pull request from validated body file" "${BODY_FILE}"
CURRENT_STAGE="post_create"
append_trace "post_create" "ok" "pull request created" "${PR_URL}"
FAILURE_STAGE="none"
ERROR_SUMMARY=""
write_report "$(now_iso)" "$(now_ms)"
REPORT_FINALIZED=1
printf '%s\n' "${PR_URL}"
