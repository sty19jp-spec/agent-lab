#!/usr/bin/env bash
set -Eeuo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/executor-runtime.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/executor-stage.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/executor-failure.sh"

executor_runtime_prepare_paths "${REPO_ROOT}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || executor_die_config "missing command: $1"
}

ensure_clean_worktree() {
  git diff --quiet --ignore-submodules -- || executor_die_repo_state "working tree has unstaged changes"
  git diff --cached --quiet --ignore-submodules -- || executor_die_repo_state "working tree has staged changes"
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || executor_die_repo_state "untracked files exist"
}

BODY_FILE=""
TITLE=""
BASE_BRANCH="main"
VALIDATE_ONLY=0
HEAD_REF_OVERRIDE=""
BASE_SHA_OVERRIDE=""
HEAD_SHA_OVERRIDE=""

on_err() {
  executor_die_unknown "command failed during ${EXECUTOR_CURRENT_STAGE}: ${BASH_COMMAND}"
}

trap on_err ERR

while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file)
      [[ $# -ge 2 ]] || executor_die_config "missing value for --body-file"
      BODY_FILE="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || executor_die_config "missing value for --title"
      TITLE="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || executor_die_config "missing value for --base"
      BASE_BRANCH="$2"
      shift 2
      ;;
    --head-ref)
      [[ $# -ge 2 ]] || executor_die_config "missing value for --head-ref"
      HEAD_REF_OVERRIDE="$2"
      shift 2
      ;;
    --base-sha)
      [[ $# -ge 2 ]] || executor_die_config "missing value for --base-sha"
      BASE_SHA_OVERRIDE="$2"
      shift 2
      ;;
    --head-sha)
      [[ $# -ge 2 ]] || executor_die_config "missing value for --head-sha"
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
      executor_die_config "unknown argument: $1"
      ;;
  esac
done

main() {
  local pr_url=""

  cd "${REPO_ROOT}"
  executor_runtime_init_state
  executor_runtime_load_context

  executor_stage_begin "bootstrap" "starting PR pre-validation wrapper"
  [[ -n "${BODY_FILE}" ]] || executor_die_config "--body-file is required"
  if [[ "${VALIDATE_ONLY}" -eq 0 && -z "${TITLE}" ]]; then
    executor_die_config "--title is required unless --validate-only is set"
  fi

  require_cmd git
  if [[ "${VALIDATE_ONLY}" -eq 0 ]]; then
    require_cmd gh
  fi
  [[ -f "${BODY_FILE}" ]] || executor_die_config "PR body file not found: ${BODY_FILE}"
  git check-ignore -q "${EXECUTOR_REPORT_FILE}" || executor_die_config "runtime report must be ignored by git: ${EXECUTOR_REPORT_FILE}"
  git check-ignore -q "${EXECUTOR_TRACE_FILE}" || executor_die_config "debug trace must be ignored by git: ${EXECUTOR_TRACE_FILE}"
  if git ls-files --error-unmatch "${EXECUTOR_REPORT_FILE}" >/dev/null 2>&1; then
    executor_die_repo_state "runtime report is tracked by git: ${EXECUTOR_REPORT_FILE}"
  fi
  if git ls-files --error-unmatch "${EXECUTOR_TRACE_FILE}" >/dev/null 2>&1; then
    executor_die_repo_state "debug trace is tracked by git: ${EXECUTOR_TRACE_FILE}"
  fi
  ensure_clean_worktree

  EXECUTOR_PR_BODY_FILE="${BODY_FILE}"
  EXECUTOR_PR_TITLE="${TITLE}"
  if [[ -n "${TASK:-}" && -z "${EXECUTOR_TASK_DESCRIPTION}" ]]; then
    EXECUTOR_TASK_DESCRIPTION="${TASK}"
  fi

  if [[ -z "${EXECUTOR_VALIDATOR_VERSION}" || "${EXECUTOR_VALIDATOR_VERSION}" == "unknown" ]]; then
    EXECUTOR_VALIDATOR_VERSION="$(git rev-parse HEAD:tools/pr_readiness_validator.py)"
  fi
  executor_runtime_refresh_repo_state
  executor_stage_succeed "bootstrap" "validated PR pre-validation wrapper prerequisites"
  executor_runtime_write_report

  EXECUTOR_REPOSITORY_BRANCH="${HEAD_REF_OVERRIDE}"
  if [[ -z "${EXECUTOR_REPOSITORY_BRANCH}" ]]; then
    EXECUTOR_REPOSITORY_BRANCH="$(git branch --show-current)"
  fi
  [[ -n "${EXECUTOR_REPOSITORY_BRANCH}" ]] || executor_die_repo_state "current branch is detached"

  EXECUTOR_REPOSITORY_BASE_COMMIT="${BASE_SHA_OVERRIDE}"
  if [[ -z "${EXECUTOR_REPOSITORY_BASE_COMMIT}" ]]; then
    executor_stage_begin "main_sync" "refreshing base branch for PR pre-validation"
    if ! executor_stage_run_with_retry "main_sync" 2 "retrying git fetch origin ${BASE_BRANCH}" git fetch --no-tags origin "${BASE_BRANCH}"; then
      executor_die_transient "git fetch --no-tags origin ${BASE_BRANCH} failed after retries"
    fi
    EXECUTOR_REPOSITORY_BASE_COMMIT="$(git merge-base "origin/${BASE_BRANCH}" HEAD)"
    executor_stage_succeed "main_sync" "resolved base commit from origin/${BASE_BRANCH}" "origin/${BASE_BRANCH}"
    executor_runtime_write_report
  fi

  EXECUTOR_REPOSITORY_HEAD_COMMIT="${HEAD_SHA_OVERRIDE}"
  if [[ -z "${EXECUTOR_REPOSITORY_HEAD_COMMIT}" ]]; then
    EXECUTOR_REPOSITORY_HEAD_COMMIT="$(git rev-parse HEAD)"
  fi

  [[ -n "${EXECUTOR_REPOSITORY_BASE_COMMIT}" ]] || executor_die_repo_state "failed to determine base sha against origin/${BASE_BRANCH}"
  [[ -n "${EXECUTOR_REPOSITORY_HEAD_COMMIT}" ]] || executor_die_repo_state "failed to determine head sha"
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  EXECUTOR_VALIDATOR_COMMAND="${EXECUTOR_PYTHON_BIN} tools/pr_readiness_validator.py --repo-root . --pr-body-file ${BODY_FILE} --head-ref ${EXECUTOR_REPOSITORY_BRANCH} --base-sha ${EXECUTOR_REPOSITORY_BASE_COMMIT} --head-sha ${EXECUTOR_REPOSITORY_HEAD_COMMIT}"

  executor_stage_begin "pr_body_render" "accepting rendered PR body artifact"
  executor_stage_succeed "pr_body_render" "accepted rendered PR body artifact" "${BODY_FILE}"
  executor_runtime_write_report

  executor_stage_begin "pre_validation" "running canonical PR pre-validation"
  log "PR pre-validation"
  log "  branch    : ${EXECUTOR_REPOSITORY_BRANCH}"
  log "  base      : ${BASE_BRANCH}"
  log "  body file : ${BODY_FILE}"
  log "  changed   : $(printf '%s\n' "${EXECUTOR_REPOSITORY_CHANGED_FILES_NL}" | sed '/^$/d' | wc -l | tr -d ' ') file(s)"

  trap - ERR
  set +e
  "${EXECUTOR_PYTHON_BIN}" tools/pr_readiness_validator.py \
    --repo-root . \
    --pr-body-file "${BODY_FILE}" \
    --head-ref "${EXECUTOR_REPOSITORY_BRANCH}" \
    --base-sha "${EXECUTOR_REPOSITORY_BASE_COMMIT}" \
    --head-sha "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  validation_status=$?
  set -e
  trap on_err ERR

  if [[ "${validation_status}" -ne 0 ]]; then
    EXECUTOR_VALIDATION_RESULT="fail"
    executor_die_validation "pre-validation failed; see ${EXECUTOR_REPORT_FILE}"
  fi

  EXECUTOR_VALIDATION_RESULT="pass"
  executor_stage_succeed "pre_validation" "canonical PR pre-validation passed"
  executor_runtime_write_report

  if [[ "${VALIDATE_ONLY}" -eq 1 ]]; then
    executor_finalize_success
    log "Local pre-validation passed"
    log "  report    : ${EXECUTOR_REPORT_FILE}"
    log "  trace     : ${EXECUTOR_TRACE_FILE}"
    exit 0
  fi

  executor_stage_begin "pr_create" "creating pull request from validated body file"
  if ! executor_stage_run_with_retry "pr_create" 1 "retrying gh pr create" gh pr create \
    --base "${BASE_BRANCH}" \
    --head "${EXECUTOR_REPOSITORY_BRANCH}" \
    --title "${TITLE}" \
    --body-file "${BODY_FILE}"; then
    EXECUTOR_VALIDATION_RESULT="pass"
    executor_die_transient "gh pr create failed after retries"
  fi
  pr_url="$(gh pr view --json url --jq '.url')"
  EXECUTOR_PR_URL="${pr_url}"
  executor_stage_succeed "pr_create" "created pull request from validated body file" "${BODY_FILE}"
  executor_runtime_write_report

  executor_stage_begin "post_create" "finalizing runtime artifacts after PR creation"
  if ! executor_finalize_success; then
    executor_best_effort_failure "post_create" "unknown_error" "failed to finalize runtime report after PR creation"
  fi
  executor_stage_succeed "post_create" "finalized runtime artifacts after PR creation" "${pr_url}"
  executor_runtime_write_report

  log "Creating PR from validated body file"
  log "  report    : ${EXECUTOR_REPORT_FILE}"
  log "  trace     : ${EXECUTOR_TRACE_FILE}"
  printf '%s\n' "${pr_url}"
}

main "$@"
