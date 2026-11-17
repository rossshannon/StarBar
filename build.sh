#!/bin/bash

# Build script for StarBar
#
#   ./build.sh                  Release build into build/ (incremental)
#   ./build.sh --clean          Clean first
#   ./build.sh --install    Also replace /Applications/StarBar.app and launch it
#   ./build.sh --dev        Build StarBar Dev instead, to install beside StarBar (see below)
#   ./build.sh --watch      Rebuild on source changes (combine with --install)
#   ./build.sh --version=1.2.0  Build with this marketing version (the release workflow does)
#   ./build.sh --test           Run the tests that don't need Music
#   ./build.sh --test-all   Also run the tests that talk to Music (needs a track playing)
#   ./build.sh --ui-test    Run the UI tests, which take over the screen (asks first; --yes skips)
#
# StarBar Dev: --dev builds the same code as "StarBar Dev", with its own bundle ID
# (com.rossshannon.starbar.dev), so its own settings and sign-ins, and a blue DEV ribbon on
# its icon, into build/dev/. With --install it goes to /Applications/StarBar Dev.app, beside
# the everyday StarBar rather than over it. The two take turns: installing one quits the
# other, and the app itself quits when the other is opened after it.
#
# Every build but a release records the branch, commit and time it was built from, which the
# About window shows under the version. A release is a build of StarBar at a v* tag with
# nothing uncommitted, which is what the release workflow makes.
#
# Version numbers: the marketing version is --version, else the latest v* tag, else the
# project's own. The build number (CFBundleVersion) is the commit count, so it rises with
# every commit and a newer build always compares higher, which is what LaunchServices and
# any update feed go by. A shallow clone can't count, so it keeps the project's number.
#
# Signing: builds are ad hoc unless STARBAR_CODESIGN_IDENTITY (a "Developer ID Application"
# identity) and STARBAR_TEAM_ID are set, as the release workflow sets them from its secrets.
#
# Last.fm: the app's API key and shared secret for Last.fm's API are not in the repository. A
# build takes LASTFM_API_KEY and LASTFM_SHARED_SECRET from the environment (the release
# workflow sets them from its secrets), else from the lines of those names in an env file:
# the one STARBAR_SECRETS_FILE names, then .env beside this script, then .env in the main
# checkout when this is a git worktree of it, then ~/.config/starbar/secrets.env. A file is
# read, never sourced. A .env that 1Password mounts for an Environment is a named pipe that
# waits for 1Password to be unlocked and the read approved, so it is given up on after
# STARBAR_ENV_WAIT seconds (60 at a terminal, 10 otherwise). Both values reach Xcode
# concealed (LastfmCredentials.conceal) in build/StarBarSecrets.xcconfig, never on a command
# line or in anything printed, because CI logs are public. Without them the build works in
# every other way and can't connect to Last.fm.

set -e
set -o pipefail

cd "$(dirname "$0")"

PROJECT_NAME="StarBar"
STANDARD_APP_NAME="StarBar"
DEV_APP_NAME="StarBar Dev"
# Fewest tests a run may execute before it counts as broken (see xcode_test)
MIN_APP_TESTS=150
MIN_UI_TESTS=5

INSTALL=false
WATCH=false
CLEAN=false
TEST=false
TEST_ALL=false
UI_TEST=false
ASSUME_YES=false
VERSION=""
VARIANT=standard

for arg in "$@"; do
    case $arg in
        --install|-i) INSTALL=true ;;
        --watch|-w) WATCH=true ;;
        --clean) CLEAN=true ;;
        --version=*) VERSION="${arg#*=}"; [ -n "$VERSION" ] || { echo "Error: --version needs a value, such as --version=1.2.0"; exit 2; } ;;
        --test|-t) TEST=true ;;
        --test-all) TEST=true; TEST_ALL=true ;;
        --ui-test) UI_TEST=true ;;
        --yes|-y) ASSUME_YES=true ;;
        --dev) VARIANT=dev ;;
        *) echo "Unknown option: $arg"; exit 2 ;;
    esac
done

if [ -n "$VERSION" ] && ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: --version must look like 1.2.0, not $VERSION"
    exit 2
fi

if { [ "$TEST" = true ] || [ "$UI_TEST" = true ]; } && { [ "$INSTALL" = true ] || [ "$WATCH" = true ]; }; then
    echo "Error: --test and --ui-test run on their own. Don't combine them with --install or --watch."
    exit 2
fi

if [ "$VARIANT" = dev ] && { [ "$TEST" = true ] || [ "$UI_TEST" = true ]; }; then
    echo "Error: the tests always run on StarBar, so --dev doesn't go with --test or --ui-test."
    exit 2
fi

# The project's STARBAR_VARIANT setting picks the product name, bundle ID and icon
if [ "$VARIANT" = dev ]; then
    APP_NAME="$DEV_APP_NAME"
    OTHER_APP_NAME="$STANDARD_APP_NAME"
    # Its own derived data, so going between the two rebuilds neither from scratch
    DERIVED_DATA="build/dev"
else
    APP_NAME="$STANDARD_APP_NAME"
    OTHER_APP_NAME="$DEV_APP_NAME"
    DERIVED_DATA="build"
fi
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

# xcodebuild needs a full Xcode. If xcode-select points at the Command Line
# Tools, fall back to the first Xcode app we can find.
if [ -z "$DEVELOPER_DIR" ] && ! xcodebuild -version > /dev/null 2>&1; then
    XCODE_APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" | head -1)
    if [ -z "$XCODE_APP" ]; then
        echo "Error: no Xcode found. Install Xcode or run xcode-select -s."
        exit 1
    fi
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    echo "Using Xcode at $XCODE_APP"
fi

# Prove the app now running is the build we just made. Prints a verification block and
# returns non-zero if the installed binary differs from the build or the new app isn't running.
verify_install() {
    local built_binary="$APP_PATH/Contents/MacOS/$APP_NAME"
    local installed_binary="$INSTALL_PATH/Contents/MacOS/$APP_NAME"
    local built_hash installed_hash pid="" started version

    built_hash=$(shasum -a 256 "$built_binary" | cut -d' ' -f1)
    installed_hash=$(shasum -a 256 "$installed_binary" | cut -d' ' -f1)

    # open returns before the app starts, so wait up to 10 seconds for the process
    for _ in $(seq 1 20); do
        pid=$(pgrep -f "^$installed_binary" | head -1 || true)
        [ -n "$pid" ] && break
        sleep 0.5
    done

    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null)
    version="$version ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null))"

    echo ""
    echo "=== Install verification ==="
    echo "Commit:     $(git rev-parse --short HEAD 2>/dev/null)$(git diff --quiet 2>/dev/null || echo ' + uncommitted changes')"
    echo "App:        $APP_NAME, $(describe_source "$INSTALL_PATH")"
    echo "Version:    $version"
    echo "Binary:     $(stat -f '%Sm' "$installed_binary")  sha256 ${installed_hash:0:12}"

    if [ "$built_hash" != "$installed_hash" ]; then
        echo "FAILED: the installed binary is not the one just built (build ${built_hash:0:12})"
        return 1
    fi
    if [ -z "$pid" ]; then
        echo "FAILED: $APP_NAME is not running from $INSTALL_PATH"
        return 1
    fi
    started=$(ps -o lstart= -p "$pid")
    echo "Running:    PID $pid, started $started"
    echo "Verified: /Applications has the new build, and it is running."
}

# Last.fm's API key and shared secret: find_lastfm_credentials, prepare_lastfm_credentials and
# redact_build_log, in a file of their own so that Scripts/test-lastfm-credentials.sh can run
# them with made-up values
source Scripts/lastfm-credentials.sh

# xcodebuild settings for the version numbers and signing, appended to BUILD_SETTINGS
BUILD_SETTINGS=()
collect_build_settings() {
    local tag
    # Called before every build, including each watch-mode rebuild
    BUILD_SETTINGS=()
    if [ -n "$VERSION" ]; then
        BUILD_SETTINGS+=("MARKETING_VERSION=$VERSION")
    elif tag=$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null); then
        BUILD_SETTINGS+=("MARKETING_VERSION=${tag#v}")
    else
        echo "Note: no v* tag reachable, so the version stays the project's own"
    fi
    if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "false" ]; then
        BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)")
    else
        echo "Note: shallow or missing git history, so the build number stays the project's own"
    fi
    BUILD_SETTINGS+=("STARBAR_VARIANT=$VARIANT")
    collect_source_settings
    if [ -n "$STARBAR_CODESIGN_IDENTITY" ] && [ -n "$STARBAR_TEAM_ID" ]; then
        BUILD_SETTINGS+=(
            "CODE_SIGN_STYLE=Manual"
            "CODE_SIGN_IDENTITY=$STARBAR_CODESIGN_IDENTITY"
            "DEVELOPMENT_TEAM=$STARBAR_TEAM_ID"
            # Notarisation needs a secure timestamp on the signature
            "OTHER_CODE_SIGN_FLAGS=--timestamp"
        )
        echo "Signing with $STARBAR_CODESIGN_IDENTITY"
    fi
}

# The branch, commit and build time, which the app shows in its About window (BuildInfo),
# for every build but a release: StarBar at a v* tag with no uncommitted changes to tracked
# files. Appends to BUILD_SETTINGS.
collect_source_settings() {
    local commit branch modified=NO
    commit=$(git rev-parse --short HEAD 2>/dev/null) || return 0
    git diff --quiet HEAD -- 2>/dev/null || modified=YES
    if [ "$VARIANT" = standard ] && [ "$modified" = NO ] \
        && git describe --exact-match --tags --match 'v[0-9]*' HEAD > /dev/null 2>&1; then
        return 0
    fi
    branch=$(git symbolic-ref --short -q HEAD || true)
    # A pull request's checkout in GitHub Actions is detached; Actions names its branch
    [ -n "$branch" ] || branch="${GITHUB_HEAD_REF:-}"
    # Only characters Xcode takes as they are: it would expand a $(...) in a branch name
    branch=$(printf '%s' "$branch" | tr -cd 'A-Za-z0-9._/+-')
    [ -z "$branch" ] || BUILD_SETTINGS+=("STARBAR_SOURCE_BRANCH=$branch")
    BUILD_SETTINGS+=(
        "STARBAR_SOURCE_COMMIT=$commit"
        "STARBAR_SOURCE_MODIFIED=$modified"
        "STARBAR_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    )
}

# What an app bundle says it was built from: "release", or "main at 8c978ba" and so on
describe_source() {
    local plist="$1/Contents/Info.plist" branch commit modified
    commit=$(/usr/libexec/PlistBuddy -c "Print :StarBarSourceCommit" "$plist" 2>/dev/null || true)
    if [ -z "$commit" ]; then
        echo "release"
        return
    fi
    branch=$(/usr/libexec/PlistBuddy -c "Print :StarBarSourceBranch" "$plist" 2>/dev/null || true)
    modified=$(/usr/libexec/PlistBuddy -c "Print :StarBarSourceModified" "$plist" 2>/dev/null || true)
    echo "${branch:+$branch at }$commit$([ "$modified" = YES ] && echo ' + uncommitted changes')"
}

build_and_install() {
    echo ""
    echo "=== Building $APP_NAME... ==="

    local actions=(build)
    if [ "$CLEAN" = true ]; then
        actions=(clean build)
    fi
    collect_build_settings
    prepare_lastfm_credentials

    # Capture build output so a failure shows the full log
    BUILD_LOG=$(mktemp)
    if xcodebuild -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$PROJECT_NAME" \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        "${LASTFM_BUILD_ARGS[@]}" \
        "${BUILD_SETTINGS[@]}" \
        "${actions[@]}" > "$BUILD_LOG" 2>&1; then
        redact_build_log "$BUILD_LOG"
        tail -10 "$BUILD_LOG"
        rm -f "$BUILD_LOG"
    else
        redact_build_log "$BUILD_LOG"
        echo "Build failed! Full output:"
        cat "$BUILD_LOG"
        rm -f "$BUILD_LOG"
        return 1
    fi

    if [ ! -d "$APP_PATH" ]; then
        echo "Build failed or app not found"
        return 1
    fi

    echo ""
    echo "Build successful: $APP_NAME version $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")), $(describe_source "$APP_PATH")"

    if [ "$INSTALL" = true ]; then
        if [ -d "$INSTALL_PATH" ] && ! command -v trash &> /dev/null; then
            echo "Error: trash not found, so the existing app can't be moved to the Trash. Install with: brew install trash"
            return 1
        fi
        echo "Installing to /Applications..."
        killall "$APP_NAME" 2>/dev/null || true
        # StarBar and StarBar Dev take turns (VariantHandover in the app). Quitting the other
        # here also covers a StarBar from before that, which doesn't quit by itself.
        if pgrep -xq "$OTHER_APP_NAME"; then
            echo "Quitting $OTHER_APP_NAME: only one of StarBar and StarBar Dev runs at a time"
            killall "$OTHER_APP_NAME" 2>/dev/null || true
        fi
        sleep 0.5
        if [ -d "$INSTALL_PATH" ]; then
            trash "$INSTALL_PATH"
        fi
        cp -R "$APP_PATH" /Applications/
        echo "Launching..."
        open "$INSTALL_PATH"
        verify_install
    else
        echo "App location: $APP_PATH"
        echo "To install, run: ./build.sh$([ "$VARIANT" = dev ] && echo ' --dev') --install"
    fi
}

# Run xcodebuild test with the given scheme, with VAR=value entries for the test host's
# environment. xcodebuild forwards TEST_RUNNER_<VAR> from its own environment to the host,
# so they go through env; passed as arguments they would be build settings and never arrive.
# Usage: xcode_test <name> <scheme> <min_tests> [TEST_RUNNER_VAR=value...]
# Writes build/test/<name>.log and a result bundle under build/test/results/.
# Fails when fewer than <min_tests> tests ran: a test bundle that fails to load, or a scheme
# that no longer includes the tests, would otherwise pass with "Executed 0 tests".
xcode_test() {
    local name="$1"
    local scheme="$2"
    local min_tests="$3"
    shift 3
    local test_dir="build/test"
    local test_log="$test_dir/$name.log"
    # xcodebuild won't overwrite a result bundle, so each run gets its own
    local result_bundle="$test_dir/results/$name-$(date +%Y%m%d-%H%M%S).xcresult"

    mkdir -p "$test_dir/results"
    if env "$@" xcodebuild -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$scheme" \
        -destination "platform=macOS" \
        -derivedDataPath "$test_dir" \
        -resultBundlePath "$result_bundle" \
        test > "$test_log" 2>&1; then
        grep -E "Executed [0-9]+ tests|\*\* TEST" "$test_log" | tail -2
        local executed
        executed=$(grep -E "Executed [0-9]+ tests" "$test_log" | tail -1 | sed -E 's/.*Executed ([0-9]+) tests.*/\1/')
        if [ "${executed:-0}" -lt "$min_tests" ]; then
            echo "Only ${executed:-0} tests ran, but at least $min_tests were expected. Full log: $test_log"
            return 1
        fi
    else
        # Failed tests first, then the end of the log, which explains crashes and build errors
        grep -E ": error:|Test Case .* failed" "$test_log" || true
        echo "--- last 40 lines of $test_log ---"
        tail -40 "$test_log"
        echo "Tests failed. Full log: $test_log"
        echo "Results: $result_bundle"
        return 1
    fi
}

run_tests() {
    # The UI tests take over the screen, so they have their own scheme and run only with --ui-test.
    # ScriptBridgeTests reads from Music, so it skips itself unless the test host sees
    # STARBAR_LIVE_MUSIC_TESTS=1 (xcodebuild forwards TEST_RUNNER_ variables from its
    # environment). It needs Music playing a track with artwork. CI has no Music.
    local extra=()
    if [ "$TEST_ALL" = true ]; then
        extra+=("TEST_RUNNER_STARBAR_LIVE_MUSIC_TESTS=1")
    fi
    local status=0

    # First, since it takes seconds: how a build finds the Last.fm key and secret and keeps them
    # out of its log, with made-up values, under the bash this script itself runs in
    echo ""
    echo "=== Checking the build's Last.fm credentials... ==="
    /bin/bash Scripts/test-lastfm-credentials.sh || status=1

    echo ""
    echo "=== Testing $APP_NAME... ==="
    # The app hosts the unit tests, so a test run launches it
    xcode_test test "$PROJECT_NAME" "$MIN_APP_TESTS" "${extra[@]}" || status=1

    return $status
}

run_ui_tests() {
    echo ""
    echo "=== UI testing $APP_NAME... ==="
    echo "These tests take over the mouse and screen for about two minutes, clicking and dragging"
    echo "the menu bar. macOS may ask you to authenticate first."

    # Only run on request: ask first, except in CI or with --yes
    if [ -z "$CI" ] && [ "$ASSUME_YES" = false ]; then
        if [ ! -t 0 ]; then
            echo "Error: --ui-test takes over the screen, so it needs confirmation. Run it in a terminal, or pass --yes."
            return 2
        fi
        # read fails at end of input (Ctrl-D); without the || the script would exit silently
        if ! read -r -p "Take over the screen now? [y/N] " answer; then
            echo ""
            echo "UI tests not run."
            return 2
        fi
        case "$answer" in
            [yY]|[yY][eE][sS]) ;;
            *) echo "UI tests not run."; return 2 ;;
        esac
    fi

    # The test build has the same bundle ID as the installed app, and StarBar Dev follows
    # Music as well, so quit whichever installed copy is running while the tests run, then
    # reopen it
    local name reopen=()
    for name in "$STANDARD_APP_NAME" "$DEV_APP_NAME"; do
        if pgrep -xq "$name"; then
            reopen+=("/Applications/$name.app")
            killall "$name" 2>/dev/null || true
        fi
    done
    [ ${#reopen[@]} -eq 0 ] || sleep 0.5

    local status=0
    xcode_test ui-test "$PROJECT_NAME UI Tests" "$MIN_UI_TESTS" || status=1

    local app
    for app in "${reopen[@]}"; do
        [ -d "$app" ] && open "$app"
    done
    return $status
}

if [ "$UI_TEST" = true ]; then
    run_ui_tests
elif [ "$TEST" = true ]; then
    run_tests
elif [ "$WATCH" = true ]; then
    if ! command -v fswatch &> /dev/null; then
        echo "Error: fswatch not found. Install with: brew install fswatch"
        exit 1
    fi

    echo "Watching: StarBar/ and StarBar.xcodeproj/project.pbxproj"
    echo "Press Ctrl+C to stop"

    build_and_install || true

    fswatch -o -e "build/" -e ".git/" \
        --include="\.swift$" \
        --include="\.xcassets" \
        --include="\.plist$" \
        --include="\.xib$" \
        --include="\.storyboard$" \
        --include="\.entitlements$" \
        --include="\.strings$" \
        --include="project\.pbxproj$" \
        -r "StarBar/" "StarBar.xcodeproj/project.pbxproj" | while read -r; do
        echo ""
        echo "Change detected, rebuilding..."
        build_and_install || true
    done
else
    build_and_install
fi
