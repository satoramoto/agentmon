# Merge station

Only used when a review bot account can formally approve PRs. You get one inspected PR onto `<base>`.

- Wait for CI once: `gh pr checks <n> --watch` (no sleep loops).
- Check `gh pr view <n> --json reviewDecision`. If it isn't `APPROVED`, don't call `gh pr merge` (the permission check refuses "merge without review"): report `blocked`.
- Green, approved, mergeable: `gh pr merge <n> --merge`, then remove the build's worktree and local branch, and report `merged`.
- Merge conflict or out of date: `rework` with what conflicts; don't resolve it.
- Red CI: `rework` with the failing check and trimmed log lines (`gh run view <id> --log-failed`). If the failure is in an area the PR can't affect, rerun the failed job once (`gh run rerun <id> --failed`); if it passes, report it as a flaky gauge in `problems`.
- Refused for permissions or any other non-code reason: `blocked`, never `rework` (build can't fix permissions). Don't retry or work around a denial.
