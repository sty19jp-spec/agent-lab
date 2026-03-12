#!/usr/bin/env bash

if [[ -n "${EXECUTOR_STAGE_LIB_LOADED:-}" ]]; then
  return 0
fi
EXECUTOR_STAGE_LIB_LOADED=1

executor_stage_begin() {
  local stage="$1"
  local message="${2:-}"

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
}

executor_stage_retry() {
  local stage="$1"
  local message="$2"
  local fail_classification="${3:-transient_command_error}"

  EXECUTOR_STAGE_RETRY_COUNT["${stage}"]="$(( ${EXECUTOR_STAGE_RETRY_COUNT[${stage}]:-0} + 1 ))"
  executor_runtime_trace_event "${stage}" "retry" "${message}" "" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}" "${fail_classification}"
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
  executor_runtime_trace_event "${stage}" "ok" "${message}" "${artifact}" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}"
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
}

executor_stage_run_with_retry() {
  local stage="$1"
  local retries="$2"
  shift 2
  local message="$1"
  shift

  local attempt=0
  local status=0

  while true; do
    set +e
    "$@"
    status=$?
    set -e

    if [[ "${status}" -eq 0 ]]; then
      return 0
    fi

    if [[ "${attempt}" -ge "${retries}" ]]; then
      return "${status}"
    fi

    attempt=$((attempt + 1))
    executor_stage_retry "${stage}" "${message} (attempt ${attempt})"
  done
}
