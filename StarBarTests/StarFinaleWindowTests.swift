//
//  StarFinaleWindowTests.swift
//  StarBarTests
//
//  The see-through window over the menu bar that the five-star finale is drawn in: out of the
//  way of every click, laid around the first star, drawn where it is stepped to, and taken
//  down at once. It has no clock of its own; `MenuBarStarFlourishTests` covers it stepping
//  with the stars' flourish. Each test stops the window, so nothing is left on screen.
//

import XCTest
@testable import StarBar

final class StarFinaleWindowTests: XCTestCase {

    private var window: StarFinaleWindow!

    override func setUp() {
        super.setUp()
        window = StarFinaleWindow()
    }

    override func tearDown() {
        window.stop()
        window = nil
        super.tearDown()
    }

    private let finale = StarFinale.menuBar(starSize: 16, spacing: 4, stagger: 0.05)

    /// The first star's centre, 12 points below the top of the main screen as on a 24 point
    /// menu bar, and far enough from the screen's left edge for the fan
    private func firstStar() throws -> NSPoint {
        let screen = try XCTUnwrap(NSScreen.main)
        return NSPoint(x: screen.frame.midX.rounded() + 0.5, y: screen.frame.maxY - 12.764)
    }

    private func drawnCentre() -> NSPoint {
        return NSPoint(x: window.frame.minX + window.finaleView.origin.x, y: window.frame.minY + window.finaleView.origin.y)
    }

    func testTheWindowNeverTakesFocusOrClicks() {
        XCTAssertTrue(window.ignoresMouseEvents, "a second rating still reaches the stars")
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.level, MenuBarOverlayWindow.windowLevel)
        XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.statusBar.rawValue, "over the menu bar's items")
        XCTAssertLessThan(window.level.rawValue, NSWindow.Level.popUpMenu.rawValue, "under an open menu")
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.isVisible, "nothing on screen until a song is given five stars")
        XCTAssertFalse(window.isPlaying)
    }

    /// The heart's burst is drawn in the same kind of window
    func testTheHeartsBurstWindowIsOneOfTheSame() {
        let burst = HeartBurstWindow()
        XCTAssertEqual(burst.level, window.level)
        XCTAssertEqual(burst.collectionBehavior, window.collectionBehavior)
        XCTAssertEqual(burst.styleMask, window.styleMask)
        XCTAssertTrue(burst.ignoresMouseEvents)
    }

    func testItIsLaidAroundTheFirstStarAndDrawsWhereItIsStepped() throws {
        let centre = try firstStar()

        window.play(finale, firstStarAt: centre)

        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.isPlaying)
        XCTAssertEqual(window.finaleView.finale, finale)
        XCTAssertEqual(window.finaleView.elapsed, 0, "its first frame, which is empty")
        XCTAssertEqual(drawnCentre().x, centre.x, accuracy: 0.001)
        XCTAssertEqual(drawnCentre().y, centre.y, accuracy: 0.001)
        XCTAssertEqual(window.frame.origin.x, window.frame.origin.x.rounded(), "in whole points")
        XCTAssertEqual(window.frame.origin.y, window.frame.origin.y.rounded())
        XCTAssertTrue(window.frame.contains(finale.bounds.offsetBy(dx: centre.x, dy: centre.y)), "room for every small star")
        XCTAssertEqual(window.finaleView.frame.size, window.frame.size, "the finale fills the window")

        window.step(to: 0.4)
        XCTAssertEqual(window.finaleView.elapsed, 0.4)
        XCTAssertTrue(window.isVisible)
    }

    /// The small stars fan down, so the window hangs below the stars and stays under the
    /// screen's top edge, where the heart's burst has to reach above it
    func testTheWindowHangsBelowTheStars() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let centre = try firstStar()

        window.play(finale, firstStarAt: centre)

        XCTAssertLessThanOrEqual(window.frame.maxY, screen.frame.maxY)
        XCTAssertLessThan(window.frame.maxY - centre.y, 7, "barely above the stars' centres")
        XCTAssertGreaterThan(centre.y - window.frame.minY, 30, "and about 30 points below them")
        XCTAssertGreaterThan(window.frame.maxX - centre.x, 4 * finale.pitch, "past the last star")
        XCTAssertLessThan(window.frame.minX, centre.x - 16, "and out to the left of the first")
    }

    func testASecondFinaleStartsAgainWhereItIsPut() throws {
        let centre = try firstStar()
        window.play(finale, firstStarAt: centre)
        window.step(to: 0.5)

        let moved = NSPoint(x: centre.x - 40, y: centre.y)
        window.play(finale, firstStarAt: moved)

        XCTAssertEqual(window.finaleView.elapsed, 0)
        XCTAssertTrue(window.isPlaying)
        XCTAssertEqual(drawnCentre().x, moved.x, accuracy: 0.001)
    }

    func testStopTakesItDownAtOnceAndALateStepDrawsNothing() throws {
        window.play(finale, firstStarAt: try firstStar())
        window.step(to: 0.2)

        window.stop()

        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isPlaying)
        XCTAssertNil(window.finaleView.finale)
        window.step(to: 0.3)
        XCTAssertFalse(window.isPlaying, "a step after the end doesn't bring it back")
        XCTAssertEqual(window.finaleView.elapsed, 0.2)
    }

}
