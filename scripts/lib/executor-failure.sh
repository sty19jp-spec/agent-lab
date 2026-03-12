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
  EXECUTOR_LAST_FAILURE_CLASSIFICATION="none"
  EXECUTOR_HEALTH_STATUS="${EXECUTOR_HEALTH_STATUS:-pass}"
  EXECUTOR_HEALTH_SUMMARY="${EXECUTOR_HEALTH_SUMMARY:-runtime self-check passed}"
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  executor_runtime_write_report
  executor_runtime_update_metrics
}

executor_fail_with_class() {
  local fail_classification="$1"
  local message="$2"
  local artifact="${3:-}"
  local stage="${EXECUTOR_CURRENT_STAGE}"
  local retry_attempt="${EXECUTOR_STAGE_RETRY_COUNT[${stage}]:-0}"
  local resume_eligible="false"
  local resume_block_reason=""

  if executor_runtime_resume_eligible "${stage}" "${fail_classification}"; then
    resume_eligible="true"
  else
    resume_block_reason="stage or failure class is not eligible for deterministic auto-resume"
  fi

  executor_stage_record_failure "${stage}" "${fail_classification}" "${message}" "${artifact}"
  if [[ "${EXECUTOR_HEALTH_STATUS}" == "pending" ]]; then
    EXECUTOR_HEALTH_STATUS="fail"
    EXECUTOR_HEALTH_SUMMARY="${message}"
  fi
  executor_runtime_refresh_repo_state "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}"
  executor_runtime_write_report
  executor_runtime_update_metrics
  executor_runtime_write_failure_report \
    "${stage}" \
    "${EXECUTOR_LAST_COMMAND}" \
    "${EXECUTOR_LAST_EXIT_CODE}" \
    "${fail_classification}" \
    "${retry_attempt}" \
    "${resume_eligible}" \
    "${resume_block_reason}"
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

executor_die_transient_network() {
  executor_fail_with_class "transient_network_error" "$1"
}

executor_die_gh_api_temporary() {
  executor_fail_with_class "gh_api_temporary_error" "$1"
}

executor_die_auth() {
  executor_fail_with_class "auth_error" "$1"
}

executor_die_branch_policy() {
  executor_fail_with_class "branch_policy_error" "$1"
}

executor_die_unknown() {
  executor_fail_with_class "unknown_error" "$1"
}
