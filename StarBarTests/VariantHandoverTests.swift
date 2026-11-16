//
//  VariantHandoverTests.swift
//  StarBarTests
//
//  StarBar and StarBar Dev take turns: the one opened last runs. Needs no Music app.
//

import XCTest
@testable import StarBar

final class VariantHandoverTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    private let standard = BuildInfo.standardBundleIdentifier
    private let dev = BuildInfo.devBundleIdentifier
    private let opened = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let installedStandard = URL(fileURLWithPath: "/Applications/StarBar.app")
    private let installedDev = URL(fileURLWithPath: "/Applications/StarBar Dev.app")

    private func action(other: String?, at url: URL?, launched: Date?, own: String, now: Date? = nil) -> VariantHandover.Action {
        return VariantHandover.action(otherBundleIdentifier: other, otherBundleURL: url, otherLaunched: launched,
                                      ownBundleIdentifier: own, ownLaunched: opened, now: now ?? opened.addingTimeInterval(60), home: home)
    }

    /// StarBar opened while StarBar Dev runs: StarBar Dev quits, and the other way round
    func testTheCopyOpenedFirstStepsAside() {
        XCTAssertEqual(action(other: standard, at: installedStandard, launched: opened.addingTimeInterval(30), own: dev), .stepAside)
        XCTAssertEqual(action(other: dev, at: installedDev, launched: opened.addingTimeInterval(30), own: standard), .stepAside)
    }

    /// The newcomer leaves it to the older copy
    func testTheCopyOpenedLastWaits() {
        XCTAssertEqual(action(other: standard, at: installedStandard, launched: opened.addingTimeInterval(-30), own: dev), .waitForOther)
        XCTAssertEqual(action(other: dev, at: installedDev, launched: opened.addingTimeInterval(-30), own: standard), .waitForOther)
    }

    /// A copy whose launch the system can't date counts as opened when it was seen
    func testAnUndatedCopyCountsAsNew() {
        XCTAssertEqual(action(other: standard, at: installedStandard, launched: nil, own: dev), .stepAside)
        XCTAssertEqual(action(other: standard, at: installedStandard, launched: nil, own: dev, now: opened.addingTimeInterval(-1)), .waitForOther)
    }

    /// Two opened at the same instant: StarBar runs
    func testATieGoesToStarBar() {
        XCTAssertEqual(action(other: standard, at: installedStandard, launched: opened, own: dev), .stepAside)
        XCTAssertEqual(action(other: dev, at: installedDev, launched: opened, own: standard), .waitForOther)
    }

    /// The test host is StarBar, run from DerivedData: a test run mustn't make StarBar Dev quit.
    /// Nor does a copy run from a build folder.
    func testOnlyInstalledCopiesCount() {
        let testHost = URL(fileURLWithPath: "/Users/someone/Library/Developer/Xcode/DerivedData/StarBar-abc/Build/Products/Debug/StarBar.app")
        let buildFolder = URL(fileURLWithPath: "/Users/someone/Development/StarBar/.worktrees/x/build/dev/Build/Products/Release/StarBar Dev.app")
        XCTAssertEqual(action(other: standard, at: testHost, launched: opened.addingTimeInterval(30), own: dev), .ignore)
        XCTAssertEqual(action(other: dev, at: buildFolder, launched: opened.addingTimeInterval(30), own: standard), .ignore)
        XCTAssertEqual(action(other: standard, at: nil, launched: opened.addingTimeInterval(30), own: dev), .ignore)
        XCTAssertEqual(action(other: dev, at: URL(fileURLWithPath: "/Users/someone/Applications/StarBar Dev.app"), launched: opened.addingTimeInterval(30), own: standard), .stepAside)
    }

    /// Another copy of the same variant, and every other app, are none of its business
    func testOnlyTheOtherVariantCounts() {
        XCTAssertEqual(action(other: standard, at: installedStandard, launched: opened.addingTimeInterval(30), own: standard), .ignore)
        XCTAssertEqual(action(other: "com.apple.Music", at: URL(fileURLWithPath: "/System/Applications/Music.app"), launched: opened.addingTimeInterval(30), own: standard), .ignore)
        XCTAssertEqual(action(other: nil, at: installedStandard, launched: opened.addingTimeInterval(30), own: dev), .ignore)
        // A copy that is neither, such as the test bundle's own identifier, steps aside for nobody
        XCTAssertEqual(action(other: dev, at: installedDev, launched: opened.addingTimeInterval(30), own: "com.rossshannon.starbar.tests"), .ignore)
    }

    /// Under tests the watcher never starts, so this test run can't quit an installed copy
    func testTheWatcherDoesNotRunUnderTests() {
        VariantHandover.shared.start()
        XCTAssertFalse(VariantHandover.shared.isWatching)
    }

}
