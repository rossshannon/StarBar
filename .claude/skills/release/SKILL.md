---
name: release
description: Use when cutting a StarBar release, or when asked to "release", "ship", "tag" or "publish" a version, write or check release notes, or work out what has merged since the last release. Covers scope, the notes in docs/releases/, the release pull request, the one command that tags and publishes, and the checks afterwards. The product site's half is the `release-site` skill in the site's repository.
---

# Release StarBar

> **⚠️ Learning mode — this skill is young.** It was written from the 1.5.0 to
> 1.10.0 releases and has not yet run a release itself, so the steps below are
> still settling. **Each time you use it, iterate it in the same session**:
> sharpen any fuzzy step, smooth the rough edge you hit, and fold in any new
> failure mode or request the maintainer raised. Then append a dated one-liner
> to the Learning-mode iteration log at the bottom, and put the edit in the
> release's own pull request or the next one.

A release is: notes merged to `main`, a `v*` tag on that merge commit, the Release workflow's zip on a GitHub release, the hand-written title and notes on that release, and then the product site. **An agent session prepares and checks; the maintainer publishes.** Pushing a tag and editing a release are public and can't be taken back, and agent sessions are usually refused both, so don't try: the skill ends in one command for the maintainer to run in their own terminal.

Versions are three numbers. "1.11" means `1.11.0`, tag `v1.11.0`. A new feature raises the middle number; fixes alone raise the last.

## 1. Scope

```bash
git fetch origin main --tags
PREV=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main)
git log --first-parent --oneline "$PREV"..origin/main
git diff --stat "$PREV" origin/main -- .github/workflows build.sh StarBar/StarBar.entitlements "Privacy Policy.md" README.md
```

- Read every merged pull request in that range. Settle the version and a title of a few words with the maintainer if they haven't given them.
- A change to `release.yml` or `build.sh` has never run for a tag: say so in the hand-over, since the Release run is its first test.
- Check nothing meant for this release is still open, and that nothing unfinished has merged.

## 2. Notes and the release pull request

1. Write `docs/releases/vX.Y.Z.md`, following [references/notes-style.md](references/notes-style.md) and the last two files beside it.
2. Check it: `bash .claude/skills/release/scripts/check-notes.sh X.Y.Z`
3. Bring `README.md` (features, screenshots) and `Privacy Policy.md` up to date if the release changes what they describe.
4. Open the release pull request with those changes. It is the last thing merged before the tag: the tag goes on its merge commit. Its CI run also runs the notes check.

## 3. The site

The site's version, release section and media are prepared in the site's repository with its `release-site` skill, as a pull request of its own. Start it now so both are ready together, but **it is merged and deployed only after the GitHub release is public**, because the site sends people to the latest release.

## 4. Go-ahead

Ask the maintainer once, with both pull requests, the title, and the notes as they will appear. Their yes covers merging both. Publishing and deploying stay theirs.

## 5. Merge

Merge the release pull request as a merge commit. Wait for the Tests workflow to pass on that commit on `main`. **Nothing else merges to `main` until the tag is pushed**: `publish.sh` refuses unless `origin/main` is the release commit.

## 6. Publish (the maintainer)

Hand over this, with the merge commit's full SHA filled in, as one line:

```bash
cd <their StarBar checkout> && git fetch origin main --tags && bash <(git show <sha>:.claude/skills/release/scripts/publish.sh) X.Y.Z <sha>
```

`publish.sh` runs as it stands in that commit and reads the notes from it, so the checkout's branch and uncommitted work don't matter and aren't touched. It checks `origin/main`, the notes and the tests, tags, pushes, waits for the Release run, then sets the title and notes, adding the Source and Package lines. It ends with a block headed `=== Published ===` for the maintainer to paste back. Adding `--dry-run` runs every check and stops before tagging.

## 7. Check

Read the release back with the GitHub tools, whatever the pasted block says:

- the title is line 1 of the notes; the body is the rest plus `**Source:**` (the merge commit) and `**Package:**` (the version, and a build number equal to the commit count)
- `StarBar-vX.Y.Z.zip` and its `.sha256` are attached; it is not a draft or a pre-release; it is marked Latest
- the Release run passed, including any workflow step that changed since the last release

Then the site: merge its pull request and hand over its deploy command, per `release-site`.

## 8. Close

Record the release where the project keeps its log (version, date, build, tag and merge commit, pull requests), list what was left open, and add a line to the iteration log below.

## When a step fails

| What happened | What to do |
|---|---|
| Tests fail on `main` after the merge | Fix forward in a new pull request; the release commit becomes that one's merge. Nothing was tagged |
| `publish.sh` stops before tagging | It says "Nothing has been changed". Fix what it names and run it again |
| The Release run fails on a flaky job | Rerun the failed job, then run the same command again: it sees the tag and carries on |
| The Release run fails on a real fault, with no release made | Merge a fix, then hand over the command with the new SHA and `--retag` on the end. It moves the tag only while no release exists |
| Something is wrong after the release is public | A published tag never moves. Fix the notes on the release page if it is only wording; anything in the app is the next patch version |

## Scripts

- `scripts/check-notes.sh <version>`: the notes' shape. Rules and reasons are in the style reference.
- `scripts/publish.sh <version> <sha> [--dry-run] [--retag]`: the maintainer's command.
- `scripts/tests/`: `python3 -m unittest discover -s .claude/skills/release/scripts/tests`, which CI runs. The tests drive both scripts against a scratch repository and a stand-in for `gh`, and check every file in `docs/releases/`.

## Learning-mode iteration log

On each real run, append a dated one-liner: what you sharpened, what bit you, what the maintainer asked for. When it has run clean across a few releases with no edits needed, drop the banner and this section, and keep a `## Self-improvement — log gotchas to this file` section in its place.

- 2026-11-13 — Skill written from the 1.5.0 to 1.10.0 releases, each of which was published by a script written for it. Not yet run for a release.
