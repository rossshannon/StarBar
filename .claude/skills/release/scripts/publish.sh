#!/bin/bash
# Publish a StarBar release: tag the release commit, wait for the Release workflow to build
# and publish it, then put the hand-written title and notes on the GitHub release.
#
#   publish.sh <version> <commit> [--dry-run] [--retag]
#
#   <version>   three numbers, such as 1.11.0
#   <commit>    the full SHA of the release commit, which must be the tip of origin/main
#   --dry-run   run every check, then stop before tagging. Changes nothing anywhere
#   --retag     move a tag whose workflow run failed before it published anything, once a
#               fix has merged. Refused when the tag has a release: a published tag never moves
#
# Run it as it stands in the release commit, from any full checkout of the repository:
#
#   git fetch origin main --tags
#   bash <(git show <commit>:.claude/skills/release/scripts/publish.sh) <version> <commit>
#
# The notes (docs/releases/v<version>.md) and their checker are read from <commit> with
# git show, so the checkout's own branch and any uncommitted work are neither used nor
# touched. Run again after a stop, it carries on: a tag already on <commit> is not pushed
# twice, and a release that already has its notes is only checked.
#
# Needs git and gh, signed in with push access. Written for the bash 3.2 and BSD tools
# that macOS ships.
set -euo pipefail
export GH_PAGER=cat          # a final `gh release view` once sat in the pager
export GH_PROMPT_DISABLED=1

NOTES_DIR="docs/releases"
CHECKER=".claude/skills/release/scripts/check-notes.sh"
RELEASE_WORKFLOW="release.yml"
TEST_WORKFLOW="test.yml"
# How long to look for the workflow run after the tag is pushed (tests shorten these)
POLL_SECONDS="${STARBAR_RELEASE_POLL_SECONDS:-5}"
POLL_TRIES="${STARBAR_RELEASE_POLL_TRIES:-60}"

usage() {
  echo "usage: publish.sh <version> <commit> [--dry-run] [--retag]" >&2
}

# What a stop has to tell the person: whether anything outside this Mac has changed yet
STATE="Nothing has been changed."
step() { echo; echo "== $*"; }
stop() {
  echo >&2
  echo "STOPPED: $*" >&2
  echo "$STATE" >&2
  exit 1
}

VERSION=""
SHA=""
DRY_RUN=0
RETAG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --retag)   RETAG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        echo "publish: unknown option $1" >&2; usage; exit 2 ;;
    *)
      if [ -z "$VERSION" ]; then VERSION="$1"
      elif [ -z "$SHA" ]; then SHA="$1"
      else usage; exit 2
      fi
      shift ;;
  esac
done

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
SHA_RE='^[0-9a-f]{40}$'
if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "publish: the version must be three numbers such as 1.11.0, not '$VERSION'" >&2
  usage
  exit 2
fi
if ! [[ "$SHA" =~ $SHA_RE ]]; then
  echo "publish: the commit must be a full 40-character SHA, not '$SHA'" >&2
  usage
  exit 2
fi
TAG="v$VERSION"
SHORT="${SHA:0:7}"

# version_lt A B: true when A is a lower version than B
version_lt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<EOF
$1
EOF
  IFS=. read -r b1 b2 b3 <<EOF
$2
EOF
  [ $((10#$a1)) -ne $((10#$b1)) ] && { [ $((10#$a1)) -lt $((10#$b1)) ]; return; }
  [ $((10#$a2)) -ne $((10#$b2)) ] && { [ $((10#$a2)) -lt $((10#$b2)) ]; return; }
  [ $((10#$a3)) -lt $((10#$b3)) ]
}

# ---------------------------------------------------------------------------------------
step "Checking this Mac can publish"

git rev-parse --show-toplevel >/dev/null 2>&1 || stop "run this inside a checkout of the StarBar repository."
[ "$(git rev-parse --is-shallow-repository)" = "false" ] \
  || stop "this checkout is shallow, so the build number can't be counted. Use a full clone."
command -v gh >/dev/null 2>&1 || stop "gh is not installed (brew install gh)."
ORIGIN=$(git remote get-url origin 2>/dev/null) || stop "this checkout has no remote called origin."
SLUG="${STARBAR_RELEASE_REPO:-}"
if [ -z "$SLUG" ]; then
  TRIMMED="${ORIGIN%/}"
  TRIMMED="${TRIMMED%.git}"
  SLUG=$(sed -E -n 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' <<<"$TRIMMED")
fi
[ -n "$SLUG" ] || stop "origin is $ORIGIN, which doesn't look like a GitHub repository."
# Every gh call below goes to origin's repository, never to a fork's parent
export GH_REPO="$SLUG"
gh auth status >/dev/null 2>&1 || stop "gh is not signed in (gh auth login)."
echo "Repository $SLUG, release $TAG from $SHORT."

# ---------------------------------------------------------------------------------------
step "Checking the release commit"

git fetch -q origin main --tags || stop "the fetch from origin failed (see above)."
git cat-file -e "$SHA^{commit}" 2>/dev/null || stop "there is no commit $SHA, even after a fetch."
MAIN=$(git rev-parse origin/main)
[ "$MAIN" = "$SHA" ] || stop "origin/main is at ${MAIN:0:7}, not $SHORT. Something merged after this release was prepared, so this command is out of date: ask for one with the new commit."

PREVIOUS=""
HIGHER=""
while read -r candidate; do
  [[ "${candidate#v}" =~ $VERSION_RE ]] || continue
  [ "$candidate" != "$TAG" ] || continue
  if version_lt "${candidate#v}" "$VERSION"; then
    if [ -z "$PREVIOUS" ] || version_lt "${PREVIOUS#v}" "${candidate#v}"; then
      PREVIOUS="$candidate"
    fi
  else
    HIGHER="$candidate"
  fi
done <<EOF
$(git tag -l 'v[0-9]*')
EOF
[ -z "$HIGHER" ] || stop "$HIGHER already exists and $VERSION is not above it. Release versions only go up."
[ -n "$PREVIOUS" ] || stop "there is no earlier v* tag to follow."
git merge-base --is-ancestor "$PREVIOUS" "$SHA" || stop "$SHORT does not contain $PREVIOUS, the release before it."
COMMIT_COUNT=$(git rev-list --count "$SHA")
echo "origin/main is $SHORT, commit number $COMMIT_COUNT, and it follows $PREVIOUS."

# ---------------------------------------------------------------------------------------
step "Checking the notes in $SHORT"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/starbar-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
git show "$SHA:$NOTES_DIR/$TAG.md" > "$WORK/notes.md" 2>/dev/null \
  || stop "there is no $NOTES_DIR/$TAG.md in $SHORT. The notes are merged before the release is cut."
git show "$SHA:$CHECKER" > "$WORK/check-notes.sh" 2>/dev/null \
  || stop "there is no $CHECKER in $SHORT."
bash "$WORK/check-notes.sh" "$VERSION" --file "$WORK/notes.md" --previous "$PREVIOUS" --commit "$SHA" \
  || stop "the notes in $SHORT don't pass. Fix them in a pull request and start again from its merge commit."

# Line 1 of the notes is the release's title; the rest is its body
TITLE=$(sed -n '1s/^# //p' "$WORK/notes.md")
TAG_MESSAGE="${TITLE/ — /: }"
sed '1,2d' "$WORK/notes.md" \
  | awk '{ line[NR] = $0 } END { n = NR; while (n > 0 && line[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print line[i] }' \
  > "$WORK/body.md"
echo "Title: $TITLE"

# ---------------------------------------------------------------------------------------
step "Checking the tests passed on $SHORT"

# The run for the push to main, as "id status conclusion", newest first
test_runs() {
  gh run list --workflow "$TEST_WORKFLOW" --commit "$SHA" --event push --limit 20 \
    --json databaseId,status,conclusion -q '.[] | "\(.databaseId) \(.status) \(.conclusion)"'
}
RUNS=$(test_runs) || stop "couldn't list the test runs (see above)."
[ -n "$RUNS" ] || stop "no Tests run is recorded for $SHORT on main. Wait for it to start, or start one from the Actions page, then run this again."
if ! grep -q ' completed success$' <<<"$RUNS"; then
  WAITING=$(grep -v ' completed ' <<<"$RUNS" | sed -n '1s/ .*//p' || true)
  if [ -n "$WAITING" ]; then
    echo "The tests are still running (run $WAITING). Waiting for them."
    gh run watch "$WAITING" --exit-status \
      || stop "the tests failed on $SHORT: https://github.com/$SLUG/actions/runs/$WAITING"
  else
    FAILED=$(sed -n '1s/ .*//p' <<<"$RUNS")
    stop "the tests did not pass on $SHORT: https://github.com/$SLUG/actions/runs/$FAILED. If it was a flaky job, rerun it there and run this again; otherwise merge a fix and ask for a new command."
  fi
fi
echo "The tests passed."

# ---------------------------------------------------------------------------------------
step "Looking for $TAG"

# Where the tag points on GitHub: the peeled line for an annotated tag, the tag's own otherwise
REMOTE_AT=$(git ls-remote origin "refs/tags/$TAG^{}" | cut -f1)
[ -n "$REMOTE_AT" ] || REMOTE_AT=$(git ls-remote origin "refs/tags/$TAG" | cut -f1)
LOCAL_AT=$(git rev-parse -q --verify "refs/tags/$TAG^{commit}" 2>/dev/null || true)
HAS_RELEASE=0
gh release view "$TAG" --json tagName >/dev/null 2>&1 && HAS_RELEASE=1

NEEDS_TAG=1
NEEDS_PUSH=1
DELETE_REMOTE=0
if [ -n "$REMOTE_AT" ] && [ "$REMOTE_AT" = "$SHA" ]; then
  echo "$TAG is already on $SHORT on GitHub, so it won't be pushed again."
  NEEDS_TAG=0
  NEEDS_PUSH=0
elif [ -n "$REMOTE_AT" ]; then
  [ "$HAS_RELEASE" -eq 0 ] || stop "$TAG is on ${REMOTE_AT:0:7} and has a release. A published tag never moves: what's wrong with it is fixed in the next patch version."
  [ "$RETAG" -eq 1 ] || stop "$TAG is already on ${REMOTE_AT:0:7}, a different commit, with no release. If its workflow run failed and a fix has merged since, run this again with --retag added."
  # A run still going for the old commit would publish that commit's build under the moved tag
  UNFINISHED=$(gh run list --workflow "$RELEASE_WORKFLOW" --branch "$TAG" --limit 20 \
    --json databaseId,status -q '.[] | select(.status != "completed") | .databaseId' | tr '\n' ' ') \
    || stop "couldn't list the Release runs (see above)."
  UNFINISHED="${UNFINISHED% }"
  [ -z "$UNFINISHED" ] || stop "a Release run for the old $TAG is still going (run $UNFINISHED). Wait for it to end or cancel it (gh run cancel $UNFINISHED), then run this again."
  echo "$TAG is on ${REMOTE_AT:0:7} with no release; --retag will move it to $SHORT."
  DELETE_REMOTE=1
elif [ -n "$LOCAL_AT" ] && [ "$LOCAL_AT" = "$SHA" ]; then
  echo "$TAG is on $SHORT here but not on GitHub yet, so it only needs pushing."
  NEEDS_TAG=0
elif [ -n "$LOCAL_AT" ]; then
  [ "$RETAG" -eq 1 ] || stop "this checkout has a $TAG on ${LOCAL_AT:0:7} that was never pushed. Delete it (git tag -d $TAG) or run this again with --retag added."
  echo "This checkout's $TAG, on ${LOCAL_AT:0:7}, was never pushed; --retag will replace it."
else
  echo "$TAG doesn't exist yet."
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "=== Dry run: everything checks out ==="
  echo "Would tag:   $TAG on $SHORT (\"$TAG_MESSAGE\")"
  echo "Would wait:  for the Release workflow to publish StarBar-$TAG.zip"
  echo "Would set:   the release's title to \"$TITLE\" and its notes to $NOTES_DIR/$TAG.md"
  echo "Nothing has been changed."
  exit 0
fi

# ---------------------------------------------------------------------------------------
if [ "$NEEDS_PUSH" -eq 1 ]; then
  step "Tagging $SHORT as $TAG"
  if [ "$DELETE_REMOTE" -eq 1 ]; then
    git push origin ":refs/tags/$TAG" || stop "couldn't remove the old $TAG from GitHub (see above)."
    STATE="The old $TAG has been removed from GitHub and the new one is not pushed yet. Running the same command again carries on."
  fi
  if [ "$NEEDS_TAG" -eq 1 ]; then
    [ -z "$LOCAL_AT" ] || git tag -d "$TAG" >/dev/null
    git tag -a "$TAG" "$SHA" -m "$TAG_MESSAGE"
  fi
  git push origin "refs/tags/$TAG" || stop "the tag push failed (see above)."
  echo "Pushed $TAG."
fi
STATE="$TAG is on GitHub. Running the same command again carries on from here."

# ---------------------------------------------------------------------------------------
step "Waiting for the Release workflow"

# The run for this tag at this commit: not the newest run, which for a few seconds can
# still be the last release's, and not a moved tag's earlier run
RUN=""
tries=0
while [ "$tries" -lt "$POLL_TRIES" ]; do
  LISTED=$(gh run list --workflow "$RELEASE_WORKFLOW" --branch "$TAG" --limit 5 \
    --json databaseId,headSha -q '.[] | "\(.databaseId) \(.headSha)"' || true)
  RUN=$(grep " $SHA\$" <<<"$LISTED" | sed -n '1s/ .*//p' || true)
  [ -z "$RUN" ] || break
  tries=$((tries + 1))
  sleep "$POLL_SECONDS"
done
[ -n "$RUN" ] || stop "no Release run for $TAG has appeared. Look at https://github.com/$SLUG/actions, then run this again."
echo "Run $RUN: https://github.com/$SLUG/actions/runs/$RUN"
gh run watch "$RUN" --exit-status \
  || stop "the Release run failed: https://github.com/$SLUG/actions/runs/$RUN. If a job was flaky, rerun it there (gh run rerun $RUN --failed) and run this again. If the code needs a fix, merge it and ask for a new command, which will end in --retag."

# ---------------------------------------------------------------------------------------
step "Putting the notes on the release"

BODY=$(gh release view "$TAG" --json body -q .body) \
  || stop "the workflow finished but there is no release for $TAG. Look at the run's last step."
# The workflow's own body starts "Build 461. Signed ..."; a release that already has its
# notes says it in the Package line
BUILD=$(sed -n 's/^Build \([0-9][0-9]*\)\..*/\1/p' <<<"$BODY" | sed -n '1p')
[ -n "$BUILD" ] || BUILD=$(sed -n 's/^\*\*Package:\*\* version .*, build \([0-9][0-9]*\)\..*/\1/p' <<<"$BODY" | sed -n '1p')
WARNINGS=0
warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "LOOK AT THIS: $*"
}
if [ -z "$BUILD" ]; then
  BUILD="$COMMIT_COUNT"
  warn "the release didn't say which build it holds, so the notes say $BUILD, the commit count. Check it against the app's About window."
elif [ "$BUILD" != "$COMMIT_COUNT" ]; then
  warn "the workflow built number $BUILD, but $SHORT is commit number $COMMIT_COUNT. The notes say $BUILD."
fi
case "$BODY" in
  *"Signed with Developer ID"*)
    if grep -q -i 'signed ad hoc' "$WORK/body.md"; then
      warn "this build is signed with Developer ID and notarised, but the notes' Installation section says it is signed ad hoc. Edit that paragraph on the release page, and in $NOTES_DIR/$TAG.md."
    fi ;;
esac

{
  cat "$WORK/body.md"
  # shellcheck disable=SC2016  # the backticks are Markdown
  printf '\n**Source:** `%s`.\n\n**Package:** version %s, build %s.\n' "$SHORT" "$VERSION" "$BUILD"
} > "$WORK/release.md"
gh release edit "$TAG" --title "$TITLE" --notes-file "$WORK/release.md" >/dev/null \
  || stop "couldn't set the title and notes (see above). The release is public with the workflow's own one-line notes."
STATE="$TAG is published with its notes."

# ---------------------------------------------------------------------------------------
step "Checking what GitHub now shows"

NAME=$(gh release view "$TAG" --json name -q .name)
URL=$(gh release view "$TAG" --json url -q .url)
SHOWN=$(gh release view "$TAG" --json body -q .body | tr -d '\r')
ASSETS=$(gh release view "$TAG" --json assets -q '.assets[].name')
LATEST=$(gh release list --limit 10 --json tagName,isLatest -q '.[] | select(.isLatest) | .tagName')
CHECKSUM=$(gh release download "$TAG" --pattern "StarBar-$TAG.zip.sha256" --output - 2>/dev/null | cut -d' ' -f1 || true)

[ "$NAME" = "$TITLE" ] || warn "the release's title is \"$NAME\", not \"$TITLE\"."
[ "$SHOWN" = "$(cat "$WORK/release.md")" ] || warn "the release's notes are not what was sent."
for asset in "StarBar-$TAG.zip" "StarBar-$TAG.zip.sha256"; do
  grep -q -x -F "$asset" <<<"$ASSETS" || warn "the release has no $asset."
done
[ "$LATEST" = "$TAG" ] || warn "GitHub marks ${LATEST:-nothing} as the latest release, not $TAG (gh release edit $TAG --latest)."
[ -n "$CHECKSUM" ] || warn "couldn't read the zip's checksum file."

echo
if [ "$WARNINGS" -eq 0 ]; then
  echo "=== Published ==="
else
  echo "=== Published, with $WARNINGS thing(s) to look at, above ==="
fi
echo "Release:  $URL"
echo "Title:    $NAME"
echo "Source:   $SHORT, build $BUILD"
echo "Assets:   $(printf '%s\n' "$ASSETS" | tr '\n' ' ')"
echo "SHA-256:  ${CHECKSUM:-unknown}"
echo "Latest:   ${LATEST:-none}"
echo
echo "Paste this block back into the conversation that gave you the command."
[ "$WARNINGS" -eq 0 ] || exit 1
