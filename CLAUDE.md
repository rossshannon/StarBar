# StarBar Project Guide

The app, Xcode project, schemes, targets, source folders and Swift module are all named StarBar. The module name is pinned with `PRODUCT_MODULE_NAME` because the storyboards reference it.

## Build & Test Commands
- Build (Release, into `build/`): `./build.sh`
- Build, install to /Applications, and relaunch: `./build.sh --install`. It ends with an install verification block (commit, binary hash, running PID). Always follow the `install-and-verify` skill (`.claude/skills/install-and-verify/`): never report an install as done without that block and log evidence that the changed code runs.
- Rebuild on file changes: `./build.sh --watch --install` (needs `brew install fswatch`)
- Xcode is at `~/Downloads/Xcode-beta.app` and `xcode-select` points at the Command Line Tools. `build.sh` finds Xcode itself; for raw `xcodebuild` or `swift test`, prefix with `DEVELOPER_DIR=/Users/ross/Downloads/Xcode-beta.app/Contents/Developer`.
- Signing: ad-hoc ("Sign to Run Locally"), no development team. Bundle IDs are `com.rossshannon.starbar`, `.helper`, `.tests`, `.uitests`. The helper and main app IDs are also hard-coded in both `AppDelegate.swift` files.
- Build: `xcodebuild -project "StarBar.xcodeproj" -scheme "StarBar" build`
- Test (app tests that don't need Music, plus SDK tests): `./build.sh --test`
- Test everything, including `ScriptBridgeTests` and `iTunesLibraryTests`: `./build.sh --test-all`. These need Music playing a track with artwork and media library access, so they run locally only. CI (`.github/workflows/test.yml`) runs `./build.sh` and `./build.sh --test` on macos-15, macos-26 and xcode-27 (the macOS 27 preview, non-blocking), and `--ui-test` on macos-26 and xcode-27, so the skip list lives only in `build.sh`.
- The app tests are hosted in StarBar, so a test run launches the app. The test target is signed ad hoc like the app; without that, `xcodebuild test` asks for a development team.
- UI tests (click and drag the real menu bar): `./build.sh --ui-test`. **Only run them when Ross asks.** They take over the mouse and screen for about two minutes. The script asks for confirmation, and a non-interactive run stops unless `--yes` is passed; pass `--yes` only after Ross has asked for UI tests in this conversation. CI runs them on every push, so that is the normal way to get them. The app runs with `-UITesting YES` (fake playing state, no Music), and `MenuBarRatingUITests` reads the status item's accessibility value ("3½ stars, favourite"). Needs macOS Automation Mode: `sudo automationmodetool enable-automationmode-without-authentication`, or authenticate when asked. The UI tests have their own shared scheme, `StarBar UI Tests`; the `StarBar` scheme doesn't include them, so a plain `xcodebuild test` or Xcode's Product > Test can't take over the screen. Keep it that way. (A skipped testable can't be picked with `-only-testing` either, which is why it's a separate scheme.)
- Test logs: `build/test/test.log`, `build/test/ui-test.log`; result bundles: `build/test/results/`
- Pre-commit hook (opt in): `git config core.hooksPath .githooks`
- Release: push a `v*` tag; `.github/workflows/release.yml` tests, builds with `MARKETING_VERSION` from the tag, and attaches a zip to a GitHub release
- Test (unit tests only, including the ones that need Music): `xcodebuild -project "StarBar.xcodeproj" -scheme "StarBar" test`
- Run specific test: `xcodebuild -project "StarBar.xcodeproj" -scheme "StarBar" test -only-testing:"StarBarTests/TestClassName/testMethodName"` (a wrong identifier is silently ignored)
- SDK Tests: `cd SDK && swift test`
- Clean: `xcodebuild -project "StarBar.xcodeproj" clean`

## Code Style Guidelines
- **Formatting**: 4-space indentation, braces on same line as declarations
- **Imports**: Foundation first, then Cocoa/UI frameworks, third-party imports last
- **Naming**: Classes use PascalCase, variables/properties use camelCase
- **Favorites**: Music renamed "Loved" to "Favorite". Code says `favorite` (the heart: `favoriteMinX`, `isFavoriteHit`) and `favorited` (the state: `isFavorited`, `updateFavorited(_:)`), in American spelling to match Apple's API. User-facing text uses British "favourite". `loved` appears only in the Scripting Bridge header (`iTunes/Vendor/iTunes.swift`) and the fallback for older Music versions in `iTunesTrack.swift`.
- **Click geometry**: keep hit-testing in pure functions on `RatingControl` (`starRating(atPositionX:behavior:)`, `isFavoriteHit(positionX:)`) and cover them in `RatingControlGeometryTests`
- **Menu bar gestures**: on macOS 27 the menu bar sends the status item one synthesised click (mouse down and up together) when the mouse goes down, and no drag events, so pan and press recognizers never fire there. Before macOS 27, real drag events arrive and the click recognizer fails, so a pan recognizer starts the drag instead. Both paths call the same handler. `RatingClickController` toggles the heart, saves a plain click, or, while the left button is still held, follows a drag: `MenuBarRatingControl` calls `tick()` from a 60 Hz timer, the stars preview, and the rating is saved on release. The mouse comes from a `RatingPointer` (`StatusButtonPointer` reads `NSEvent`), so `RatingClickControllerTests` drives clicks and drags with a fake one. Ratings the user chooses go through `RatingControl.commit(rating:)`; display-only changes use `update(rating:)`.
- **Rating reminder**: `RatingReminder` (pure timing rule) and `StarSweep` are covered by `RatingReminderTests`; `RatingReminderController` takes a fake bell and clock in `RatingReminderControllerTests`. Music posts no `playerInfo` notification when the user seeks, so the controller reads `playerPosition` every 2 s while a reminder is pending. Music saves ratings after a 2 s debounce, so every user rating path must call `userDidRate()`. The sweep only sets `RatingControl.sweepPosition` and never changes `rating`.
- **Track announcement**: the Growl-style "Music Video" strip. `TrackAnnouncement` (value type) and `TrackAnnouncementLayout` / `TrackAnnouncementPlacement` (pure geometry, Growl's constants) are covered by `TrackAnnouncementLayoutTests`. `TrackAnnouncementController` takes closures for the player read and artwork load, a `TrackAnnouncementPresenter` and the reminder's `RatingReminderClock`, and `TrackAnnouncementControllerTests` drives it with fakes (`FakeClock` is shared with the reminder tests). Track identity is the 16-character hex persistent ID (`PlayerSnapshot.identity(persistentID:)` converts the notification's `Int`); the artwork loader returns `.trackChanged` when the live track's ID differs, and the announcement is dropped. Music sends no notification at launch, so `AppDelegate.setupTrackAnnouncement()` seeds the controller with `playerDidUpdate(seedOnly: true)` before observing `.iTunesPlayerDidUpdated`; a track is "seen" once it has played, so a resumed track never announces but one skipped to while paused does. Replace, never queue. `TrackAnnouncementPanel` is a non-activating `NSPanel` one window level below the Dock (so a side Dock draws over it), spanning the screen width and resting on the `visibleFrame` bottom, while `TrackAnnouncementView` slides inside it; the layout scales with the screen height (`TrackAnnouncementLayout.scale(forScreenHeight:)`, 1 at 1000 pt, capped at 2); it must never go through `WindowManager.open(_:)` or be counted by `hasWindowDisplay`, which would activate the app.
- **Files**: File names match class names (e.g., `PlayerViewController.swift`)
- **Types**: Prefer optionals with safe unwrapping, limit force unwraps to controlled contexts
- **Error Handling**: Use do-catch blocks with descriptive messages, leverage os_log for errors
- **Extensions**: Organize code using extensions grouped by functionality
- **Preview**: SwiftUI previews at bottom of files with conditional compilation

## Architecture
- Target macOS 12+, Swift 5.7+
- Uses SPM for dependencies
- Protocol-oriented design with delegates
- NotificationCenter for app-wide communication
- Singletons for shared services
