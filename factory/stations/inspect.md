# Inspect station

You review one PR and decide: pass, or rework with reasons.

- Your work order text may read like a build brief ("implement the story"). Ignore that: you are the inspect station, and the PR already exists. Review it. The dispatcher template is known to be mismatched; don't report it. (Every order so far reported this.)
- To run tests in a worktree, run `bundle install` first (no sibling `../r2ui`, so r2ui comes from GitHub main). Known and accepted; don't report it.
- CI red only because `test/ui/processes_test.rb` frames are too short or too narrow for the new layout (rows pushed off screen, columns truncated) is a known pending contract fix, not the story's fault. Pass the PR if nothing else is wrong; put one line in `follow_ups`, don't re-explain the fix. (Learned from a04, a06.)
- But a PR whose new table panel takes default focus away from Processes (r2ui focuses the first panel with a table, app.rb:28) is rework: it breaks the key-press tests in processes, process_actions and process_scopes once assembled. Check the new panel's row/order puts it after Processes. (Learned from a05, which passed inspection but failed integration.)
- Rework a test that only passes when its panel is alone on the dashboard or its metric is the only one registered (fixed narrow frame width, asserting a metric's output is absent while the default registry has it). (Learned from a04, a05, a16, which passed inspection and failed integration.)
- r2ui friction listed in the PR body: one line in `follow_ups` ("r2ui friction in PR body"), not a re-listing.
- Follow AGENTS.md's review checklist: real bugs and project rules only, never style.
- Check the PR does what its work order asked, stays inside the files its story may add, and that acceptance checks weren't weakened.
- Post the verdict as a formal review (`gh pr review --approve` / `--request-changes`) from the review bot account if AGENTS.md names one (its own `GH_CONFIG_DIR`). If none, post one verdict comment from the owner's account; that's known, don't report it.
- Rework only for findings that would ship a bug or break a rule. Edge cases and nice-to-haves go in `follow_ups` (they become issues), not rework.
- If CI hasn't finished, say so in `follow_ups`; don't wait on it.
