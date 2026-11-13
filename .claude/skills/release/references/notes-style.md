# Release notes: the house style

The notes for a release live in `docs/releases/vX.Y.Z.md` and are merged before the release is cut. `publish.sh` puts them on the GitHub release as they are, so the file is the record of what was published. Read the last two files in `docs/releases/` before writing a new one; they are the model.

## Shape

```markdown
# StarBar 1.11.0 — What the release is, in a few words

StarBar 1.11.0 does this and that, in one or two sentences a user would repeat.

**This is the recommended release. Requires macOS 13 or later, and Music or Spotify.**

## The headline feature

- One thing the user will see, as a full sentence.

## Network access

What is sent, to whom, when, and what never causes it.

## Fixed

- What went wrong, as the user saw it, and that it no longer does.

## Installation

(the two paragraphs from the last release, unchanged)

[Changes since 1.10.0](https://github.com/<owner>/<repo>/compare/v1.10.0...v1.11.0).
```

- **Line 1 is the title.** It becomes the GitHub release's title and, with a colon for the dash, the tag's message. Sentence case, an em dash, no full stop. A patch release may be `# StarBar 1.7.1` alone.
- **No Source or Package lines.** `publish.sh` adds them under the notes, from the commit it tagged and the build number the workflow reports. Up to 1.10.0 they were written by hand as `MERGE_COMMIT` and `BUILD_NUMBER`, for each release's own script to substitute.
- **Installation is copied, not rewritten.** Its second paragraph says the build is signed ad hoc and not notarised. If the repository has gained its signing secrets, that paragraph is wrong: rewrite it, and expect `publish.sh` to flag the old wording.

## Writing

- Write for someone who uses the app, not someone who reads the code. Say what they will see or do: "Click the heart and it bursts", not "added `HeartBurstWindow`". No pull request numbers, class names or internal terms.
- Lead with what is new, most noticeable first. Fixes go last, under `## Fixed` or the feature they belong to.
- Each bullet is a full sentence that stands on its own. Bold only for a button or label the user presses.
- British spelling in what the user reads: favourite, notarised, colour.
- Be plain about limits and costs: a feature that works for only some accounts, a song that is missed, a moment of placeholder. Past notes say so in a bullet of their own.
- When a hidden default switches a behaviour off, give the whole `defaults write` command.
- Length follows the release: 1.7.1 is 23 lines, 1.9.0 is 53.

## Network access and Privacy

The app's standing promise is that everything it sends over the network is stated plainly in the release notes. So:

- A release that talks to a new host, or sends something new to an old one, has a `## Network access` section: what is sent, to which host, what triggers it, and what never does. If the Privacy Policy changed, link it.
- A release that reads or keeps something new on the Mac, without sending it, has a `## Privacy` section.
- `check-notes.sh` insists on one of the two when `StarBar/StarBar.entitlements` or `Privacy Policy.md` changed since the last release. That is a floor: 1.7.0 added two hosts under an entitlement the app already had, and only the writer could know its notes needed the section.

## Gathering what changed

```bash
git fetch origin main --tags
PREV=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main)
git log --first-parent --oneline "$PREV"..origin/main
```

Read each merged pull request's description, not only its title: the user-facing behaviour is there, and so is what was measured or left open. `AGENTS.md`'s diff over the same range shows the decisions made along the way.

## What `check-notes.sh` checks, and why

| Rule | Why |
|---|---|
| Line 1 is `# StarBar X.Y.Z`, alone or followed by an em dash and a tagline with no full stop; line 2 is blank | The title is read by `publish.sh`; a hyphen or a wrong version would go straight onto the release |
| Line 3 starts `StarBar X.Y.Z ` | Every release opens the same way, and the version is checked a second time |
| No other `# ` heading | Everything under line 1 is the release's body |
| One recommended-release line | It carries the system requirement |
| One `## Installation`, as the last section | People look for it at the bottom |
| The last line is the compare link, from the release before to this one | The link is copied from the last notes, so it is the line most likely to be left as it was |
| No `MERGE_COMMIT`, `BUILD_NUMBER`, `TODO`, `TBD`, `FIXME`, HTML comment, Source or Package line | Leftovers from drafting |
| Entitlements or Privacy Policy changed since the last release: a `## Network access` or `## Privacy` section | The standing promise above |

The same check runs in CI over every file in `docs/releases/`, through the skill's tests.
