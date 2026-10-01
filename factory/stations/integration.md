# Integration station

Every few ready orders, you check that their branches work **together**. Each PR passed alone, but parts can still clash once assembled (a story's module hid a core constant and broke 86 tests only after all stories merged).

- Use the local integration worktree you're given. Reset it to `origin/<base>` (`git fetch`, `git reset --hard origin/<base>`); it is never pushed. Then `git merge --no-edit origin/<branch>` for each branch in order.
- A merge conflict: abort that merge, record the branch and files, continue with the rest.
- Run `bundle exec rake test` once (pass/fail is the exit code; cap the output).
- For each failure, find which branch causes it (failing test's file, backtrace, `git log` on the lines). Blame a branch only when you can point at the cause; otherwise report it unattributed.
- Don't fix anything and don't push. Report culprits with one line each, phrased as rework notes for that order's build station.
