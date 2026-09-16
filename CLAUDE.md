# Music Rating Project Guide

The app is named "Music Rating". The Xcode project, scheme, targets, source folders and Swift module (`Song_Rating`, pinned with `PRODUCT_MODULE_NAME` because storyboards reference it) keep the upstream "Song Rating" name.

## Build & Test Commands
- Build (Release, into `build/`): `./build.sh`
- Build, install to /Applications, and relaunch: `./build.sh --install`
- Rebuild on file changes: `./build.sh --watch --install` (needs `brew install fswatch`)
- Xcode is at `~/Downloads/Xcode-beta.app` and `xcode-select` points at the Command Line Tools. `build.sh` finds Xcode itself; for raw `xcodebuild` or `swift test`, prefix with `DEVELOPER_DIR=/Users/ross/Downloads/Xcode-beta.app/Contents/Developer`.
- Signing: ad-hoc ("Sign to Run Locally"), no development team. Bundle IDs are `com.rossshannon.musicrating`, `.helper`, `.tests`. The helper and main app IDs are also hard-coded in both `AppDelegate.swift` files.
- Build: `xcodebuild -project "Song Rating.xcodeproj" -scheme "Song Rating" build`
- Test: `xcodebuild -project "Song Rating.xcodeproj" -scheme "Song Rating" test`
- Run specific test: `xcodebuild -project "Song Rating.xcodeproj" -scheme "Song Rating" test -only-testing:Song_RatingTests/TestClassName/testMethodName`
- SDK Tests: `cd SDK && swift test`
- Clean: `xcodebuild -project "Song Rating.xcodeproj" clean`

## Code Style Guidelines
- **Formatting**: 4-space indentation, braces on same line as declarations
- **Imports**: Foundation first, then Cocoa/UI frameworks, third-party imports last
- **Naming**: Classes use PascalCase, variables/properties use camelCase
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
