#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_DIR="${REPO_ROOT}/.runtime"
TRACE_FILE="${RUNTIME_DIR}/debug-trace.jsonl"
REPORT_FILE="${RUNTIME_DIR}/execution-report.json"
CURRENT_STAGE="bootstrap"
REPORT_FINALIZED=0
RUN_ID=""
EXECUTOR_NAME="${CODEX_EXECUTOR_NAME:-codex-cli}"
EXECUTOR_VERSION="${CODEX_EXECUTOR_VERSION:-unknown}"
VALIDATOR_VERSION="unknown"
STARTED_AT=""
STARTED_MS=""
FAILURE_STAGE="none"
ERROR_SUMMARY=""
CURRENT_BRANCH=""
BASE_COMMIT=""
HEAD_COMMIT=""

resolve_python() {
  if command -v python >/dev/null 2>&1; then
    printf 'python'
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf 'python3'
    return
  fi
  printf ''
}

PYTHON_BIN="$(resolve_python)"

now_iso() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

now_ms() {
  if [[ -n "${PYTHON_BIN}" ]]; then
    "${PYTHON_BIN}" - <<'PY'
import time
print(int(time.time() * 1000))
PY
    return
  fi
  date -u +%s000
}

append_trace() {
  local stage="$1"
  local status="$2"
  local message="$3"
  local artifact="${4:-}"

  [[ -n "${PYTHON_BIN}" ]] || return

  mkdir -p "${RUNTIME_DIR}"
  "${PYTHON_BIN}" - <<'PYEOF' "${TRACE_FILE}" "${stage}" "${status}" "${message}" "${artifact}"
import json
import sys
from datetime import datetime, timezone

trace_file, stage, status, message, artifact = sys.argv[1:]
event = {
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "stage": stage,
    "status": status,
    "message": message,
}
if artifact:
    event["artifact"] = artifact

with open(trace_file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=True) + "\n")
PYEOF
}

write_report() {
  local finished_at="$1"
  local finished_ms="$2"

  [[ -n "${PYTHON_BIN}" ]] || return

  "${PYTHON_BIN}" - <<'PYEOF' "${REPORT_FILE}" "${STARTED_AT}" "${STARTED_MS}" "${finished_at}" "${finished_ms}" "${RUN_ID}" "${EXECUTOR_NAME}" "${EXECUTOR_VERSION}" "${CURRENT_BRANCH}" "${BASE_COMMIT}" "${HEAD_COMMIT}" "${VALIDATOR_VERSION}" "${FAILURE_STAGE}" "${ERROR_SUMMARY}" "${TRACE_FILE}"
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
    validator_version,
    failure_stage,
    error_summary,
    trace_file,
) = sys.argv[1:]

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
        "workspace_clean": True,
        "changed_files_count": 0,
        "changed_files": [],
        "untracked_files_count": 0,
        "untracked_files": [],
    },
    "pr": {
        "body_file": "",
        "title": "",
        "readiness_token": "PR-ready",
    },
    "validation": {
        "validator_version": validator_version,
        "pre_validation_result": "pending",
        "validator_command": "",
    },
    "timing": {
        "started_at": started_at,
        "finished_at": finished_at,
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
  append_trace "${CURRENT_STAGE}" "error" "${message}"
  write_report "$(now_iso)" "$(now_ms)"
  REPORT_FINALIZED=1
  printf 'ERROR: %s\n' "${message}" >&2
  exit 1
}

die() {
  finalize_failure "$*"
}

on_err() {
  local exit_code=$?
  finalize_failure "command failed during ${CURRENT_STAGE}: ${BASH_COMMAND}"
  exit "${exit_code}"
}

trap on_err ERR

load_nvm() {
  local nvm_dir="${NVM_DIR:-${HOME}/.nvm}"
  local nvm_sh="${nvm_dir}/nvm.sh"

  if [[ -s "${nvm_sh}" ]]; then
    # shellcheck source=/dev/null
    . "${nvm_sh}"
  fi
}

require_codex() {
  command -v codex >/dev/null 2>&1 || die "codex command not found. Install Codex CLI or load it into PATH."
}

require_task() {
  [[ -n "${TASK:-}" ]] || die "TASK is required. Usage: make codex-task TASK=<task-name>"
}

ensure_main_branch() {
  local current_branch
  current_branch="$(git branch --show-current)"
  [[ "${current_branch}" == "main" ]] || die "current branch must be main before starting a Codex task (current: ${current_branch:-detached HEAD})"
}

ensure_clean_worktree() {
  git diff --quiet --ignore-submodules -- || die "working tree has unstaged changes"
  git diff --cached --quiet --ignore-submodules -- || die "working tree has staged changes"
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || die "untracked files exist"
}

ensure_branch_available() {
  local target_branch="$1"

  git check-ref-format --branch "${target_branch}" >/dev/null 2>&1 || die "invalid task branch name: ${target_branch}"

  if git show-ref --verify --quiet "refs/heads/${target_branch}"; then
    die "target branch already exists locally: ${target_branch}"
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/${target_branch}"; then
    die "target branch already exists on origin: ${target_branch}"
  fi
}

init_observability() {
  mkdir -p "${RUNTIME_DIR}"
  git check-ignore -q "${REPORT_FILE}" || die "runtime report must be ignored by git: ${REPORT_FILE}"
  git check-ignore -q "${TRACE_FILE}" || die "debug trace must be ignored by git: ${TRACE_FILE}"

  STARTED_AT="$(now_iso)"
  STARTED_MS="$(now_ms)"
  RUN_ID="$(date -u +'%Y%m%dT%H%M%SZ')-$$"
  CURRENT_BRANCH="$(git branch --show-current)"
  VALIDATOR_VERSION="$(git rev-parse HEAD:tools/pr_readiness_validator.py)"

  : > "${TRACE_FILE}"
  write_report "${STARTED_AT}" "${STARTED_MS}"
  append_trace "bootstrap" "ok" "initialized executor observability" ".runtime/execution-report.json"
}

main() {
  local target_branch
  local origin_head
  local start_commit
  local pr_body_file

  require_task

  cd "${REPO_ROOT}"
  init_observability

  load_nvm
  require_codex
  EXECUTOR_VERSION="$(codex --version 2>/dev/null | head -n1 || printf 'unknown')"

  target_branch="codex/${TASK}"

  ensure_main_branch
  ensure_clean_worktree
  ensure_branch_available "${target_branch}"

  CURRENT_STAGE="main_sync"
  git fetch origin
  git switch main
  git reset --hard origin/main
  append_trace "main_sync" "ok" "synchronized local main to origin/main" "origin/main"

  CURRENT_STAGE="branch_create"
  git switch -c "${target_branch}"
  append_trace "branch_create" "ok" "created task branch" "${target_branch}"

  origin_head="$(git rev-parse --short origin/main)"
  BASE_COMMIT="$(git rev-parse origin/main)"
  HEAD_COMMIT="$(git rev-parse HEAD)"
  start_commit="$(git rev-parse --short HEAD)"
  pr_body_file="/tmp/$(basename "${REPO_ROOT}")-${target_branch//\//-}-pr-body.md"
  CURRENT_BRANCH="${target_branch}"

  export CODEX_PR_BODY_FILE="${pr_body_file}"
  export CODEX_PR_BASE_BRANCH="main"
  export CODEX_PR_PREVALIDATE_SCRIPT="${REPO_ROOT}/scripts/pre-validate-pr.sh"
  export CODEX_EXECUTION_REPORT_FILE="${REPO_ROOT}/.runtime/execution-report.json"
  export CODEX_DEBUG_TRACE_FILE="${REPO_ROOT}/.runtime/debug-trace.jsonl"
  export CODEX_RUN_ID="${RUN_ID}"
  export CODEX_EXECUTOR_NAME="${EXECUTOR_NAME}"
  export CODEX_EXECUTOR_VERSION="${EXECUTOR_VERSION}"

  CURRENT_STAGE="executor_runtime"
  write_report "$(now_iso)" "$(now_ms)"
  append_trace "executor_runtime" "ok" "executor runtime ready" "${CODEX_PR_BODY_FILE}"

  log "Started Codex task"
  log "  repository : $(basename "${REPO_ROOT}")"
  log "  branch     : ${target_branch}"
  log "  origin/main: ${origin_head}"
  log "  head       : ${start_commit}"
  log "  pr body    : ${CODEX_PR_BODY_FILE}"
  log "  pr report  : ${CODEX_EXECUTION_REPORT_FILE}"
  log "  pr trace   : ${CODEX_DEBUG_TRACE_FILE}"
  log "  pr flow    : render PR body -> pre-validate same file -> gh pr create --body-file"
  log

  exec codex --ask-for-approval never --sandbox workspace-write
}

main "$@"
