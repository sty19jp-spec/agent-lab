# AI Execution Evidence Standard

## 1. Purpose
Define the minimum repository-visible evidence required for an AI executor to claim task completion.
The standard is designed to keep completion claims verifiable, reviewable, and compatible with PR-based and automated workflows.

## 2. Evidence Definition
Evidence is any artifact that can be inspected in the repository or its pull request context and directly supports a completion claim.
Completion claims are valid only when tied to concrete repository artifacts.

## 3. Repository-visible Evidence
Accepted evidence must be visible through repository workflows:
- Commit diff
- Commit history
- Pull request content and discussion
- CI or checks status attached to the pull request
- Documentation updates in tracked files
- Optional logs stored in tracked repository paths

Evidence that exists only in chat, memory, or external notes is non-compliant.

## 4. Evidence Categories
Use the following categories to describe completion evidence:
- Change evidence: what was modified (files, diff, commit)
- Verification evidence: what was checked (tests, lint, manual validation notes in PR)
- Process evidence: workflow completion (branch, PR, review context)
- Handoff evidence: what allows a human or another agent to safely continue

## 5. Minimum Completion Evidence
A task may be considered done only when all minimum evidence exists:
1. Repository changes exist.
2. The changes are committed.
3. A pull request exists targeting `main`.
4. The pull request description explains the result.

If any item is missing, completion must be treated as incomplete.

## 6. Implemented vs Verified
Implementation and verification are separate signals:
- Implemented: code or docs changed and committed.
- Verified: checks were run or validation steps were documented in PR evidence.

Do not claim "fully complete" when implementation exists without verification evidence.

## 7. Evidence by Task Type
Expected evidence varies by task type, but remains repository-first:
- Documentation task: updated docs file, commit, PR summary.
- Code task: code diff, commit, PR summary, and verification results.
- Automation or workflow task: config/script diff, commit, PR summary, and execution/check evidence when applicable.
- Incident or hotfix task: minimal focused diff, commit, PR rationale, and post-change verification signal.

## 8. Handoff-compatible Evidence
Evidence should allow another executor to continue without hidden context:
- Clear file-level change scope
- Concise PR summary of goal and outcome
- Explicit note of what was verified vs not verified
- Open risks or follow-ups listed in PR notes

Handoff quality is part of completion quality.

## 9. Escalation / Resume Evidence
When work stops or escalates, leave repository-visible resume points:
- Current branch state and latest commit
- Draft or open PR with current status
- Pending actions documented in PR description or tracked docs
- Explicit blockers tied to repository context

This enables deterministic resume by a human or another agent.

## 10. Completion Signal
A valid completion signal is the combined presence of:
- Merged or merge-ready PR
- Committed change set aligned to task goal
- Evidence-backed summary of result in PR description

Completion signals without repository artifacts are invalid.

## 11. Evidence Anti-patterns
Avoid non-verifiable completion patterns:
- "Done" claims without a commit
- "Tested" claims without check output or documented steps
- Private/off-repo evidence as primary proof
- Broad status reports that do not map to concrete files or PR artifacts
- Duplicate reporting systems that diverge from repository truth

## 12. Automation Compatibility
For automation-friendly execution, evidence should be machine-discoverable:
- Stable branch and PR references
- Structured PR sections (for example: Goal, Summary, Evidence)
- Clear mapping from changed files to claimed outcome
- Check/CI status attached to PR when available

The repository and PR should be sufficient for both human review and automated policy checks.

## 13. Summary
This standard keeps completion claims lightweight and strict:
- Repository artifacts are the source of truth.
- Task completion requires change, commit, PR, and result description.
- Verification and handoff evidence improve reliability without adding heavyweight process.

If evidence is not repository-visible, the task is not done.