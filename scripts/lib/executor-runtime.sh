#!/usr/bin/env bash

if [[ -n "${EXECUTOR_RUNTIME_LIB_LOADED:-}" ]]; then
  return 0
fi
EXECUTOR_RUNTIME_LIB_LOADED=1

EXECUTOR_STAGE_ORDER=(
  bootstrap
  main_sync
  branch_create
  executor_runtime
  pr_body_render
  pre_validation
  pr_create
  post_create
)

declare -gA EXECUTOR_STAGE_STATUS=()
declare -gA EXECUTOR_STAGE_STARTED_AT=()
declare -gA EXECUTOR_STAGE_ENDED_AT=()
declare -gA EXECUTOR_STAGE_RETRY_COUNT=()
declare -gA EXECUTOR_STAGE_FAIL_CLASSIFICATION=()

declare -g EXECUTOR_SCHEMA_VERSION="phase48-v1"
declare -g EXECUTOR_RUNTIME_DIR=""
declare -g EXECUTOR_TRACE_FILE=""
declare -g EXECUTOR_REPORT_FILE=""
declare -g EXECUTOR_STATE_FILE=""
declare -g EXECUTOR_FAILURE_FILE=""
declare -g EXECUTOR_LOCK_FILE=""
declare -g EXECUTOR_PYTHON_BIN=""
declare -g EXECUTOR_RUN_ID=""
declare -g EXECUTOR_NAME="codex-cli"
declare -g EXECUTOR_VERSION="unknown"
declare -g EXECUTOR_VALIDATOR_VERSION="unknown"
declare -g EXECUTOR_CURRENT_STAGE="bootstrap"
declare -g EXECUTOR_CURRENT_STAGE_STATUS="pending"
declare -g EXECUTOR_RUN_STATUS="pending"
declare -g EXECUTOR_STARTED_AT=""
declare -g EXECUTOR_STARTED_MS=""
declare -g EXECUTOR_FINISHED_AT=""
declare -g EXECUTOR_FINISHED_MS=""
declare -g EXECUTOR_FAILURE_STAGE="none"
declare -g EXECUTOR_FAILURE_CLASSIFICATION="none"
declare -g EXECUTOR_ERROR_SUMMARY=""
declare -g EXECUTOR_TASK_DESCRIPTION=""
declare -g EXECUTOR_BASE_BRANCH="main"
declare -g EXECUTOR_REPOSITORY_BRANCH=""
declare -g EXECUTOR_REPOSITORY_BASE_COMMIT=""
declare -g EXECUTOR_REPOSITORY_HEAD_COMMIT=""
declare -g EXECUTOR_REPOSITORY_WORKSPACE_CLEAN="false"
declare -g EXECUTOR_REPOSITORY_CHANGED_FILES_NL=""
declare -g EXECUTOR_REPOSITORY_UNTRACKED_FILES_NL=""
declare -g EXECUTOR_PR_BODY_FILE=""
declare -g EXECUTOR_PR_TITLE=""
declare -g EXECUTOR_PR_URL=""
declare -g EXECUTOR_PR_READINESS_TOKEN="PR-ready"
declare -g EXECUTOR_VALIDATION_RESULT="pending"
declare -g EXECUTOR_VALIDATOR_COMMAND=""
declare -g EXECUTOR_LAST_COMMAND=""
declare -g EXECUTOR_LAST_EXIT_CODE="0"
declare -g EXECUTOR_LAST_FAILURE_CLASSIFICATION="none"
declare -g EXECUTOR_RESUME_MODE="0"
declare -g EXECUTOR_STATE_COMPLETED_STAGES_NL=""
declare -g EXECUTOR_STATE_FAILED_STAGE="none"
declare -g EXECUTOR_STATE_FAILURE_CLASS="none"
declare -g EXECUTOR_STATE_LAST_UPDATED_AT=""
declare -g EXECUTOR_LOCK_ACQUIRED="0"
declare -g EXECUTOR_RECONCILED_PR_URL=""

executor_runtime_resolve_python() {
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

executor_runtime_now_iso() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

executor_runtime_now_ms() {
  if [[ -n "${EXECUTOR_PYTHON_BIN}" ]]; then
    "${EXECUTOR_PYTHON_BIN}" - <<'PY'
import time
print(int(time.time() * 1000))
PY
    return
  fi
  date -u +%s000
}

executor_runtime_prepare_paths() {
  local repo_root="$1"

  REPO_ROOT="${repo_root}"
  EXECUTOR_RUNTIME_DIR="${REPO_ROOT}/.runtime"
  EXECUTOR_TRACE_FILE="${EXECUTOR_RUNTIME_DIR}/debug-trace.jsonl"
  EXECUTOR_REPORT_FILE="${EXECUTOR_RUNTIME_DIR}/execution-report.json"
  EXECUTOR_STATE_FILE="${EXECUTOR_RUNTIME_DIR}/execution-state.json"
  EXECUTOR_FAILURE_FILE="${EXECUTOR_RUNTIME_DIR}/failure-report.json"
  EXECUTOR_LOCK_FILE="${EXECUTOR_RUNTIME_DIR}/run.lock"
  EXECUTOR_PYTHON_BIN="${EXECUTOR_PYTHON_BIN:-$(executor_runtime_resolve_python)}"
}

executor_runtime_reset_stages() {
  local stage
  for stage in "${EXECUTOR_STAGE_ORDER[@]}"; do
    EXECUTOR_STAGE_STATUS["${stage}"]="pending"
    EXECUTOR_STAGE_STARTED_AT["${stage}"]=""
    EXECUTOR_STAGE_ENDED_AT["${stage}"]=""
    EXECUTOR_STAGE_RETRY_COUNT["${stage}"]="0"
    EXECUTOR_STAGE_FAIL_CLASSIFICATION["${stage}"]="none"
  done
}

executor_runtime_init_state() {
  mkdir -p "${EXECUTOR_RUNTIME_DIR}"

  executor_runtime_reset_stages

  EXECUTOR_STARTED_AT="$(executor_runtime_now_iso)"
  EXECUTOR_STARTED_MS="$(executor_runtime_now_ms)"
  EXECUTOR_FINISHED_AT=""
  EXECUTOR_FINISHED_MS=""
  EXECUTOR_RUN_ID="${EXECUTOR_RUN_ID:-$(date -u +'%Y%m%dT%H%M%SZ')-$$}"
  EXECUTOR_CURRENT_STAGE="bootstrap"
  EXECUTOR_CURRENT_STAGE_STATUS="pending"
  EXECUTOR_RUN_STATUS="in_progress"
  EXECUTOR_FAILURE_STAGE="none"
  EXECUTOR_FAILURE_CLASSIFICATION="none"
  EXECUTOR_ERROR_SUMMARY=""
  EXECUTOR_VALIDATION_RESULT="pending"
  EXECUTOR_VALIDATOR_COMMAND=""
  EXECUTOR_PR_TITLE=""
  EXECUTOR_PR_URL=""
  EXECUTOR_LAST_COMMAND=""
  EXECUTOR_LAST_EXIT_CODE="0"
  EXECUTOR_LAST_FAILURE_CLASSIFICATION="none"
  EXECUTOR_STATE_COMPLETED_STAGES_NL=""
  EXECUTOR_STATE_FAILED_STAGE="none"
  EXECUTOR_STATE_FAILURE_CLASS="none"
  EXECUTOR_STATE_LAST_UPDATED_AT=""
  EXECUTOR_RECONCILED_PR_URL=""
}

executor_runtime_trace_event() {
  local stage="$1"
  local status="$2"
  local message="$3"
  local artifact="${4:-}"
  local retry_count="${5:-}"
  local fail_classification="${6:-}"

  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || return

  mkdir -p "${EXECUTOR_RUNTIME_DIR}"
  "${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_TRACE_FILE}" "${stage}" "${status}" "${message}" "${artifact}" "${retry_count}" "${fail_classification}"
import json
import sys
from datetime import datetime, timezone

trace_file, stage, status, message, artifact, retry_count, fail_classification = sys.argv[1:]
event = {
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "stage": stage,
    "status": status,
    "message": message,
}
if artifact:
    event["artifact"] = artifact
if retry_count:
    event["retry_count"] = int(retry_count)
if fail_classification:
    event["fail_classification"] = fail_classification

with open(trace_file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=True) + "\n")
PYEOF
}

executor_runtime_refresh_repo_state() {
  local base_commit="${1:-${EXECUTOR_REPOSITORY_BASE_COMMIT}}"
  local head_commit="${2:-${EXECUTOR_REPOSITORY_HEAD_COMMIT}}"

  EXECUTOR_REPOSITORY_BRANCH="$(git branch --show-current || true)"
  EXECUTOR_REPOSITORY_BASE_COMMIT="${base_commit}"
  EXECUTOR_REPOSITORY_HEAD_COMMIT="${head_commit}"
  EXECUTOR_REPOSITORY_UNTRACKED_FILES_NL="$(git ls-files --others --exclude-standard || true)"

  if git diff --quiet --ignore-submodules -- && git diff --cached --quiet --ignore-submodules -- && [[ -z "${EXECUTOR_REPOSITORY_UNTRACKED_FILES_NL}" ]]; then
    EXECUTOR_REPOSITORY_WORKSPACE_CLEAN="true"
  else
    EXECUTOR_REPOSITORY_WORKSPACE_CLEAN="false"
  fi

  if [[ -n "${base_commit}" && -n "${head_commit}" ]]; then
    EXECUTOR_REPOSITORY_CHANGED_FILES_NL="$(git diff --name-only "${base_commit}...${head_commit}" || true)"
  else
    EXECUTOR_REPOSITORY_CHANGED_FILES_NL=""
  fi
}

executor_runtime_stage_payload() {
  local stage
  for stage in "${EXECUTOR_STAGE_ORDER[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${stage}" \
      "${EXECUTOR_STAGE_STATUS[${stage}]}" \
      "${EXECUTOR_STAGE_STARTED_AT[${stage}]}" \
      "${EXECUTOR_STAGE_ENDED_AT[${stage}]}" \
      "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}" \
      "${EXECUTOR_STAGE_FAIL_CLASSIFICATION[${stage}]}"
  done
}

executor_runtime_completed_stages_payload() {
  local stage
  for stage in "${EXECUTOR_STAGE_ORDER[@]}"; do
    if [[ "${EXECUTOR_STAGE_STATUS[${stage}]}" == "ok" ]]; then
      printf '%s\n' "${stage}"
    fi
  done
}

executor_runtime_retry_count_payload() {
  local stage
  for stage in "${EXECUTOR_STAGE_ORDER[@]}"; do
    printf '%s\t%s\n' "${stage}" "${EXECUTOR_STAGE_RETRY_COUNT[${stage}]}"
  done
}

executor_runtime_write_state() {
  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || return

  local completed_payload
  local retry_payload
  local last_updated_at

  completed_payload="$(executor_runtime_completed_stages_payload)"
  retry_payload="$(executor_runtime_retry_count_payload)"
  last_updated_at="$(executor_runtime_now_iso)"
  EXECUTOR_STATE_COMPLETED_STAGES_NL="${completed_payload}"
  EXECUTOR_STATE_FAILED_STAGE="${EXECUTOR_FAILURE_STAGE}"
  EXECUTOR_STATE_FAILURE_CLASS="${EXECUTOR_FAILURE_CLASSIFICATION}"
  EXECUTOR_STATE_LAST_UPDATED_AT="${last_updated_at}"

  "${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_STATE_FILE}" "${EXECUTOR_RUN_ID}" "${EXECUTOR_CURRENT_STAGE}" "${completed_payload}" "${EXECUTOR_FAILURE_STAGE}" "${EXECUTOR_FAILURE_CLASSIFICATION}" "${retry_payload}" "${EXECUTOR_REPOSITORY_BRANCH}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}" "${EXECUTOR_PR_BODY_FILE}" "${last_updated_at}"
import json
import sys

(
    state_file,
    run_id,
    current_stage,
    completed_payload,
    failed_stage,
    failure_class,
    retry_payload,
    branch_name,
    commit_head,
    pr_body_file,
    last_updated_at,
) = sys.argv[1:]

completed = [line for line in completed_payload.splitlines() if line]
retry_count_by_stage = {}
for line in retry_payload.splitlines():
    if not line:
        continue
    name, count = line.split("\t", 1)
    retry_count_by_stage[name] = int(count or "0")

state = {
    "run_id": run_id,
    "current_stage": current_stage,
    "completed_stages": completed,
    "failed_stage": failed_stage,
    "failure_class": failure_class,
    "retry_count_by_stage": retry_count_by_stage,
    "branch_name": branch_name,
    "commit_head": commit_head,
    "pr_body_file": pr_body_file,
    "last_updated_at": last_updated_at,
}

with open(state_file, "w", encoding="utf-8") as fh:
    json.dump(state, fh, indent=2)
    fh.write("\n")
PYEOF
}

executor_runtime_write_report() {
  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || return

  local finished_at="${1:-$(executor_runtime_now_iso)}"
  local finished_ms="${2:-$(executor_runtime_now_ms)}"
  local stage_payload

  stage_payload="$(executor_runtime_stage_payload)"
  EXECUTOR_FINISHED_AT="${finished_at}"
  EXECUTOR_FINISHED_MS="${finished_ms}"

  "${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_REPORT_FILE}" "${EXECUTOR_SCHEMA_VERSION}" "${EXECUTOR_RUN_ID}" "${EXECUTOR_NAME}" "${EXECUTOR_VERSION}" "${EXECUTOR_REPOSITORY_BRANCH}" "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}" "${EXECUTOR_REPOSITORY_WORKSPACE_CLEAN}" "${EXECUTOR_REPOSITORY_CHANGED_FILES_NL}" "${EXECUTOR_REPOSITORY_UNTRACKED_FILES_NL}" "${EXECUTOR_PR_BODY_FILE}" "${EXECUTOR_PR_TITLE}" "${EXECUTOR_PR_URL}" "${EXECUTOR_PR_READINESS_TOKEN}" "${EXECUTOR_VALIDATOR_VERSION}" "${EXECUTOR_VALIDATION_RESULT}" "${EXECUTOR_VALIDATOR_COMMAND}" "${EXECUTOR_STARTED_AT}" "${EXECUTOR_STARTED_MS}" "${EXECUTOR_FINISHED_AT}" "${EXECUTOR_FINISHED_MS}" "${EXECUTOR_TRACE_FILE}" "${EXECUTOR_CURRENT_STAGE}" "${EXECUTOR_CURRENT_STAGE_STATUS}" "${EXECUTOR_RUN_STATUS}" "${EXECUTOR_TASK_DESCRIPTION}" "${EXECUTOR_FAILURE_STAGE}" "${EXECUTOR_FAILURE_CLASSIFICATION}" "${EXECUTOR_ERROR_SUMMARY}" "${stage_payload}" "${EXECUTOR_STATE_FILE}" "${EXECUTOR_FAILURE_FILE}" "${EXECUTOR_LOCK_FILE}"
import json
import sys

(
    report_file,
    schema_version,
    run_id,
    executor_name,
    executor_version,
    branch,
    base_commit,
    head_commit,
    workspace_clean,
    changed_files_nl,
    untracked_files_nl,
    pr_body_file,
    pr_title,
    pr_url,
    readiness_token,
    validator_version,
    validation_result,
    validator_command,
    started_at,
    started_ms,
    finished_at,
    finished_ms,
    trace_file,
    current_stage,
    current_stage_status,
    run_status,
    task_description,
    failure_stage,
    failure_classification,
    error_summary,
    stage_payload,
    state_file,
    failure_file,
    lock_file,
) = sys.argv[1:]

changed_files = [line for line in changed_files_nl.splitlines() if line]
untracked_files = [line for line in untracked_files_nl.splitlines() if line]
started_ms_int = int(started_ms) if started_ms else 0
finished_ms_int = int(finished_ms) if finished_ms else started_ms_int
duration_ms = finished_ms_int - started_ms_int if finished_ms_int >= started_ms_int else 0

stages = []
for line in stage_payload.splitlines():
    if not line:
        continue
    name, status, started, ended, retry_count, fail_class = line.split("\t")
    stages.append(
        {
            "name": name,
            "stage_status": status,
            "started_at": started,
            "ended_at": ended,
            "retry_count": int(retry_count or "0"),
            "fail_classification": fail_class or "none",
        }
    )

report = {
    "schema_version": schema_version,
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
        "body_file": pr_body_file,
        "title": pr_title,
        "url": pr_url,
        "readiness_token": readiness_token,
    },
    "validation": {
        "validator_version": validator_version,
        "pre_validation_result": validation_result,
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
        "execution_state": ".runtime/execution-state.json",
        "failure_report": ".runtime/failure-report.json",
        "run_lock": ".runtime/run.lock",
    },
    "runtime": {
        "current_stage": current_stage,
        "stage_status": current_stage_status,
        "run_status": run_status,
    },
    "contract": {
        "input": {
            "repository_state": "working-copy",
            "task": task_description,
            "runtime_environment": "shell",
        },
        "output": {
            "rendered_pr_body_artifact": pr_body_file,
            "execution_report": ".runtime/execution-report.json",
            "debug_trace": ".runtime/debug-trace.jsonl",
            "pr_url": pr_url,
        },
    },
    "stages": stages,
    "debug": {
        "trace_enabled": True,
        "failure_stage": failure_stage,
        "fail_classification": failure_classification,
        "error_summary": error_summary,
    },
}

with open(report_file, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")
PYEOF

  executor_runtime_write_state
}

executor_runtime_load_context() {
  [[ -f "${EXECUTOR_REPORT_FILE}" ]] || return 0
  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || return 0

  eval "$("${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_REPORT_FILE}"
import json
import shlex
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

stage_map = {stage["name"]: stage for stage in data.get("stages", [])}

def emit(name, value):
    print(f"{name}={shlex.quote(str(value))}")

emit("EXECUTOR_SCHEMA_VERSION", data.get("schema_version", "phase48-v1"))
emit("EXECUTOR_RUN_ID", data.get("run_id", ""))
emit("EXECUTOR_NAME", data.get("executor", {}).get("name", ""))
emit("EXECUTOR_VERSION", data.get("executor", {}).get("version", ""))
emit("EXECUTOR_REPOSITORY_BRANCH", data.get("repository", {}).get("branch", ""))
emit("EXECUTOR_REPOSITORY_BASE_COMMIT", data.get("repository", {}).get("base_commit", ""))
emit("EXECUTOR_REPOSITORY_HEAD_COMMIT", data.get("repository", {}).get("head_commit", ""))
emit("EXECUTOR_REPOSITORY_WORKSPACE_CLEAN", "true" if data.get("repository", {}).get("workspace_clean") else "false")
emit("EXECUTOR_REPOSITORY_CHANGED_FILES_NL", "\n".join(data.get("repository", {}).get("changed_files", [])))
emit("EXECUTOR_REPOSITORY_UNTRACKED_FILES_NL", "\n".join(data.get("repository", {}).get("untracked_files", [])))
emit("EXECUTOR_PR_BODY_FILE", data.get("pr", {}).get("body_file", ""))
emit("EXECUTOR_PR_TITLE", data.get("pr", {}).get("title", ""))
emit("EXECUTOR_PR_URL", data.get("pr", {}).get("url", ""))
emit("EXECUTOR_PR_READINESS_TOKEN", data.get("pr", {}).get("readiness_token", "PR-ready"))
emit("EXECUTOR_VALIDATOR_VERSION", data.get("validation", {}).get("validator_version", ""))
emit("EXECUTOR_VALIDATION_RESULT", data.get("validation", {}).get("pre_validation_result", "pending"))
emit("EXECUTOR_VALIDATOR_COMMAND", data.get("validation", {}).get("validator_command", ""))
emit("EXECUTOR_STARTED_AT", data.get("timing", {}).get("started_at", ""))
emit("EXECUTOR_STARTED_MS", data.get("timing", {}).get("started_ms", ""))
emit("EXECUTOR_FINISHED_AT", data.get("timing", {}).get("finished_at", ""))
emit("EXECUTOR_FINISHED_MS", data.get("timing", {}).get("finished_ms", ""))
emit("EXECUTOR_CURRENT_STAGE", data.get("runtime", {}).get("current_stage", "bootstrap"))
emit("EXECUTOR_CURRENT_STAGE_STATUS", data.get("runtime", {}).get("stage_status", "pending"))
emit("EXECUTOR_RUN_STATUS", data.get("runtime", {}).get("run_status", "pending"))
emit("EXECUTOR_TASK_DESCRIPTION", data.get("contract", {}).get("input", {}).get("task", ""))
emit("EXECUTOR_FAILURE_STAGE", data.get("debug", {}).get("failure_stage", "none"))
emit("EXECUTOR_FAILURE_CLASSIFICATION", data.get("debug", {}).get("fail_classification", "none"))
emit("EXECUTOR_ERROR_SUMMARY", data.get("debug", {}).get("error_summary", ""))

for stage_name in (
    "bootstrap",
    "main_sync",
    "branch_create",
    "executor_runtime",
    "pr_body_render",
    "pre_validation",
    "pr_create",
    "post_create",
):
    stage = stage_map.get(stage_name, {})
    print(f"EXECUTOR_STAGE_STATUS[{shlex.quote(stage_name)}]={shlex.quote(str(stage.get('stage_status', 'pending')))}")
    print(f"EXECUTOR_STAGE_STARTED_AT[{shlex.quote(stage_name)}]={shlex.quote(str(stage.get('started_at', '')))}")
    print(f"EXECUTOR_STAGE_ENDED_AT[{shlex.quote(stage_name)}]={shlex.quote(str(stage.get('ended_at', '')))}")
    print(f"EXECUTOR_STAGE_RETRY_COUNT[{shlex.quote(stage_name)}]={shlex.quote(str(stage.get('retry_count', 0)))}")
    print(f"EXECUTOR_STAGE_FAIL_CLASSIFICATION[{shlex.quote(stage_name)}]={shlex.quote(str(stage.get('fail_classification', 'none')))}")
PYEOF
)"
}

executor_runtime_load_state() {
  [[ -f "${EXECUTOR_STATE_FILE}" ]] || return 1
  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || return 1

  eval "$("${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_STATE_FILE}"
import json
import shlex
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

def emit(name, value):
    print(f"{name}={shlex.quote(str(value))}")

emit("EXECUTOR_RUN_ID", data.get("run_id", ""))
emit("EXECUTOR_CURRENT_STAGE", data.get("current_stage", "bootstrap"))
emit("EXECUTOR_STATE_COMPLETED_STAGES_NL", "\n".join(data.get("completed_stages", [])))
emit("EXECUTOR_STATE_FAILED_STAGE", data.get("failed_stage", "none"))
emit("EXECUTOR_STATE_FAILURE_CLASS", data.get("failure_class", "none"))
emit("EXECUTOR_REPOSITORY_BRANCH", data.get("branch_name", ""))
emit("EXECUTOR_REPOSITORY_HEAD_COMMIT", data.get("commit_head", ""))
emit("EXECUTOR_PR_BODY_FILE", data.get("pr_body_file", ""))
emit("EXECUTOR_STATE_LAST_UPDATED_AT", data.get("last_updated_at", ""))

retry_count_by_stage = data.get("retry_count_by_stage", {})
for stage_name in (
    "bootstrap",
    "main_sync",
    "branch_create",
    "executor_runtime",
    "pr_body_render",
    "pre_validation",
    "pr_create",
    "post_create",
):
    print(f"EXECUTOR_STAGE_RETRY_COUNT[{shlex.quote(stage_name)}]={shlex.quote(str(retry_count_by_stage.get(stage_name, 0)))}")
PYEOF
)"
}

executor_runtime_stage_completed() {
  local stage="$1"
  [[ $'\n'"${EXECUTOR_STATE_COMPLETED_STAGES_NL}"$'\n' == *$'\n'"${stage}"$'\n'* ]]
}

executor_runtime_resume_allowed_for_stage() {
  case "$1" in
    main_sync|branch_create|executor_runtime|pr_body_render|pre_validation)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

executor_runtime_is_retryable_class() {
  case "$1" in
    transient_command_error|transient_network_error|gh_api_temporary_error)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

executor_runtime_retry_backoff_seconds() {
  case "$1" in
    1) printf '2' ;;
    2) printf '5' ;;
    *) printf '5' ;;
  esac
}

executor_runtime_record_command_failure() {
  local command_string="$1"
  local exit_code="$2"
  local fail_classification="$3"

  EXECUTOR_LAST_COMMAND="${command_string}"
  EXECUTOR_LAST_EXIT_CODE="${exit_code}"
  EXECUTOR_LAST_FAILURE_CLASSIFICATION="${fail_classification}"
}

executor_runtime_classify_command_failure() {
  local stage="$1"
  shift

  if [[ $# -ge 2 && "$1" == "git" && "$2" == "fetch" ]]; then
    printf 'transient_network_error'
    return
  fi

  if [[ $# -ge 2 && "$1" == "gh" && "$2" == "pr" ]]; then
    if [[ "${stage}" == "pr_create" ]]; then
      printf 'gh_api_temporary_error'
      return
    fi
  fi

  if [[ $# -ge 1 && "$1" == "gh" ]]; then
    printf 'gh_api_temporary_error'
    return
  fi

  printf 'unknown_error'
}

executor_runtime_resume_eligible() {
  local stage="$1"
  local fail_classification="$2"

  if ! executor_runtime_resume_allowed_for_stage "${stage}"; then
    return 1
  fi

  if executor_runtime_is_retryable_class "${fail_classification}"; then
    return 0
  fi

  case "${fail_classification}" in
    validation_error|repo_state_error|config_error|auth_error|branch_policy_error|unknown_error)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

executor_runtime_repo_status_summary() {
  git status --short --branch 2>/dev/null || true
}

executor_runtime_suggested_operator_action() {
  local fail_classification="$1"
  local stage="$2"

  case "${fail_classification}" in
    transient_network_error|gh_api_temporary_error|transient_command_error)
      printf 'Inspect network/API availability, then rerun with EXECUTOR_RESUME=1 after confirming the workspace and runtime lock state.'
      ;;
    validation_error)
      printf 'Fix the PR metadata or diff mismatch, then rerun pre-validation without forcing resume.'
      ;;
    repo_state_error|branch_policy_error)
      printf 'Restore the repository to the expected branch and clean state before rerunning.'
      ;;
    config_error|auth_error)
      printf 'Fix the missing configuration or authentication issue before rerunning.'
      ;;
    *)
      printf 'Inspect .runtime/debug-trace.jsonl and the repository state before retrying stage %s manually.' "${stage}"
      ;;
  esac
}

executor_runtime_write_failure_report() {
  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || return

  local stage="$1"
  local command_string="$2"
  local exit_code="$3"
  local fail_classification="$4"
  local retry_attempt="$5"
  local resume_eligible="$6"
  local resume_block_reason="$7"
  local repo_status_summary
  local suggested_action
  local timestamp
  local retryable="false"

  if executor_runtime_is_retryable_class "${fail_classification}"; then
    retryable="true"
  fi

  repo_status_summary="$(executor_runtime_repo_status_summary)"
  suggested_action="$(executor_runtime_suggested_operator_action "${fail_classification}" "${stage}")"
  timestamp="$(executor_runtime_now_iso)"

  "${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_FAILURE_FILE}" "${EXECUTOR_SCHEMA_VERSION}" "${EXECUTOR_SCHEMA_VERSION}" "${EXECUTOR_RUN_ID}" "${stage}" "${command_string}" "${exit_code}" "${fail_classification}" "${retryable}" "${retry_attempt}" "${timestamp}" "${EXECUTOR_REPOSITORY_BRANCH}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}" "${resume_eligible}" "${resume_block_reason}" "${repo_status_summary}" "${suggested_action}"
import json
import sys

(
    failure_file,
    schema_version,
    runtime_version,
    run_id,
    stage,
    command,
    exit_code,
    failure_class,
    retryable,
    retry_attempt,
    timestamp,
    branch_name,
    commit_head,
    resume_eligible,
    resume_block_reason,
    repo_status_summary,
    suggested_operator_action,
) = sys.argv[1:]

report = {
    "schema_version": schema_version,
    "runtime_version": runtime_version,
    "run_id": run_id,
    "stage": stage,
    "command": command,
    "exit_code": int(exit_code or "1"),
    "failure_class": failure_class,
    "retryable": retryable == "true",
    "retry_attempt": int(retry_attempt or "0"),
    "timestamp": timestamp,
    "branch_name": branch_name,
    "commit_head": commit_head,
    "resume_eligible": resume_eligible == "true",
    "resume_block_reason": resume_block_reason,
    "repo_status_summary": repo_status_summary,
    "suggested_operator_action": suggested_operator_action,
}

with open(failure_file, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")
PYEOF
}

executor_runtime_reconcile_existing_pr() {
  local branch_name="${EXECUTOR_REPOSITORY_BRANCH}"
  local body_file="${EXECUTOR_PR_BODY_FILE}"
  local gh_output
  local status
  local reconcile_output

  [[ -n "${branch_name}" ]] || return 1
  [[ -n "${body_file}" && -f "${body_file}" ]] || return 2

  set +e
  gh_output="$(gh pr view --head "${branch_name}" --json url,body 2>/dev/null)"
  status=$?
  set -e

  if [[ "${status}" -ne 0 || -z "${gh_output}" ]]; then
    return 1
  fi

  set +e
  reconcile_output="$("${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${body_file}" "${gh_output}"
import json
import sys
from pathlib import Path

body_file = Path(sys.argv[1])
payload = json.loads(sys.argv[2])
local_body = body_file.read_text(encoding="utf-8")
remote_body = payload.get("body", "")

if local_body == remote_body:
    print(payload.get("url", ""))
    sys.exit(0)

sys.exit(1)
PYEOF
)"
  status=$?
  set -e
  if [[ "${status}" -ne 0 ]]; then
    EXECUTOR_RECONCILED_PR_URL=""
    return 2
  fi

  EXECUTOR_RECONCILED_PR_URL="${reconcile_output}"
  EXECUTOR_PR_URL="${EXECUTOR_RECONCILED_PR_URL}"
  executor_runtime_trace_event "pr_create" "ok" "reconciled existing pull request after create failure" "${EXECUTOR_PR_URL}"
  return 0
}

executor_runtime_acquire_lock() {
  mkdir -p "${EXECUTOR_RUNTIME_DIR}"

  if [[ -e "${EXECUTOR_LOCK_FILE}" ]]; then
    printf 'ERROR: executor run lock already exists: %s\n' "${EXECUTOR_LOCK_FILE}" >&2
    return 1
  fi

  cat > "${EXECUTOR_LOCK_FILE}" <<EOF
run_id=${EXECUTOR_RUN_ID}
pid=$$
branch=${EXECUTOR_REPOSITORY_BRANCH}
stage=${EXECUTOR_CURRENT_STAGE}
created_at=$(executor_runtime_now_iso)
EOF
  EXECUTOR_LOCK_ACQUIRED="1"
  return 0
}

executor_runtime_release_lock() {
  if [[ "${EXECUTOR_LOCK_ACQUIRED}" == "1" && -f "${EXECUTOR_LOCK_FILE}" ]]; then
    rm -f "${EXECUTOR_LOCK_FILE}"
  fi
  EXECUTOR_LOCK_ACQUIRED="0"
}
