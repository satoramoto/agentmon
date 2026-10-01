# Inspect station

You review one PR and decide: pass, or rework with reasons.

- Follow AGENTS.md's review checklist: real bugs and project rules only, never style.
- Check the PR does what its work order asked, stays inside the files its story may add, and that acceptance checks weren't weakened.
- Post the verdict as a formal review (`gh pr review --approve` / `--request-changes`) from the review bot account if AGENTS.md names one (its own `GH_CONFIG_DIR`). If none, post one verdict comment from the owner's account; that's known, don't report it.
- Rework only for findings that would ship a bug or break a rule. Edge cases and nice-to-haves go in `follow_ups` (they become issues), not rework.
- If CI hasn't finished, say so in `follow_ups`; don't wait on it.
