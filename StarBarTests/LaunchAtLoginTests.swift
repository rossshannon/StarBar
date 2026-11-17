//
//  LaunchAtLoginTests.swift
//  StarBarTests
//
//  Which copies of the app may register themselves as a login item. Needs no Music app.
//

import XCTest
@testable import StarBar

final class LaunchAtLoginTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    private func isInstalled(_ path: String) -> Bool {
        return LaunchAtLogin.isInstalledLocation(URL(fileURLWithPath: path), home: home)
    }

    func testAnAppInAnApplicationsFolderIsInstalled() {
        XCTAssertTrue(isInstalled("/Applications/StarBar.app"))
        XCTAssertTrue(isInstalled("/Users/someone/Applications/StarBar.app"))
    }

    /// Builds from Xcode and build.sh are never installed copies, Debug or Release
    func testABuildIsNotInstalled() {
        XCTAssertFalse(isInstalled("/Users/someone/Library/Developer/Xcode/DerivedData/StarBar-abc/Build/Products/Debug/StarBar.app"))
        XCTAssertFalse(isInstalled("/Users/someone/Library/Caches/StarBar-build/v1.2.0-a6b01cad/build/test/Build/Products/Debug/StarBar.app"))
        XCTAssertFalse(isInstalled("/Users/someone/Library/Caches/StarBar-build/StarBar-cb35e033/build/Build/Products/Release/StarBar.app"))
    }

    /// A folder whose name only starts with "Applications" is not one
    func testALookalikeFolderIsNotInstalled() {
        XCTAssertFalse(isInstalled("/Applications Old/StarBar.app"))
        XCTAssertFalse(isInstalled("/Users/someone/ApplicationsBackup/StarBar.app"))
        XCTAssertFalse(isInstalled("/Users/other/Applications/StarBar.app"))
    }

    /// StarBar Dev never opens at login, wherever it is; StarBar does from an Applications folder
    func testOnlyStarBarMayOpenAtLogin() {
        let dev = URL(fileURLWithPath: "/Applications/StarBar Dev.app")
        XCTAssertTrue(LaunchAtLogin.refusal(for: .dev, at: dev, home: home) is LaunchAtLogin.DevBuildError)
        XCTAssertNil(LaunchAtLogin.refusal(for: .standard, at: URL(fileURLWithPath: "/Applications/StarBar.app"), home: home))
        let build = URL(fileURLWithPath: "/Users/someone/Development/StarBar/build/Build/Products/Release/StarBar.app")
        XCTAssertTrue(LaunchAtLogin.refusal(for: .standard, at: build, home: home) is LaunchAtLogin.NotInstalledError)
    }

    /// The test host itself is a build, so it must not count as installed
    func testTheTestHostIsNotInstalled() {
        XCTAssertFalse(LaunchAtLogin.isInstalledLocation(Bundle.main.bundleURL))
    }

    /// StarBar Dev's checkbox is greyed out and says why, rather than ticking and turning straight back off
    func testOnlyStarBarsCheckboxCanBeTicked() {
        let standard = LaunchAtLogin.checkbox(for: .standard)
        XCTAssertEqual(standard.title, "Launch at login")
        XCTAssertTrue(standard.isEnabled)
        XCTAssertNil(standard.toolTip)

        let dev = LaunchAtLogin.checkbox(for: .dev)
        XCTAssertEqual(dev.title, "Launch at login (StarBar only)")
        XCTAssertFalse(dev.isEnabled)
        XCTAssertEqual(dev.toolTip, "StarBar Dev doesn’t open at login. StarBar does.")
    }

}
