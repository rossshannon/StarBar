//
//  BuildInfoTests.swift
//  StarBarTests
//
//  Which build is running and what it says it was built from. Needs no Music app.
//

import XCTest
@testable import StarBar

final class BuildInfoTests: XCTestCase {

    private let dublin = TimeZone(identifier: "Europe/Dublin")!
    private let irish = Locale(identifier: "en_IE")

    private func info(_ extra: [String: Any] = [:]) -> [String: Any] {
        var info: [String: Any] = [
            "CFBundleName": "StarBar",
            "CFBundleShortVersionString": "1.10.0",
            "CFBundleVersion": "472",
            // What Info.plist holds when build.sh passed nothing: the settings expand to nothing
            BuildInfo.branchKey: "",
            BuildInfo.commitKey: "",
            BuildInfo.modifiedKey: "",
            BuildInfo.buildDateKey: "",
        ]
        info.merge(extra) { _, new in new }
        return info
    }

    func testTheBundleIdentifierSaysWhichVariantThisIs() {
        XCTAssertEqual(BuildInfo(bundleIdentifier: "com.rossshannon.starbar", info: info()).variant, .standard)
        XCTAssertEqual(BuildInfo(bundleIdentifier: "com.rossshannon.starbar.dev", info: info()).variant, .dev)
        // The test host is StarBar itself
        XCTAssertEqual(BuildInfo.current.variant, .standard)
        XCTAssertFalse(BuildInfo.current.isDev)
    }

    func testEachVariantNamesTheOther() {
        XCTAssertEqual(BuildInfo(bundleIdentifier: BuildInfo.standardBundleIdentifier, info: info()).otherVariantBundleIdentifier, BuildInfo.devBundleIdentifier)
        XCTAssertEqual(BuildInfo(bundleIdentifier: BuildInfo.devBundleIdentifier, info: info()).otherVariantBundleIdentifier, BuildInfo.standardBundleIdentifier)
    }

    /// A release, or a build from Xcode, says nothing about where it came from
    func testAReleaseShowsNoSource() {
        let build = BuildInfo(bundleIdentifier: BuildInfo.standardBundleIdentifier, info: info())
        XCTAssertFalse(build.hasSource)
        XCTAssertEqual(build.sourceLines(timeZone: dublin, locale: irish), [])
        XCTAssertEqual(build.logDescription, "StarBar 1.10.0 (472)")
    }

    /// Settings Info.plist never had expand to nothing too, so a missing key is a release
    func testMissingKeysAreARelease() {
        let build = BuildInfo(bundleIdentifier: BuildInfo.standardBundleIdentifier, info: ["CFBundleName": "StarBar"])
        XCTAssertNil(build.commit)
        XCTAssertNil(build.branch)
        XCTAssertFalse(build.hasUncommittedChanges)
        XCTAssertEqual(build.version, "NA")
    }

    func testABranchBuildShowsItsBranchAndCommit() {
        let build = BuildInfo(bundleIdentifier: BuildInfo.devBundleIdentifier, info: info([
            "CFBundleName": "StarBar Dev",
            BuildInfo.branchKey: "claude/project-thread-wiixq5",
            BuildInfo.commitKey: "8e3dd1e",
            BuildInfo.modifiedKey: "NO",
            BuildInfo.buildDateKey: "2026-11-16T21:40:05Z",
        ]))
        XCTAssertTrue(build.hasSource)
        let lines = build.sourceLines(timeZone: dublin, locale: irish)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first, "claude/project-thread-wiixq5")
        XCTAssertTrue(lines.last!.hasPrefix("8e3dd1e, built "), lines.last!)
        // In Dublin's time, which is UTC in November
        XCTAssertTrue(lines.last!.contains("16"), lines.last!)
        XCTAssertTrue(lines.last!.contains("21:40"), lines.last!)
        XCTAssertEqual(build.logDescription, "StarBar Dev 1.10.0 (472) from claude/project-thread-wiixq5 at 8e3dd1e, built 2026-11-16T21:40:05Z")
    }

    func testUncommittedChangesAreSaid() {
        let build = BuildInfo(bundleIdentifier: BuildInfo.standardBundleIdentifier, info: info([
            BuildInfo.branchKey: "main",
            BuildInfo.commitKey: "8c978ba",
            BuildInfo.modifiedKey: "YES",
        ]))
        XCTAssertTrue(build.hasUncommittedChanges)
        XCTAssertEqual(build.sourceLines(timeZone: dublin, locale: irish), ["main", "8c978ba + changes"])
        XCTAssertEqual(build.logDescription, "StarBar 1.10.0 (472) from main at 8c978ba with uncommitted changes")
    }

    /// A detached checkout has no branch, and the commit stands on its own
    func testADetachedBuildShowsOnlyItsCommit() {
        let build = BuildInfo(bundleIdentifier: BuildInfo.standardBundleIdentifier, info: info([
            BuildInfo.commitKey: "1abb0d8",
        ]))
        XCTAssertNil(build.branch)
        XCTAssertEqual(build.sourceLines(timeZone: dublin, locale: irish), ["1abb0d8"])
        XCTAssertEqual(build.logDescription, "StarBar 1.10.0 (472) from 1abb0d8")
    }

    /// A date that doesn't parse is left out rather than shown wrong
    func testAnUnreadableBuildDateIsLeftOut() {
        let build = BuildInfo(bundleIdentifier: BuildInfo.standardBundleIdentifier, info: info([
            BuildInfo.branchKey: "main",
            BuildInfo.commitKey: "8c978ba",
            BuildInfo.buildDateKey: "yesterday",
        ]))
        XCTAssertNil(build.buildDate)
        XCTAssertEqual(build.sourceLines(timeZone: dublin, locale: irish), ["main", "8c978ba"])
    }

}
