#!/usr/bin/env bash

if [[ -n "${EXECUTOR_STAGE_LIB_LOADED:-}" ]]; then
  return 0
fi
EXECUTOR_STAGE_LIB_LOADED=1

executor_stage_begin() {
  local stage="$1"
  local message="${2:-}"
  local stage_kind

  stage_kind="$(executor_runtime_stage_kind_for "${stage}")"

  if [[ "${EXECUTOR_STAGE_STATUS[${stage}]:-pending}" == "ok" ]]; then
    executor_runtime_trace_event "${stage}" "started" "re-entering completed ${stage_kind} stage"
  fi

  EXECUTOR_CURRENT_STAGE="${stage}"
  EXECUTOR_CURRENT_STAGE_STATUS="in_progress"
  EXECUTOR_RUN_STATUS="in_progress"
  EXECUTOR_STAGE_STATUS["${stage}"]="in_progress"
  if [[ -z "${EXECUTOR_STAGE_STARTED_AT[${stage}]}" ]]; then
    EXECUTOR_STAGE_STARTED_AT["${stage}"]="$(executor_runtime_now_iso)"
  fi
  EXECUTOR_STAGE_ENDED_AT["${stage}"]=""
  EXECUTOR_STAGE_FAIL_CLASSIFICATION["${stage}"]="none"

  if [[ -n "${message}" ]]; then
    executor_runtime_trace_event "${stage}" "started" "${message}"
  fi
  executor_runtime_write_state
}

executor_stage_retry() {
  local stage="$1"
  local message="$2"
  local fail_classification="${3:-transient_command_error}"

  EXECUTOR_STAGE_RETRY_COUNT["${stage}"]="$(( ${EXECUTOR_STAGE_RETRY_COUNT[${stage}]:-0} + 1 ))"
  executor_runtime_trace_event "${stage}" "retry" "${message}" "" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}" "${fail_classification}"
  executor_runtime_write_state
}

executor_stage_succeed() {
  local stage="$1"
  local message="$2"
  local artifact="${3:-}"

  EXECUTOR_CURRENT_STAGE="${stage}"
  EXECUTOR_CURRENT_STAGE_STATUS="ok"
  EXECUTOR_STAGE_STATUS["${stage}"]="ok"
  EXECUTOR_STAGE_ENDED_AT["${stage}"]="$(executor_runtime_now_iso)"
  EXECUTOR_STAGE_FAIL_CLASSIFICATION["${stage}"]="none"
  EXECUTOR_FAILURE_STAGE="none"
  EXECUTOR_FAILURE_CLASSIFICATION="none"
  EXECUTOR_ERROR_SUMMARY=""
  executor_runtime_trace_event "${stage}" "ok" "${message}" "${artifact}" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}"
  executor_runtime_write_state
}

executor_stage_record_failure() {
  local stage="$1"
  local fail_classification="$2"
  local message="$3"
  local artifact="${4:-}"

  EXECUTOR_CURRENT_STAGE="${stage}"
  EXECUTOR_CURRENT_STAGE_STATUS="error"
  EXECUTOR_STAGE_STATUS["${stage}"]="error"
  if [[ -z "${EXECUTOR_STAGE_STARTED_AT[${stage}]}" ]]; then
    EXECUTOR_STAGE_STARTED_AT["${stage}"]="$(executor_runtime_now_iso)"
  fi
  EXECUTOR_STAGE_ENDED_AT["${stage}"]="$(executor_runtime_now_iso)"
  EXECUTOR_STAGE_FAIL_CLASSIFICATION["${stage}"]="${fail_classification}"
  EXECUTOR_FAILURE_STAGE="${stage}"
  EXECUTOR_FAILURE_CLASSIFICATION="${fail_classification}"
  EXECUTOR_ERROR_SUMMARY="${message}"
  EXECUTOR_RUN_STATUS="failed"
  executor_runtime_trace_event "${stage}" "error" "${message}" "${artifact}" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}" "${fail_classification}"
  executor_runtime_write_state
}

executor_stage_best_effort_failure() {
  local stage="$1"
  local fail_classification="$2"
  local message="$3"
  local artifact="${4:-}"

  EXECUTOR_STAGE_STATUS["${stage}"]="error"
  if [[ -z "${EXECUTOR_STAGE_STARTED_AT[${stage}]}" ]]; then
    EXECUTOR_STAGE_STARTED_AT["${stage}"]="$(executor_runtime_now_iso)"
  fi
  EXECUTOR_STAGE_ENDED_AT["${stage}"]="$(executor_runtime_now_iso)"
  EXECUTOR_STAGE_FAIL_CLASSIFICATION["${stage}"]="${fail_classification}"
  executor_runtime_trace_event "${stage}" "error" "${message}" "${artifact}" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}" "${fail_classification}"
  executor_runtime_write_state
}

executor_stage_mark_resumed() {
  local stage="$1"
  local message="$2"
  local artifact="${3:-}"

  EXECUTOR_CURRENT_STAGE="${stage}"
  EXECUTOR_CURRENT_STAGE_STATUS="ok"
  EXECUTOR_STAGE_STATUS["${stage}"]="ok"
  if [[ -z "${EXECUTOR_STAGE_STARTED_AT[${stage}]}" ]]; then
    EXECUTOR_STAGE_STARTED_AT["${stage}"]="$(executor_runtime_now_iso)"
  fi
  if [[ -z "${EXECUTOR_STAGE_ENDED_AT[${stage}]}" ]]; then
    EXECUTOR_STAGE_ENDED_AT["${stage}"]="$(executor_runtime_now_iso)"
  fi
  executor_runtime_trace_event "${stage}" "ok" "${message}" "${artifact}" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}"
  executor_runtime_write_state
}

executor_stage_run_with_retry() {
  local stage="$1"
  local retries="$2"
  shift 2

  local fail_classification=""
  case "${1:-}" in
    transient_command_error|transient_network_error|gh_api_temporary_error|validation_error|repo_state_error|config_error|auth_error|branch_policy_error|unknown_error)
      fail_classification="$1"
      shift
      ;;
  esac

  local message="$1"
  shift

  local attempt=0
  local status=0
  local command_string
  local backoff_seconds
  local reconcile_status=0

  command_string="$(printf '%q ' "$@")"
  command_string="${command_string% }"
  if [[ -z "${fail_classification}" ]]; then
    fail_classification="$(executor_runtime_classify_command_failure "${stage}" "$@")"
  fi

  while true; do
    set +e
    "$@"
    status=$?
    set -e

    if [[ "${status}" -eq 0 ]]; then
      EXECUTOR_LAST_COMMAND="${command_string}"
      EXECUTOR_LAST_EXIT_CODE="0"
      EXECUTOR_LAST_FAILURE_CLASSIFICATION="none"
      return 0
    fi

    executor_runtime_record_command_failure "${command_string}" "${status}" "${fail_classification}"

    if [[ "${stage}" == "pr_create" && "$1" == "gh" && "${2:-}" == "pr" && "${3:-}" == "create" ]]; then
      if executor_runtime_reconcile_existing_pr; then
        return 0
      fi
      reconcile_status=$?
      if [[ "${reconcile_status}" -eq 2 ]]; then
        EXECUTOR_LAST_FAILURE_CLASSIFICATION="unknown_error"
        return "${status}"
      fi
    fi

    if ! executor_runtime_is_retryable_class "${fail_classification}"; then
      return "${status}"
    fi

    if [[ "${attempt}" -ge "${retries}" ]]; then
      return "${status}"
    fi

    attempt=$((attempt + 1))
    executor_stage_retry "${stage}" "${message} (attempt ${attempt})" "${fail_classification}"
    backoff_seconds="$(executor_runtime_retry_backoff_seconds "${attempt}")"
    sleep "${backoff_seconds}"
  done
}
