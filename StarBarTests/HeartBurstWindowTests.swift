//
//  HeartBurstWindowTests.swift
//  StarBarTests
//
//  The see-through window over the menu bar that the heart's burst is drawn in: out of the
//  way of every click, centred on the heart, stepped by the clock, and put away when the burst
//  is over. Each test stops the window, so nothing is left on screen.
//

import XCTest
@testable import StarBar

final class HeartBurstWindowTests: XCTestCase {

    private var clock: FakeClock!
    private var window: HeartBurstWindow!

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        window = HeartBurstWindow(clock: clock)
    }

    override func tearDown() {
        window.stop()
        window = nil
        clock = nil
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

    func testItBurstsCentredOnTheHeartAndPutsItselfAway() throws {
        let heart = try heart()

        window.play(around: heart, burst: burst, palette: .music)

        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.isPlaying)
        XCTAssertEqual(window.burstView.change, .burst)
        XCTAssertGreaterThanOrEqual(window.frame.width / 2, burst.extent, "room for every dot")
        let centre = NSPoint(x: window.frame.minX + window.burstView.centre!.x, y: window.frame.minY + window.burstView.centre!.y)
        XCTAssertEqual(centre.x, heart.midX, accuracy: 0.001)
        XCTAssertEqual(centre.y, heart.midY, accuracy: 0.001)
        XCTAssertEqual(window.frame.origin.x, window.frame.origin.x.rounded(), "in whole points")

        clock.runFrames(for: 0.4)
        XCTAssertEqual(window.burstView.elapsed, 0.4, accuracy: 0.001)
        XCTAssertTrue(window.isVisible)

        clock.runFrames(for: HeartBurst.duration - 0.4 + 0.02)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isPlaying)
        XCTAssertNil(window.burstView.change)
        XCTAssertTrue(clock.pendingRepeating.isEmpty, "no timer left running")
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

    func testAStallPausesTheBurstRatherThanSkippingIt() throws {
        window.play(around: try heart(), burst: burst, palette: .music)
        clock.runFrames(for: 0.1)

        // Half a second with no frame, then one late frame
        clock.advance(by: 0.5)
        clock.fireRepeating()

        XCTAssertTrue(window.isPlaying, "not finished unseen")
        XCTAssertLessThanOrEqual(window.burstView.elapsed, 0.1 + SteppedTimeline.maxStep + 0.001)
    }

    func testASecondHeartStartsTheBurstAgain() throws {
        let heart = try heart()
        window.play(around: heart, burst: burst, palette: .music)
        clock.runFrames(for: 0.5)

        window.play(around: heart, burst: burst, palette: .spotify)

        XCTAssertEqual(window.burstView.elapsed, 0)
        XCTAssertEqual(window.burstView.palette.ringStart, Stars.spotifyHeartColor)
        XCTAssertEqual(clock.pendingRepeating.count, 1, "one burst at a time")
        clock.runFrames(for: 0.5)
        XCTAssertTrue(window.isPlaying, "the second runs its whole length")
    }

    func testStopTakesItDownAtOnce() throws {
        window.play(around: try heart(), burst: burst, palette: .music)
        clock.runFrames(for: 0.2)

        window.stop()

        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isPlaying)
        XCTAssertTrue(clock.pendingRepeating.isEmpty)
    }

}
