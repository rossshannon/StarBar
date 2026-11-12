//
//  HeartBurstWindowTests.swift
//  StarBarTests
//
//  The see-through window over the menu bar that the heart's burst is drawn in: out of the
//  way of every click, centred on the heart, drawn where it is stepped to, and taken down at
//  once. It has no clock of its own; `MenuBarHeartChangeTests` covers it stepping with the
//  heart. Each test stops the window, so nothing is left on screen.
//

import XCTest
@testable import StarBar

final class HeartBurstWindowTests: XCTestCase {

    private var window: HeartBurstWindow!

    override func setUp() {
        super.setUp()
        window = HeartBurstWindow()
    }

    override func tearDown() {
        window.stop()
        window = nil
        super.tearDown()
    }

    private let burst = HeartBurst.menuBar(heartSize: 16)

    /// A 16 point heart 12 points below the top of the main screen, as on a 24 point menu bar
    private func heart() throws -> NSRect {
        let screen = try XCTUnwrap(NSScreen.main)
        return NSRect(x: screen.frame.midX.rounded(), y: screen.frame.maxY - 12 - 8, width: 16, height: 16)
    }

    func testTheWindowNeverTakesFocusOrClicks() {
        XCTAssertTrue(window.ignoresMouseEvents, "a quick second click still reaches the heart")
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.hasShadow)
        XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.statusBar.rawValue, "over the menu bar's items")
        XCTAssertLessThan(window.level.rawValue, NSWindow.Level.popUpMenu.rawValue, "under an open menu")
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.isVisible, "nothing on screen until a heart is set")
    }

    func testItBurstsCentredOnTheHeartAndDrawsWhereItIsStepped() throws {
        let heart = try heart()

        window.play(around: heart, burst: burst, palette: .music)

        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.isPlaying)
        XCTAssertEqual(window.burstView.change, .burst)
        XCTAssertEqual(window.burstView.elapsed, 0)
        XCTAssertGreaterThanOrEqual(window.frame.width / 2, burst.extent, "room for every dot")
        let centre = NSPoint(x: window.frame.minX + window.burstView.centre!.x, y: window.frame.minY + window.burstView.centre!.y)
        XCTAssertEqual(centre.x, heart.midX, accuracy: 0.001)
        XCTAssertEqual(centre.y, heart.midY, accuracy: 0.001)
        XCTAssertEqual(window.frame.origin.x, window.frame.origin.x.rounded(), "in whole points")

        window.step(to: 0.4)
        XCTAssertEqual(window.burstView.elapsed, 0.4)
        XCTAssertTrue(window.isVisible)
    }

    /// The burst view is the window's content view, so it takes whatever size each burst
    /// needs. The menu bar's is the window's starting size, so a bigger one is what shows it.
    func testTheBurstFillsTheWindowWhateverItsSize() throws {
        let heart = try heart()
        let bigger = HeartBurst.strip(heartSize: 12)

        window.play(around: heart, burst: bigger, palette: .music)

        XCTAssertGreaterThan(window.frame.width, 64, "bigger than the window's starting size")
        XCTAssertEqual(window.burstView.frame.size, window.frame.size)

        window.play(around: heart, burst: burst, palette: .music)

        XCTAssertLessThan(window.frame.width, 2 * bigger.extent)
        XCTAssertEqual(window.burstView.frame.size, window.frame.size)
    }

    /// The menu bar's heart is only 12 points below the screen's top edge, and a window put
    /// there must not be pushed down, or the burst would be off-centre
    func testTheWindowReachesAboveTheScreensTopEdge() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let heart = try heart()

        window.play(around: heart, burst: burst, palette: .music)

        XCTAssertGreaterThan(window.frame.maxY, screen.frame.maxY)
        XCTAssertEqual(window.frame.midY, heart.midY, accuracy: 1)
    }

    func testASecondHeartStartsTheBurstAgain() throws {
        let heart = try heart()
        window.play(around: heart, burst: burst, palette: .music)
        window.step(to: 0.5)

        window.play(around: heart, burst: burst, palette: .spotify)

        XCTAssertEqual(window.burstView.elapsed, 0)
        XCTAssertEqual(window.burstView.palette.ringStart, Stars.spotifyHeartColor)
        XCTAssertTrue(window.isPlaying)
    }

    func testStopTakesItDownAtOnceAndALateStepDrawsNothing() throws {
        window.play(around: try heart(), burst: burst, palette: .music)
        window.step(to: 0.2)

        window.stop()

        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isPlaying)
        XCTAssertNil(window.burstView.change)
        window.step(to: 0.3)
        XCTAssertFalse(window.isPlaying, "a step after the end doesn't bring it back")
        XCTAssertEqual(window.burstView.elapsed, 0.2)
    }

}
