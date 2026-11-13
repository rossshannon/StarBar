#!/bin/bash

# Build script for StarBar
#
#   ./build.sh                  Release build into build/ (incremental)
#   ./build.sh --clean          Clean first
#   ./build.sh --install    Also replace /Applications/StarBar.app and launch it
#   ./build.sh --watch      Rebuild on source changes (combine with --install)
#   ./build.sh --version=1.2.0  Build with this marketing version (the release workflow does)
#   ./build.sh --test           Run the tests that don't need Music
#   ./build.sh --test-all   Also run the tests that talk to Music (needs a track playing)
#   ./build.sh --ui-test    Run the UI tests, which take over the screen (asks first; --yes skips)
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
APP_NAME="StarBar"
APP_PATH="build/Build/Products/Release/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
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

# Last.fm's API key and shared secret from the environment, kept in shell variables that aren't
# exported, so neither xcodebuild nor anything else this script starts inherits them
LASTFM_KEY_FROM_ENV="${LASTFM_API_KEY:-}"
LASTFM_SECRET_FROM_ENV="${LASTFM_SHARED_SECRET:-}"
unset LASTFM_API_KEY LASTFM_SHARED_SECRET
# The same bytes as LastfmCredentials.pad in StarBar/Lastfm/LastfmCredentials.swift
LASTFM_PAD=(0x53 0x74 0x61 0x72 0x42 0x61 0x72 0x2A 0x4C 0x61 0x73 0x74 0x2E 0x66 0x6D 0x21)
LASTFM_XCCONFIG="build/StarBarSecrets.xcconfig"
# Set by find_lastfm_credentials
LASTFM_KEY=""
LASTFM_SECRET=""
# Set by prepare_lastfm_credentials before each build
LASTFM_BUILD_ARGS=()
LASTFM_CONCEALED_KEY=""
LASTFM_CONCEALED_SECRET=""

# Sets ENV_VALUE to an env file's value as written after the "=": whitespace trimmed, then one
# pair of matching quotes taken off, then whitespace inside them. Everything that touches the
# key or the secret uses shell builtins only, so neither appears on a command line, where other
# processes could read it.
tidy_env_value() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    ENV_VALUE="$value"
}

# Reads an env file's lines on standard input and sets LASTFM_KEY and LASTFM_SECRET from its
# LASTFM_API_KEY= and LASTFM_SHARED_SECRET= lines, each only when it isn't set already. The
# lines are read, never run.
take_lastfm_lines() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line#export }"
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            LASTFM_API_KEY=*)
                if [ -z "$LASTFM_KEY" ]; then
                    tidy_env_value "${line#LASTFM_API_KEY=}"
                    LASTFM_KEY="$ENV_VALUE"
                fi ;;
            LASTFM_SHARED_SECRET=*)
                if [ -z "$LASTFM_SECRET" ]; then
                    tidy_env_value "${line#LASTFM_SHARED_SECRET=}"
                    LASTFM_SECRET="$ENV_VALUE"
                fi ;;
        esac
    done
    ENV_VALUE=""
}

# Reads a named pipe as an env file, giving up after a while. 1Password mounts an Environment's
# local .env file as one: opening it waits until 1Password is unlocked and the read approved,
# which nobody can do for a build nobody is watching. So a helper opens the file and copies its
# lines into a pipe of this script's own, where a read can time out, and what it read stays in
# memory.
read_lastfm_env_pipe() {
    local file="$1" limit="${STARBAR_ENV_WAIT:-}" relay reader line
    local started=$SECONDS had_key="$LASTFM_KEY" had_secret="$LASTFM_SECRET"
    if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -lt 1 ]; then
        # Someone at a terminal can answer 1Password's prompt; nobody can otherwise
        if [ -t 0 ] || [ -t 1 ]; then limit=60; else limit=10; fi
    fi
    relay=$(mktemp -u "${TMPDIR:-/tmp}/starbar-env.XXXXXX") || return 0
    mkfifo -m 600 "$relay" || return 0
    echo "Last.fm: reading $file, which 1Password has to release (waiting up to $limit s; approve its prompt if it asks)"
    ( exec 3> "$relay"
      while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >&3; done < "$file"
    ) 2> /dev/null &
    reader=$!
    # Opens once the helper has the other end, which it takes before it touches the file
    exec 4< "$relay"
    rm -f "$relay"
    take_lastfm_lines < <(
        if IFS= read -r -t "$limit" -u 4 line; then
            printf '%s\n' "$line"
            while IFS= read -r -t 5 -u 4 line || [ -n "$line" ]; do printf '%s\n' "$line"; done
        fi
    )
    exec 4<&-
    # The helper has finished unless the file never opened. Either way it isn't left behind.
    kill "$reader" 2> /dev/null || true
    wait "$reader" 2> /dev/null || true
    if [ "$LASTFM_KEY" = "$had_key" ] && [ "$LASTFM_SECRET" = "$had_secret" ] && [ $((SECONDS - started)) -ge "$limit" ]; then
        echo "Note: nothing for Last.fm came from $file within $limit s (is 1Password locked?)"
    fi
}

# Reads one env file, if there is one, into LASTFM_KEY and LASTFM_SECRET
read_lastfm_env_file() {
    local file="$1"
    if [ -p "$file" ]; then
        read_lastfm_env_pipe "$file"
    elif [ -f "$file" ] && [ -r "$file" ]; then
        take_lastfm_lines < "$file"
    fi
}

# Prints the main checkout's folder when this one is a git worktree of it, else nothing
main_checkout_dir() {
    local common here
    common=$(cd "$(git rev-parse --git-common-dir 2> /dev/null)" 2> /dev/null && pwd -P) || return 0
    here=$(pwd -P)
    case "$common" in
        */.git) common="${common%/.git}" ;;
        *) return 0 ;;
    esac
    if [ "$common" != "$here" ]; then
        printf '%s' "$common"
    fi
}

lastfm_credentials_found() {
    [ -n "$LASTFM_KEY" ] && [ -n "$LASTFM_SECRET" ]
}

# Sets LASTFM_KEY and LASTFM_SECRET, each from the first place that has it: the environment,
# then the env files in the order the comment at the top gives. Either may be left empty.
find_lastfm_credentials() {
    local main
    tidy_env_value "$LASTFM_KEY_FROM_ENV"
    LASTFM_KEY="$ENV_VALUE"
    tidy_env_value "$LASTFM_SECRET_FROM_ENV"
    LASTFM_SECRET="$ENV_VALUE"
    ENV_VALUE=""
    if ! lastfm_credentials_found && [ -n "${STARBAR_SECRETS_FILE:-}" ]; then
        read_lastfm_env_file "$STARBAR_SECRETS_FILE"
    fi
    if ! lastfm_credentials_found; then
        read_lastfm_env_file ".env"
    fi
    if ! lastfm_credentials_found; then
        main=$(main_checkout_dir)
        if [ -n "$main" ]; then
            read_lastfm_env_file "$main/.env"
        fi
    fi
    if ! lastfm_credentials_found; then
        read_lastfm_env_file "$HOME/.config/starbar/secrets.env"
    fi
}

# Prints a value as LastfmCredentials.conceal stores it: each UTF-8 byte XORed with
# LASTFM_PAD, repeating, as two lowercase hex digits. Builtins only, as above. Run it in a
# command substitution, since it sets LC_ALL=C so that the string is walked byte by byte.
conceal_lastfm_value() {
    local value="$1" out="" i byte
    export LC_ALL=C
    for (( i = 0; i < ${#value}; i++ )); do
        printf -v byte '%d' "'${value:i:1}"
        printf -v byte '%02x' $(( (byte & 0xFF) ^ LASTFM_PAD[i % ${#LASTFM_PAD[@]}] ))
        out+="$byte"
    done
    printf '%s' "$out"
}

# Writes build/StarBarSecrets.xcconfig and sets LASTFM_BUILD_ARGS to pass it, or removes it
# when the key or the secret is missing. Called before every build, after any clean, so a
# watch-mode rebuild picks up an env file changed meanwhile. Prints nothing of either value:
# the pad is in this public repository, so a concealed value is as good as the value itself to
# anyone who reads it.
prepare_lastfm_credentials() {
    find_lastfm_credentials
    LASTFM_BUILD_ARGS=()
    LASTFM_CONCEALED_KEY=""
    LASTFM_CONCEALED_SECRET=""
    if ! lastfm_credentials_found; then
        rm -f "$LASTFM_XCCONFIG"
        if [ -n "$LASTFM_KEY" ]; then
            echo "Note: a Last.fm API key but no shared secret (LASTFM_SHARED_SECRET), so this build can't connect to Last.fm"
        elif [ -n "$LASTFM_SECRET" ]; then
            echo "Note: a Last.fm shared secret but no API key (LASTFM_API_KEY), so this build can't connect to Last.fm"
        else
            echo "Note: no Last.fm API key and shared secret (LASTFM_API_KEY, LASTFM_SHARED_SECRET), so this build can't connect to Last.fm"
        fi
        LASTFM_KEY=""
        LASTFM_SECRET=""
        return 0
    fi
    if ! [[ "$LASTFM_KEY" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "Warning: the Last.fm API key isn't 32 hexadecimal characters, the form Last.fm issues. Building with it anyway."
    fi
    if ! [[ "$LASTFM_SECRET" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "Warning: the Last.fm shared secret isn't 32 hexadecimal characters, the form Last.fm issues. Building with it anyway."
    fi
    LASTFM_CONCEALED_KEY=$(conceal_lastfm_value "$LASTFM_KEY")
    LASTFM_CONCEALED_SECRET=$(conceal_lastfm_value "$LASTFM_SECRET")
    LASTFM_KEY=""
    LASTFM_SECRET=""
    mkdir -p build
    rm -f "$LASTFM_XCCONFIG"
    # umask in a subshell, so the file is created 0600 and never readable by anyone else
    ( umask 077; printf 'STARBAR_LASTFM_KEY = %s\nSTARBAR_LASTFM_SECRET = %s\n' "$LASTFM_CONCEALED_KEY" "$LASTFM_CONCEALED_SECRET" > "$LASTFM_XCCONFIG" )
    chmod 600 "$LASTFM_XCCONFIG"
    LASTFM_BUILD_ARGS=(-xcconfig "$LASTFM_XCCONFIG")
    echo "Last.fm: building with the API key and shared secret"
}

# xcodebuild echoes the settings it reads from an -xcconfig file at the top of its output, and
# a failed build prints the whole log, so the concealed values are taken out of the log before
# any of it is shown. They go to grep through a file descriptor, not as arguments.
redact_build_log() {
    local log="$1" redacted line
    [ -n "$LASTFM_CONCEALED_KEY" ] && [ -n "$LASTFM_CONCEALED_SECRET" ] || return 0
    grep -qF -f <(printf '%s\n%s\n' "$LASTFM_CONCEALED_KEY" "$LASTFM_CONCEALED_SECRET") "$log" || return 0
    redacted=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$LASTFM_CONCEALED_SECRET/[Last.fm secret]}"
        printf '%s\n' "${line//$LASTFM_CONCEALED_KEY/[Last.fm key]}"
    done < "$log" > "$redacted"
    mv "$redacted" "$log"
}

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
        -derivedDataPath build \
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
    echo "Build successful: version $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist"))"

    if [ "$INSTALL" = true ]; then
        if [ -d "$INSTALL_PATH" ] && ! command -v trash &> /dev/null; then
            echo "Error: trash not found, so the existing app can't be moved to the Trash. Install with: brew install trash"
            return 1
        fi
        echo "Installing to /Applications..."
        killall "$APP_NAME" 2>/dev/null || true
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
        echo "To install, run: ./build.sh --install"
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

    # The test build has the same bundle ID as the installed app, so quit the installed copy
    # while the tests run, then reopen it
    local was_running=false
    if pgrep -xq "$APP_NAME"; then
        was_running=true
        killall "$APP_NAME" 2>/dev/null || true
        sleep 0.5
    fi

    local status=0
    xcode_test ui-test "$PROJECT_NAME UI Tests" "$MIN_UI_TESTS" || status=1

    if [ "$was_running" = true ] && [ -d "$INSTALL_PATH" ]; then
        open "$INSTALL_PATH"
    fi
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
