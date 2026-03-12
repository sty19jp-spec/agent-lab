#!/usr/bin/env bash

if [[ -n "${EXECUTOR_FAILURE_LIB_LOADED:-}" ]]; then
  return 0
fi
EXECUTOR_FAILURE_LIB_LOADED=1

executor_finalize_success() {
  EXECUTOR_RUN_STATUS="completed"
  EXECUTOR_FAILURE_STAGE="none"
  EXECUTOR_FAILURE_CLASSIFICATION="none"
  EXECUTOR_ERROR_SUMMARY=""
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  executor_runtime_write_report
}

executor_fail_with_class() {
  local fail_classification="$1"
  local message="$2"
  local artifact="${3:-}"

  executor_stage_record_failure "${EXECUTOR_CURRENT_STAGE}" "${fail_classification}" "${message}" "${artifact}"
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  executor_runtime_write_report
  printf 'ERROR: %s\n' "${message}" >&2
  exit 1
}

executor_best_effort_failure() {
  local stage="$1"
  local fail_classification="$2"
  local message="$3"
  local artifact="${4:-}"

  executor_stage_best_effort_failure "${stage}" "${fail_classification}" "${message}" "${artifact}"
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  executor_runtime_write_report
  printf 'WARN: %s\n' "${message}" >&2
}

executor_die_config() {
  executor_fail_with_class "config_error" "$1"
}

executor_die_repo_state() {
  executor_fail_with_class "repo_state_error" "$1"
}

executor_die_validation() {
  executor_fail_with_class "validation_error" "$1"
}

executor_die_transient() {
  executor_fail_with_class "transient_command_error" "$1"
}

executor_die_unknown() {
  executor_fail_with_class "unknown_error" "$1"
}
