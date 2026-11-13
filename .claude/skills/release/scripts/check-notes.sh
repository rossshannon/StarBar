#!/bin/bash
# Check a release's notes before they are published.
#
#   check-notes.sh <version> [--file <path>] [--previous <tag>] [--commit <rev>]
#
#   <version>    three numbers, such as 1.11.0
#   --file       the notes to check (default: docs/releases/v<version>.md in this checkout)
#   --previous   the release before this one (default: the highest v* tag below <version>)
#   --commit     the commit being released (default: HEAD). Used for one rule: a release
#                that changes the entitlements or the privacy policy must say so
#
# Prints every problem it finds and exits 1 if there were any, 2 for a wrong call.
# The rules and the reason for each are in ../references/notes-style.md.
#
# Written for the bash 3.2 and BSD tools that macOS ships.
set -euo pipefail

usage() {
  echo "usage: check-notes.sh <version> [--file <path>] [--previous <tag>] [--commit <rev>]" >&2
}

VERSION=""
FILE=""
PREVIOUS=""
COMMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)     [ $# -ge 2 ] || { usage; exit 2; }; FILE="$2"; shift 2 ;;
    --previous) [ $# -ge 2 ] || { usage; exit 2; }; PREVIOUS="$2"; shift 2 ;;
    --commit)   [ $# -ge 2 ] || { usage; exit 2; }; COMMIT="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "check-notes: unknown option $1" >&2; usage; exit 2 ;;
    *)          [ -z "$VERSION" ] || { usage; exit 2; }; VERSION="$1"; shift ;;
  esac
done

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
if ! [[ "$VERSION" =~ $VERSION_RE ]]; then
  echo "check-notes: the version must be three numbers such as 1.11.0, not '$VERSION'" >&2
  usage
  exit 2
fi
TAG="v$VERSION"

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

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)

if [ -z "$FILE" ]; then
  [ -n "$ROOT" ] || { echo "check-notes: not in a git checkout, so pass --file" >&2; exit 2; }
  FILE="$ROOT/docs/releases/$TAG.md"
fi
if [ ! -s "$FILE" ]; then
  echo "check-notes: there are no notes at $FILE"
  exit 1
fi

# The release before this one: the highest v* tag below this version. A checkout without
# tags (CI's, for one) has none, and the rules that need it then check less.
if [ -z "$PREVIOUS" ] && [ -n "$ROOT" ]; then
  while read -r candidate; do
    [[ "${candidate#v}" =~ $VERSION_RE ]] || continue
    version_lt "${candidate#v}" "$VERSION" || continue
    if [ -z "$PREVIOUS" ] || version_lt "${PREVIOUS#v}" "${candidate#v}"; then
      PREVIOUS="$candidate"
    fi
  done <<EOF
$(git tag -l 'v[0-9]*')
EOF
fi
if [ -n "$PREVIOUS" ] && ! [[ "${PREVIOUS#v}" =~ $VERSION_RE ]]; then
  echo "check-notes: --previous must be a tag such as v1.10.0, not '$PREVIOUS'" >&2
  exit 2
fi

PROBLEMS=0
problem() {
  PROBLEMS=$((PROBLEMS + 1))
  echo "  - $*"
}

echo "Checking $FILE for StarBar $VERSION"

if grep -q $'\r' "$FILE"; then
  problem "the file has Windows line endings; save it with plain newlines"
fi

# 1. The title, which becomes the GitHub release's title and the tag's message
LINE1=$(sed -n '1p' "$FILE")
LINE2=$(sed -n '2p' "$FILE")
LINE3=$(sed -n '3p' "$FILE")
TITLE_OK=1
case "$LINE1" in
  "# StarBar $VERSION") ;;
  "# StarBar $VERSION — "?*)
    case "$LINE1" in *.) problem "line 1: the title ends with a full stop; titles have none" ;; esac
    ;;
  *) TITLE_OK=0 ;;
esac
if [ "$TITLE_OK" -eq 0 ]; then
  problem "line 1 must be '# StarBar $VERSION — <the release in a few words>', with an em dash, or '# StarBar $VERSION' alone for a patch release. It is: $LINE1"
fi
[ -z "$LINE2" ] || problem "line 2 must be blank, between the title and the first sentence"

# 2. The opening sentence
case "$LINE3" in
  "StarBar $VERSION "*) ;;
  *) problem "line 3 must open the notes with 'StarBar $VERSION ...', one or two sentences on what the release is" ;;
esac

# 3. No second title: everything under line 1 is pasted into the release as its body
if awk 'NR > 1 && /^# / { found = 1 } END { exit !found }' "$FILE"; then
  problem "only line 1 may be a '# ' heading; sections are '## '"
fi

# 4. The recommended-release line
RECOMMENDED=$(grep -c '^\*\*This is the recommended release\. Requires macOS [0-9][0-9]* or later.*\.\*\*$' "$FILE" || true)
if [ "$RECOMMENDED" -ne 1 ]; then
  problem "one line must read '**This is the recommended release. Requires macOS 13 or later, and Music or Spotify.**' (found $RECOMMENDED)"
fi

# 5. Installation is there, once, and is the last section
INSTALL=$(grep -c '^## Installation$' "$FILE" || true)
if [ "$INSTALL" -ne 1 ]; then
  problem "there must be one '## Installation' section (found $INSTALL)"
elif [ "$(grep '^## ' "$FILE" | tail -1)" != "## Installation" ]; then
  problem "'## Installation' must be the last section"
fi

# 6. The notes end with the link to what changed since the release before
LAST=$(grep -v '^[[:space:]]*$' "$FILE" | tail -1)
LINK_RE='^\[Changes since ([0-9]+\.[0-9]+\.[0-9]+)\]\(https://github\.com/[^/ ]+/[^/ ]+/compare/v([0-9]+\.[0-9]+\.[0-9]+)\.\.\.v([0-9]+\.[0-9]+\.[0-9]+)\)\.$'
if [[ "$LAST" =~ $LINK_RE ]]; then
  SINCE="${BASH_REMATCH[1]}"
  FROM="${BASH_REMATCH[2]}"
  TO="${BASH_REMATCH[3]}"
  if [ "$TO" != "$VERSION" ]; then
    problem "the last line compares up to v$TO, not v$VERSION"
  fi
  if [ "$SINCE" != "$FROM" ]; then
    problem "the last line says 'Changes since $SINCE' but compares from v$FROM"
  fi
  if [ -n "$PREVIOUS" ]; then
    if [ "v$FROM" != "$PREVIOUS" ]; then
      problem "the last line compares from v$FROM, but the release before this one is $PREVIOUS"
    fi
  elif ! version_lt "$FROM" "$VERSION"; then
    problem "the last line compares from v$FROM, which is not before v$VERSION"
  fi
else
  problem "the last line must be '[Changes since A.B.C](https://github.com/<owner>/<repo>/compare/vA.B.C...v$VERSION).'"
fi

# 7. Nothing left over from drafting. publish.sh adds the Source and Package lines itself,
#    from the commit it tags and the build the workflow made
LEFTOVER=$(grep -n -E 'MERGE_COMMIT|BUILD_NUMBER|^\*\*Source:\*\*|^\*\*Package:\*\*|TODO|TBD|FIXME|<!--' "$FILE" || true)
if [ -n "$LEFTOVER" ]; then
  while IFS= read -r line; do
    problem "line ${line%%:*} has a placeholder or a Source/Package line, which publish.sh writes: ${line#*:}"
  done <<EOF
$LEFTOVER
EOF
fi

# 8. A release that changes what the app may do, or what the policy says, tells the user.
#    Without --commit the comparison is with the working tree, so an edit not yet
#    committed counts
WATCHED_ONE="StarBar/StarBar.entitlements"
WATCHED_TWO="Privacy Policy.md"
if [ -n "$ROOT" ] && [ -n "$PREVIOUS" ] \
  && git rev-parse -q --verify "$PREVIOUS^{commit}" >/dev/null 2>&1 \
  && { [ -z "$COMMIT" ] || git rev-parse -q --verify "$COMMIT^{commit}" >/dev/null 2>&1; }; then
  if [ -n "$COMMIT" ]; then
    CHANGED=$(git -C "$ROOT" diff --name-only "$PREVIOUS" "$COMMIT" -- "$WATCHED_ONE" "$WATCHED_TWO" 2>/dev/null || echo "?")
  else
    CHANGED=$(git -C "$ROOT" diff --name-only "$PREVIOUS" -- "$WATCHED_ONE" "$WATCHED_TWO" 2>/dev/null || echo "?")
  fi
  if [ "$CHANGED" = "?" ]; then
    echo "  note: could not compare with $PREVIOUS, so the entitlements and privacy policy rule was not checked"
  elif [ -n "$CHANGED" ] && ! grep -q -E '^## (Network access|Privacy)' "$FILE"; then
    problem "$(echo "$CHANGED" | tr '\n' ',' | sed 's/,$//; s/,/ and /') changed since $PREVIOUS, so the notes need a '## Network access' or '## Privacy' section saying what changed for the user"
  fi
else
  echo "  note: no earlier release to compare with in this checkout, so the entitlements and privacy policy rule was not checked"
fi

if [ "$PROBLEMS" -gt 0 ]; then
  echo "check-notes: $PROBLEMS problem(s) in $FILE"
  exit 1
fi
if [ -n "$PREVIOUS" ]; then
  echo "check-notes: ready (the release before is $PREVIOUS)"
else
  echo "check-notes: ready"
fi
