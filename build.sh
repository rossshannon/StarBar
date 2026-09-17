#!/bin/bash

# Build script for Music Rating
#
#   ./build.sh              Clean Release build into build/
#   ./build.sh --install    Also replace /Applications/Music Rating.app and launch it
#   ./build.sh --watch      Rebuild on source changes (combine with --install)
#   ./build.sh --test       Run the app and SDK tests that don't need Music
#   ./build.sh --test-all   Also run the tests that talk to Music (needs a track playing)
#   ./build.sh --ui-test    Run the UI tests, which take over the screen (asks first; --yes skips)

set -e
set -o pipefail

cd "$(dirname "$0")"

# Xcode project and scheme keep the upstream "Song Rating" name; the product is "Music Rating"
PROJECT_NAME="Song Rating"
APP_NAME="Music Rating"
APP_PATH="build/Build/Products/Release/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

INSTALL=false
WATCH=false
TEST=false
TEST_ALL=false
UI_TEST=false
ASSUME_YES=false

for arg in "$@"; do
    case $arg in
        --install|-i) INSTALL=true ;;
        --watch|-w) WATCH=true ;;
        --test|-t) TEST=true ;;
        --test-all) TEST=true; TEST_ALL=true ;;
        --ui-test) UI_TEST=true ;;
        --yes|-y) ASSUME_YES=true ;;
        *) echo "Unknown option: $arg"; exit 2 ;;
    esac
done

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

build_and_install() {
    echo ""
    echo "=== Building $APP_NAME... ==="

    # Capture build output so a failure shows the full log
    BUILD_LOG=$(mktemp)
    if xcodebuild -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$PROJECT_NAME" \
        -configuration Release \
        -derivedDataPath build \
        clean build > "$BUILD_LOG" 2>&1; then
        tail -10 "$BUILD_LOG"
        rm -f "$BUILD_LOG"
    else
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
    echo "Build successful!"

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

# Run xcodebuild test with the given selection arguments.
# Usage: xcode_test <name> [-only-testing:... | -skip-testing:...]...
# Writes build/test/<name>.log and a result bundle under build/test/results/.
xcode_test() {
    local name="$1"
    shift
    local test_dir="build/test"
    local test_log="$test_dir/$name.log"
    # xcodebuild won't overwrite a result bundle, so each run gets its own
    local result_bundle="$test_dir/results/$name-$(date +%Y%m%d-%H%M%S).xcresult"

    mkdir -p "$test_dir/results"
    if xcodebuild -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$PROJECT_NAME" \
        -destination "platform=macOS" \
        -derivedDataPath "$test_dir" \
        -resultBundlePath "$result_bundle" \
        "$@" \
        test > "$test_log" 2>&1; then
        grep -E "Executed [0-9]+ tests|\*\* TEST" "$test_log" | tail -2
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
    # Test identifiers use the target name ("Song RatingTests"); the module name is silently ignored.
    # The UI tests move the mouse, so they run only with --ui-test.
    local selection=("-skip-testing:Song RatingUITests")
    # These test classes read from Music, so they fail unless Music is playing a track
    # with artwork and Music Rating may access the media library. CI has no Music.
    if [ "$TEST_ALL" = false ]; then
        selection+=(
            "-skip-testing:Song RatingTests/ScriptBridgeTests"
            "-skip-testing:Song RatingTests/iTunesLibraryTests"
        )
    fi
    local status=0

    echo ""
    echo "=== Testing $APP_NAME... ==="
    # The app hosts the unit tests, so a test run launches it
    xcode_test test "${selection[@]}" || status=1

    echo ""
    echo "=== Testing SDK... ==="
    (cd SDK && swift test) || status=1

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
        read -r -p "Take over the screen now? [y/N] " answer
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
    xcode_test ui-test "-only-testing:Song RatingUITests" || status=1

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

    echo "Watching: Song Rating/, Song Rating Helper/, SDK/Sources/"
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
        -r "Song Rating/" "Song Rating Helper/" "SDK/Sources/" | while read -r; do
        echo ""
        echo "Change detected, rebuilding..."
        build_and_install || true
    done
else
    build_and_install
fi
