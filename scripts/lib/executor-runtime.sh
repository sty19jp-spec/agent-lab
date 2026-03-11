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

declare -g EXECUTOR_SCHEMA_VERSION="phase47-v1"
declare -g EXECUTOR_RUNTIME_DIR=""
declare -g EXECUTOR_TRACE_FILE=""
declare -g EXECUTOR_REPORT_FILE=""
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

executor_runtime_write_report() {
  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || return

  local finished_at="${1:-$(executor_runtime_now_iso)}"
  local finished_ms="${2:-$(executor_runtime_now_ms)}"
  local stage_payload

  stage_payload="$(executor_runtime_stage_payload)"
  EXECUTOR_FINISHED_AT="${finished_at}"
  EXECUTOR_FINISHED_MS="${finished_ms}"

  "${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_REPORT_FILE}" "${EXECUTOR_SCHEMA_VERSION}" "${EXECUTOR_RUN_ID}" "${EXECUTOR_NAME}" "${EXECUTOR_VERSION}" "${EXECUTOR_REPOSITORY_BRANCH}" "${EXECUTOR_REPOSITORY_BASE_COMMIT}" "${EXECUTOR_REPOSITORY_HEAD_COMMIT}" "${EXECUTOR_REPOSITORY_WORKSPACE_CLEAN}" "${EXECUTOR_REPOSITORY_CHANGED_FILES_NL}" "${EXECUTOR_REPOSITORY_UNTRACKED_FILES_NL}" "${EXECUTOR_PR_BODY_FILE}" "${EXECUTOR_PR_TITLE}" "${EXECUTOR_PR_URL}" "${EXECUTOR_PR_READINESS_TOKEN}" "${EXECUTOR_VALIDATOR_VERSION}" "${EXECUTOR_VALIDATION_RESULT}" "${EXECUTOR_VALIDATOR_COMMAND}" "${EXECUTOR_STARTED_AT}" "${EXECUTOR_STARTED_MS}" "${EXECUTOR_FINISHED_AT}" "${EXECUTOR_FINISHED_MS}" "${EXECUTOR_TRACE_FILE}" "${EXECUTOR_CURRENT_STAGE}" "${EXECUTOR_CURRENT_STAGE_STATUS}" "${EXECUTOR_RUN_STATUS}" "${EXECUTOR_TASK_DESCRIPTION}" "${EXECUTOR_FAILURE_STAGE}" "${EXECUTOR_FAILURE_CLASSIFICATION}" "${EXECUTOR_ERROR_SUMMARY}" "${stage_payload}"
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

emit("EXECUTOR_SCHEMA_VERSION", data.get("schema_version", "phase47-v1"))
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
