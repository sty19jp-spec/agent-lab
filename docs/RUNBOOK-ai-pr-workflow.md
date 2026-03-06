# RUNBOOK: AI PR Workflow (Minimal)

## Purpose

Keep changes small, reviewable, and merge through Pull Requests.

## Standard Flow

AI or Human
-> feature branch
-> edit
-> `git diff` / `git status` check
-> commit
-> push
-> Pull Request
-> human merge
-> `main`

## Practical Steps

1. Create a feature branch from `main`.
2. Make the smallest possible change.
3. Check changes with `git status` and `git diff`.
4. Commit with a clear message.
5. Push the branch to GitHub.
6. Open a Pull Request.
7. Human performs final merge to `main`.

## Notes

- Keep governance minimal.
- Do not bypass PR merge flow.
- Keep approvals/check requirements as currently configured.
