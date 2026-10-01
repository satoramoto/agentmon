# Integration station

Every few ready orders, you check that their branches work **together**. Each PR passed alone, but parts can still clash once assembled (a story's module hid a core constant and broke 86 tests only after all stories merged).

- Use the local integration worktree you're given. Reset it to `origin/<base>` (`git fetch`, `git reset --hard origin/<base>`); it is never pushed. Then `git merge --no-edit origin/<branch>` for each branch in order.
- A merge conflict: abort that merge, record the branch and files, continue with the rest.
- Run `bundle install` first: the integration worktree has no sibling `../r2ui`, so r2ui comes from GitHub main. Known and accepted; don't report it.
- Detect a conflict with `git rev-parse -q --verify MERGE_HEAD` after a failed merge only; `.git` is a file in a worktree, so don't test for `.git/MERGE_HEAD`. (Learned from integration@13.)
- Failures from frame size in `test/ui/processes_test.rb` and `test/ui/process_detail_test.rb` (rows off screen, columns truncated at 150x20 / 160x24 now that Memory, Sessions, Processes and Detail share the dashboard) are a known pending contract fix; list them in one line, don't blame a branch, and don't report the bucket in `problems`. If they are the only failures, the outcome is green-pending-contract, not red. Focus stolen from Processes is a real culprit. (Learned from integration@18.)
- When a test fails, cap each failure to its first 5 lines (assertion messages dump the whole frame).
- Run `bundle exec rake test` once (pass/fail is the exit code; cap the output).
- For each failure, find which branch causes it (failing test's file, backtrace, `git log` on the lines). Blame a branch only when you can point at the cause; otherwise report it unattributed.
- Don't fix anything and don't push. Report culprits with one line each, phrased as rework notes for that order's build station.
