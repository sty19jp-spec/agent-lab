#!/usr/bin/env bash

if [[ -n "${EXECUTOR_HEALTH_LIB_LOADED:-}" ]]; then
  return 0
fi
EXECUTOR_HEALTH_LIB_LOADED=1

executor_health_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || executor_die_config "missing command: $1"
}

executor_health_touch_optional_artifact() {
  local file_path="$1"
  local label="$2"

  if [[ ! -e "${file_path}" ]]; then
    mkdir -p "$(dirname "${file_path}")"
    : > "${file_path}"
    executor_runtime_note_repair_attempt "optional_artifact_recreate" "success" "recreated missing ${label}: ${file_path}"
  fi
}

executor_health_validate_state_file() {
  local validation_output
  local status

  [[ -f "${EXECUTOR_STATE_FILE}" ]] || return 0
  [[ -n "${EXECUTOR_PYTHON_BIN}" ]] || executor_die_config "python is required to validate runtime state"

  set +e
  validation_output="$("${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_STATE_FILE}" "${EXECUTOR_STATE_SCHEMA_VERSION}" "$(executor_runtime_now_iso)"
import json
import sys
from pathlib import Path

state_file = Path(sys.argv[1])
schema_version = sys.argv[2]
timestamp = sys.argv[3]

try:
    data = json.loads(state_file.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"invalid runtime state JSON: {exc}")
    sys.exit(1)

if not isinstance(data, dict):
    print("runtime state must be a JSON object")
    sys.exit(1)

required = ("run_id", "current_stage", "branch_name", "commit_head")
missing = [name for name in required if not str(data.get(name, "")).strip()]
if missing:
    print("missing required runtime state fields: " + ", ".join(missing))
    sys.exit(1)

repaired = []
if not str(data.get("schema_version", "")).strip():
    data["schema_version"] = schema_version
    repaired.append("schema_version")

if not isinstance(data.get("completed_stages"), list):
    data["completed_stages"] = []
    repaired.append("completed_stages")

if not isinstance(data.get("retry_count_by_stage"), dict):
    data["retry_count_by_stage"] = {}
    repaired.append("retry_count_by_stage")

if not str(data.get("failed_stage", "")).strip():
    data["failed_stage"] = "none"
    repaired.append("failed_stage")

if not str(data.get("failure_class", "")).strip():
    data["failure_class"] = "none"
    repaired.append("failure_class")

if "pr_body_file" not in data:
    data["pr_body_file"] = ""
    repaired.append("pr_body_file")

if not str(data.get("last_updated_at", "")).strip():
    data["last_updated_at"] = timestamp
    repaired.append("last_updated_at")

if repaired:
    state_file.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print("REPAIRED:" + ",".join(repaired))
else:
    print("OK")
PYEOF
)"
  status=$?
  set -e

  if [[ "${status}" -ne 0 ]]; then
    executor_die_repo_state "runtime state validation failed: ${validation_output}"
  fi

  if [[ "${validation_output}" == REPAIRED:* ]]; then
    executor_runtime_note_repair_attempt "state_default_repair" "success" "${validation_output#REPAIRED:}"
  fi
}

executor_health_validate_lock_consistency() {
  local target_branch="$1"
  local run_id=""
  local pid=""
  local branch=""
  local state_info
  local state_status
  local state_run_id=""
  local state_branch=""

  [[ -f "${EXECUTOR_LOCK_FILE}" ]] || return 0

  while IFS='=' read -r key value; do
    case "${key}" in
      run_id) run_id="${value}" ;;
      pid) pid="${value}" ;;
      branch) branch="${value}" ;;
    esac
  done < "${EXECUTOR_LOCK_FILE}"

  if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    executor_die_repo_state "executor run lock already exists: ${EXECUTOR_LOCK_FILE}"
  fi

  [[ -f "${EXECUTOR_STATE_FILE}" ]] || executor_die_repo_state "stale runtime lock cannot be proven safe without ${EXECUTOR_STATE_FILE}"

  set +e
  state_info="$("${EXECUTOR_PYTHON_BIN}" - <<'PYEOF' "${EXECUTOR_STATE_FILE}"
import json
import sys

data = json.loads(open(sys.argv[1], encoding="utf-8").read())
print(data.get("run_id", ""))
print(data.get("branch_name", ""))
PYEOF
)"
  state_status=$?
  set -e

  if [[ "${state_status}" -ne 0 ]]; then
    executor_die_repo_state "failed to inspect runtime state while validating ${EXECUTOR_LOCK_FILE}"
  fi

  state_run_id="$(printf '%s\n' "${state_info}" | sed -n '1p')"
  state_branch="$(printf '%s\n' "${state_info}" | sed -n '2p')"

  [[ -n "${run_id}" && "${run_id}" == "${state_run_id}" ]] || executor_die_repo_state "stale lock run_id mismatch; refusing auto-clear"
  [[ -n "${branch}" && "${branch}" == "${state_branch}" ]] || executor_die_repo_state "stale lock branch mismatch; refusing auto-clear"
  [[ -z "${target_branch}" || "${branch}" == "${target_branch}" ]] || executor_die_repo_state "stale lock target mismatch; refusing auto-clear"

  rm -f "${EXECUTOR_LOCK_FILE}"
  executor_runtime_note_repair_attempt "stale_lock_clear" "success" "cleared stale executor lock after dead pid validation"
}

executor_health_run_preflight() {
  local target_branch="$1"
  shift

  executor_health_require_cmd git
  while [[ $# -gt 0 ]]; do
    executor_health_require_cmd "$1"
    shift
  done

  git rev-parse --git-dir >/dev/null 2>&1 || executor_die_repo_state "current directory is not a git repository"
  mkdir -p "${EXECUTOR_RUNTIME_DIR}"
  executor_health_touch_optional_artifact "${EXECUTOR_TRACE_FILE}" "debug trace"
  executor_health_touch_optional_artifact "${EXECUTOR_METRICS_FILE}" "reliability metrics"
  executor_health_validate_state_file
  executor_health_validate_lock_consistency "${target_branch}"

  EXECUTOR_HEALTH_STATUS="pass"
  EXECUTOR_HEALTH_SUMMARY="runtime self-check passed"
  executor_runtime_trace_event "${EXECUTOR_CURRENT_STAGE}" "ok" "runtime self-check passed" "${EXECUTOR_RUNTIME_DIR}"
}
