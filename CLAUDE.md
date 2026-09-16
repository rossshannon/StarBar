# Music Rating Project Guide

The app is named "Music Rating". The Xcode project, scheme, targets, source folders and Swift module (`Song_Rating`, pinned with `PRODUCT_MODULE_NAME` because storyboards reference it) keep the upstream "Song Rating" name.

## Build & Test Commands
- Build (Release, into `build/`): `./build.sh`
- Build, install to /Applications, and relaunch: `./build.sh --install`
- Rebuild on file changes: `./build.sh --watch --install` (needs `brew install fswatch`)
- Xcode is at `~/Downloads/Xcode-beta.app` and `xcode-select` points at the Command Line Tools. `build.sh` finds Xcode itself; for raw `xcodebuild` or `swift test`, prefix with `DEVELOPER_DIR=/Users/ross/Downloads/Xcode-beta.app/Contents/Developer`.
- Signing: ad-hoc ("Sign to Run Locally"), no development team. Bundle IDs are `com.rossshannon.musicrating`, `.helper`, `.tests`. The helper and main app IDs are also hard-coded in both `AppDelegate.swift` files.
- Build: `xcodebuild -project "Song Rating.xcodeproj" -scheme "Song Rating" build`
- Test (app tests that don't need Music, plus SDK tests): `./build.sh --test`
- Test everything, including `ScriptBridgeTests` and `iTunesLibraryTests`: `./build.sh --test-all`. These need Music playing a track with artwork and media library access, so they run locally only. CI builds the app and runs the SDK tests.
- The app tests are hosted in Music Rating, so a test run launches the app. The test target is signed ad hoc like the app; without that, `xcodebuild test` asks for a development team.
- Test: `xcodebuild -project "Song Rating.xcodeproj" -scheme "Song Rating" test`
- Run specific test: `xcodebuild -project "Song Rating.xcodeproj" -scheme "Song Rating" test -only-testing:"Song RatingTests/TestClassName/testMethodName"` (target name with the space, not the module name; a wrong identifier is silently ignored)
- SDK Tests: `cd SDK && swift test`
- Clean: `xcodebuild -project "Song Rating.xcodeproj" clean`

## Code Style Guidelines
- **Formatting**: 4-space indentation, braces on same line as declarations
- **Imports**: Foundation first, then Cocoa/UI frameworks, third-party imports last
- **Naming**: Classes use PascalCase, variables/properties use camelCase
- **Favorites**: Music renamed "Loved" to "Favorite". Code says `favorite` (the heart: `favoriteMinX`, `isFavoriteHit`) and `favorited` (the state: `isFavorited`, `updateFavorited(_:)`), in American spelling to match Apple's API. User-facing text uses British "favourite". `loved` appears only in the Scripting Bridge header (`iTunes/Vendor/iTunes.swift`) and the fallback for older Music versions in `iTunesTrack.swift`.
- **Click geometry**: keep hit-testing in pure functions on `RatingControl` (`starRating(atPositionX:behavior:)`, `isFavoriteHit(positionX:)`) and cover them in `RatingControlGeometryTests`
- **Menu bar gestures**: click sets the rating or toggles the heart; press and hold sets the rating on release; drag previews the stars and saves on release (`RatingControl.Drag`, tested in `RatingControlDragTests`). Ratings the user chooses go through `RatingControl.commit(rating:)`; display-only changes use `update(rating:)`.
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
