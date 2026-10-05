# Releasing agentmon

A release is a `vX.Y.Z` tag on a commit on `main`. Pushing the tag runs
`.github/workflows/publish.yml`, which publishes the gem to RubyGems and creates the GitHub Release.
Agents never tag or publish; the owner does.

## Changelog

User-facing changes go under `## Unreleased` at the top of CHANGELOG.md, in the PR that makes them.

## Cut a release

1. On `main`, set `VERSION` in `lib/agentmon/version.rb` to `X.Y.Z`.
2. In CHANGELOG.md, move the `## Unreleased` entries under a new `## X.Y.Z` heading, leaving
   `## Unreleased` empty above it.
3. Commit both on `main` (directly or through a PR), then tag and push:

   ```
   git tag vX.Y.Z && git push origin main vX.Y.Z
   ```

Publish then:
- checks the tag is `vX.Y.Z` and equals `Agentmon::VERSION`;
- checks the tagged commit is on `main` (an ancestor of `origin/main`);
- checks RubyGems doesn't already have agentmon `X.Y.Z` (HTTP 404 from its API; a 200 or any
  other answer fails without publishing);
- takes the release notes from CHANGELOG.md's `## X.Y.Z` section (fails if it's empty);
- builds `agentmon-X.Y.Z.gem`, pushes it with trusted publishing (no API key) in the GitHub
  environment `release`;
- creates the GitHub Release `vX.Y.Z` with the gem attached and the changelog section as notes.

## When something fails

- A check fails (wrong version, not on main, no changelog section): nothing was published. Fix it
  on main, move the tag (`git tag -f vX.Y.Z <commit> && git push -f origin vX.Y.Z`) or delete it
  (`git push origin :refs/tags/vX.Y.Z`) and tag again.
- Build or credentials fail before "Push the gem to RubyGems": re-run the failed job.
- It fails after the gem is on RubyGems: re-running stops at the "already on RubyGems" check by
  design. Create the release by hand: `gem build agentmon.gemspec`, then
  `gh release create vX.Y.Z agentmon-X.Y.Z.gem --verify-tag --title "agentmon X.Y.Z" --notes-file <notes>`.
- A version on RubyGems can't be replaced: fix forward with `X.Y.(Z+1)`.

## One-time setup (owner)

1. r2ui must be on RubyGems first: the gemspec depends on `r2ui ~> 0.2`, which `gem install
   agentmon` resolves from RubyGems (the Gemfile's sibling/GitHub override is for development only).
2. agentmon doesn't exist on RubyGems yet, so add a *pending* trusted publisher: rubygems.org →
   your profile → Trusted publishers → Create (pending trusted publisher): gem name `agentmon`,
   GitHub Actions, repository owner `satoramoto`, repository name `agentmon`, workflow filename
   `publish.yml`, environment `release`. The first publish creates the gem and turns it into a
   normal trusted publisher.
3. The GitHub environment `release` is created on first use; add required reviewers to it to
   approve each publish. If you restrict its deployment refs, allow tags `v*.*.*`.
