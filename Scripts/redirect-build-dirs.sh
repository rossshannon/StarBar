#!/usr/bin/env bash
#
# Move each checkout's build/ (Xcode DerivedData, see build.sh's -derivedDataPath)
# into ~/Library/Caches and leave a symlink behind.
#
#   Scripts/redirect-build-dirs.sh              show what would change
#   Scripts/redirect-build-dirs.sh --apply      do it
#   Scripts/redirect-build-dirs.sh --status     just report current state
#
# Why: build/ is 0.4 to 3 GB and tens of thousands of files per checkout,
# rewritten by every build, and every worktree has its own. A backup of the home
# folder spends most of its scanning and uploading on it. Backup tools leave
# ~/Library/Caches out and record a symlink as one entry without following it,
# so the link keeps the build output out of the backup while the source stays
# in. Checked 2026-09-28 with Backblaze: a symlinked folder was one entry in its
# file list, with nothing scanned beneath it. STARBAR_BUILD_CACHE names another
# cache folder.
#
# The move is a rename on the same volume, so it is instant and keeps the
# incremental build. Reverse it by moving the target back over the link.
#
# GOTCHA: `rm -rf build/` with a trailing slash descends through the link and
# empties the real build directory while leaving the link in place. Use
# `trash build` or `rm build`.

set -euo pipefail

CACHE_ROOT="${STARBAR_BUILD_CACHE:-$HOME/Library/Caches/StarBar-build}"
mode="dry-run"

for arg in "$@"; do
    case $arg in
        --apply) mode="apply" ;;
        --status) mode="status" ;;
        --help|-h) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

cd "$(dirname "$0")/.."
repo_root="$(git rev-parse --show-toplevel)"

# One cache directory per checkout: basename plus a hash of the full path, so two
# worktrees with the same branch-ish name can never share a build directory.
cache_dir_for() {
    local checkout="$1" hash
    hash="$(printf '%s' "$checkout" | shasum -a 256 | cut -c1-8)"
    printf '%s/%s-%s' "$CACHE_ROOT" "$(basename "$checkout")" "$hash"
}

checkouts() {
    git -C "$repo_root" worktree list --porcelain | sed -n 's/^worktree //p'
}

redirect() {
    local checkout="$1" build target
    build="$checkout/build"
    target="$(cache_dir_for "$checkout")/build"

    if [ -L "$build" ]; then
        local current
        current="$(readlink "$build")"
        if [ "$current" = "$target" ]; then
            printf '  ok        %s\n' "$checkout"
        else
            printf '  LINKED elsewhere: %s -> %s\n' "$build" "$current"
        fi
        return 0
    fi

    if [ ! -e "$build" ]; then
        printf '  %-8s  %s  (absent; link so future builds land in the cache)\n' "$mode" "$build"
        [ "$mode" = "apply" ] || return 0
        mkdir -p "$target"
        ln -s "$target" "$build"
        printf '  linked    %s -> %s\n' "$build" "$target"
        return 0
    fi

    local size
    size="$(du -sh "$build" | cut -f1)"
    printf '  %-8s  %s  (%s) -> %s\n' "$mode" "$build" "$size" "$target"
    [ "$mode" = "apply" ] || return 0

    if [ -e "$target" ]; then
        echo "  refusing: $target already exists; remove it or move it aside" >&2
        return 1
    fi
    mkdir -p "$(dirname "$target")"
    mv "$build" "$target"
    ln -s "$target" "$build"
    printf '  moved+linked %s\n' "$build"
    return 0
}

echo "cache root: $CACHE_ROOT"
while IFS= read -r checkout; do
    [ -n "$checkout" ] || continue
    if [ "$mode" = "status" ]; then
        if [ -L "$checkout/build" ]; then
            printf '  link      %s -> %s\n' "$checkout/build" "$(readlink "$checkout/build")"
        elif [ -d "$checkout/build" ]; then
            printf '  real      %s  (%s)\n' "$checkout/build" "$(du -sh "$checkout/build" | cut -f1)"
        else
            printf '  none      %s\n' "$checkout/build"
        fi
    else
        redirect "$checkout"
    fi
done < <(checkouts)

if [ "$mode" = "dry-run" ]; then
    echo
    echo "Nothing changed. Re-run with --apply to move these and leave symlinks."
fi
