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


Conversation Summary

  We worked on enhancing a macOS menu bar app "Song Rating" that integrates with Apple Music to
  display and modify song ratings.

  What we did:

  1. Initial setup:
    - Created CLAUDE.md with build commands and code style guidelines
    - Fixed code signing issues by removing the original developer's team IDs and bundle
  identifiers
  2. Added "loved/favorite" status indicator:
    - Implemented a star icon next to the rating stars in the menu bar to show favorite status
    - Fixed heart/star icon rendering and click detection
    - Updated terminology from "loved" to "favorite" to match Apple Music's current UI
  3. Fixed technical issues:
    - Resolved build errors by integrating star drawing directly into Stars.swift
    - Enhanced iTunes track status detection to ensure we display current data
    - Added detailed logging for debugging

  Files we modified:

  - Core functionality:
    - /Song Rating/Controls/MenuBarRatingControl.swift - Main controller for menu bar
  interactions
    - /Song Rating/Controls/RatingControl.swift - Controls star rating display and interaction
    - /Song Rating/Helper/Stars.swift - Draws the star ratings and favorite icon
    - /Song Rating/iTunes/iTunesPlayer.swift - Manages iTunes/Music interaction
    - /Song Rating/iTunes/Extension/iTunesTrack.swift - Extends iTunesTrack with rating
  functions
  - Setup:
    - Song Rating.xcodeproj/project.pbxproj - Updated code signing and dependencies
    - Created CLAUDE.md with project guidelines

  Current state:

  - The app now displays song ratings (0-5 stars) and favorite status (star icon)
  - Clicking on rating stars updates the song's rating in Apple Music
  - Clicking on the favorite star toggles the song's "loved" status in Apple Music
  - We've added robust logging to help debug any issues with favorite status synchronization

  Next steps could include:

  1. Further UI refinements for better visibility
  2. Additional features like keyboard shortcuts
  3. Testing with different versions of macOS and Apple Music
  4. Releasing your version with these improvements
