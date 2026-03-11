#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '%s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/executor-runtime.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/executor-stage.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/executor-failure.sh"

executor_runtime_prepare_paths "${REPO_ROOT}"

require_task() {
  [[ -n "${TASK:-}" ]] || executor_die_config "TASK is required. Usage: make codex-task TASK=<task-name>"
}

load_nvm() {
  local nvm_dir="${NVM_DIR:-${HOME}/.nvm}"
  local nvm_sh="${nvm_dir}/nvm.sh"

  if [[ -s "${nvm_sh}" ]]; then
    # shellcheck source=/dev/null
    . "${nvm_sh}"
  fi
}

require_codex() {
  command -v codex >/dev/null 2>&1 || executor_die_config "codex command not found. Install Codex CLI or load it into PATH."
}

ensure_main_branch() {
  local current_branch
  current_branch="$(git branch --show-current)"
  [[ "${current_branch}" == "main" ]] || executor_die_repo_state "current branch must be main before starting a Codex task (current: ${current_branch:-detached HEAD})"
}

ensure_clean_worktree() {
  git diff --quiet --ignore-submodules -- || executor_die_repo_state "working tree has unstaged changes"
  git diff --cached --quiet --ignore-submodules -- || executor_die_repo_state "working tree has staged changes"
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || executor_die_repo_state "untracked files exist"
}

ensure_branch_available() {
  local target_branch="$1"

  git check-ref-format --branch "${target_branch}" >/dev/null 2>&1 || executor_die_config "invalid task branch name: ${target_branch}"

  if git show-ref --verify --quiet "refs/heads/${target_branch}"; then
    executor_die_repo_state "target branch already exists locally: ${target_branch}"
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/${target_branch}"; then
    executor_die_repo_state "target branch already exists on origin: ${target_branch}"
  fi
}

on_err() {
  executor_die_unknown "command failed during ${EXECUTOR_CURRENT_STAGE}: ${BASH_COMMAND}"
}

trap on_err ERR

main() {
  local target_branch
  local origin_head
  local start_commit
  local pr_body_file

  cd "${REPO_ROOT}"
  executor_runtime_init_state
  EXECUTOR_TASK_DESCRIPTION="${TASK:-}"
  git check-ignore -q "${EXECUTOR_REPORT_FILE}" || executor_die_config "runtime report must be ignored by git: ${EXECUTOR_REPORT_FILE}"
  git check-ignore -q "${EXECUTOR_TRACE_FILE}" || executor_die_config "debug trace must be ignored by git: ${EXECUTOR_TRACE_FILE}"
  : > "${EXECUTOR_TRACE_FILE}"

  executor_stage_begin "bootstrap" "starting executor runtime bootstrap"
  require_task
  load_nvm
  require_codex
  EXECUTOR_NAME="${CODEX_EXECUTOR_NAME:-codex-cli}"
  EXECUTOR_VERSION="$(codex --version 2>/dev/null | head -n1 || printf 'unknown')"
  EXECUTOR_VALIDATOR_VERSION="$(git rev-parse HEAD:tools/pr_readiness_validator.py)"
  target_branch="codex/${TASK}"
  ensure_main_branch
  ensure_clean_worktree
  ensure_branch_available "${target_branch}"
  executor_runtime_refresh_repo_state
  executor_stage_succeed "bootstrap" "validated executor bootstrap prerequisites"
  executor_runtime_write_report

  executor_stage_begin "main_sync" "synchronizing local main with origin/main"
  if ! executor_stage_run_with_retry "main_sync" 2 "retrying git fetch origin" git fetch origin; then
    executor_die_transient "git fetch origin failed after retries"
  fi
  git switch main
  git reset --hard origin/main
  EXECUTOR_REPOSITORY_BASE_COMMIT="$(git rev-parse origin/main)"
  EXECUTOR_REPOSITORY_HEAD_COMMIT="$(git rev-parse HEAD)"
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  executor_stage_succeed "main_sync" "synchronized local main to origin/main" "origin/main"
  executor_runtime_write_report

  executor_stage_begin "branch_create" "creating task branch"
  git switch -c "${target_branch}"
  EXECUTOR_REPOSITORY_BRANCH="${target_branch}"
  EXECUTOR_REPOSITORY_HEAD_COMMIT="$(git rev-parse HEAD)"
  EXECUTOR_REPOSITORY_BASE_COMMIT="$(git rev-parse origin/main)"
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  executor_stage_succeed "branch_create" "created task branch" "${target_branch}"
  executor_runtime_write_report

  executor_stage_begin "executor_runtime" "preparing executor runtime contract"
  origin_head="$(git rev-parse --short origin/main)"
  start_commit="$(git rev-parse --short HEAD)"
  pr_body_file="/tmp/$(basename "${REPO_ROOT}")-${target_branch//\//-}-pr-body.md"

  EXECUTOR_PR_BODY_FILE="${pr_body_file}"
  export CODEX_PR_BODY_FILE="${EXECUTOR_PR_BODY_FILE}"
  export CODEX_PR_BASE_BRANCH="main"
  export CODEX_PR_PREVALIDATE_SCRIPT="${REPO_ROOT}/scripts/pre-validate-pr.sh"
  export CODEX_EXECUTION_REPORT_FILE="${EXECUTOR_REPORT_FILE}"
  export CODEX_DEBUG_TRACE_FILE="${EXECUTOR_TRACE_FILE}"
  export CODEX_RUN_ID="${EXECUTOR_RUN_ID}"
  export CODEX_EXECUTOR_NAME="${EXECUTOR_NAME}"
  export CODEX_EXECUTOR_VERSION="${EXECUTOR_VERSION}"

  executor_stage_succeed "executor_runtime" "prepared executor runtime contract" "${EXECUTOR_PR_BODY_FILE}"
  executor_runtime_write_report

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
