#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

main() {
  local target_branch
  local origin_head
  local start_commit
  local pr_body_file

  require_task

  cd "${REPO_ROOT}"

  load_nvm
  require_codex

  target_branch="codex/${TASK}"

  ensure_main_branch
  ensure_clean_worktree
  ensure_branch_available "${target_branch}"

  git fetch origin
  git switch main
  git reset --hard origin/main

  git switch -c "${target_branch}"

  origin_head="$(git rev-parse --short origin/main)"
  start_commit="$(git rev-parse --short HEAD)"
  pr_body_file="/tmp/$(basename "${REPO_ROOT}")-${target_branch//\//-}-pr-body.md"

  export CODEX_PR_BODY_FILE="${pr_body_file}"
  export CODEX_PR_BASE_BRANCH="main"
  export CODEX_PR_PREVALIDATE_SCRIPT="${REPO_ROOT}/scripts/pre-validate-pr.sh"

  log "Started Codex task"
  log "  repository : $(basename "${REPO_ROOT}")"
  log "  branch     : ${target_branch}"
  log "  origin/main: ${origin_head}"
  log "  head       : ${start_commit}"
  log "  pr body    : ${CODEX_PR_BODY_FILE}"
  log "  pr flow    : render PR body -> pre-validate same file -> gh pr create --body-file"
  log

  exec codex --ask-for-approval never --sandbox workspace-write
}

main "$@"
