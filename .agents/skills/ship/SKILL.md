# ship

Use this workflow for a governed change after Task Master evidence exists.

1. Confirm the active task ID and affected scope; run the focused red/green
   tests and `review-2` checks.
2. Create `codex/task-<id>-<slug>` from the verified base branch.
3. Commit only the intended files, push the branch, and open a non-draft PR
   with a concise evidence summary.
4. Enable squash auto-merge with branch deletion. Do not ask the user to open,
   read, approve, or explain the PR.
5. Wait for required checks. If a check fails, keep the task unfinished,
   diagnose the failure, patch the branch, and retry. Report only the plain
   language outcome after merge.

Never use `--no-verify`, bypass required checks, force-push a protected branch,
or bypass destructive-action confirmation.
