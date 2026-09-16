#!/bin/bash

# Build script for Music Rating
#
#   ./build.sh              Clean Release build into build/
#   ./build.sh --install    Also replace /Applications/Music Rating.app and launch it
#   ./build.sh --watch      Rebuild on source changes (combine with --install)
#   ./build.sh --test       Run the app and SDK tests that don't need Music
#   ./build.sh --test-all   Also run the tests that talk to Music (needs a track playing)

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

for arg in "$@"; do
    case $arg in
        --install|-i) INSTALL=true ;;
        --watch|-w) WATCH=true ;;
        --test|-t) TEST=true ;;
        --test-all) TEST=true; TEST_ALL=true ;;
        *) echo "Unknown option: $arg"; exit 2 ;;
    esac
done

if [ "$TEST" = true ] && { [ "$INSTALL" = true ] || [ "$WATCH" = true ]; }; then
    echo "Error: --test runs on its own. Don't combine it with --install or --watch."
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
        echo "Done!"
    else
        echo "App location: $APP_PATH"
        echo "To install, run: ./build.sh --install"
    fi
}

run_tests() {
    # These test classes read from Music, so they fail unless Music is playing a track
    # with artwork and Music Rating may access the media library. CI has no Music.
    # Test identifiers use the target name ("Song RatingTests"); the module name is silently ignored.
    local skip_args=()
    if [ "$TEST_ALL" = false ]; then
        skip_args=(
            "-skip-testing:Song RatingTests/ScriptBridgeTests"
            "-skip-testing:Song RatingTests/iTunesLibraryTests"
        )
    fi
    local test_dir="build/test"
    local test_log="$test_dir/test.log"
    # xcodebuild won't overwrite a result bundle, so each run gets its own
    local result_bundle="$test_dir/results/TestResults-$(date +%Y%m%d-%H%M%S).xcresult"
    local status=0

    mkdir -p "$test_dir/results"

    echo ""
    echo "=== Testing $APP_NAME... ==="
    # The app hosts the tests, so a test run launches it
    if xcodebuild -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$PROJECT_NAME" \
        -destination "platform=macOS" \
        -derivedDataPath "$test_dir" \
        -resultBundlePath "$result_bundle" \
        "${skip_args[@]}" \
        test > "$test_log" 2>&1; then
        grep -E "Executed [0-9]+ tests|\*\* TEST" "$test_log" | tail -2
    else
        status=1
        # Failed tests first, then the end of the log, which explains crashes and build errors
        grep -E ": error:|Test Case .* failed" "$test_log" || true
        echo "--- last 40 lines of $test_log ---"
        tail -40 "$test_log"
        echo "App tests failed. Full log: $test_log"
        echo "Results: $result_bundle"
    fi

    echo ""
    echo "=== Testing SDK... ==="
    (cd SDK && swift test) || status=1

    return $status
}

if [ "$TEST" = true ]; then
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
