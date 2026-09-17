//
//  TrackAnnouncementPanelTests.swift
//  StarBarTests
//
//  The strip's window: click-through and never key, placed on the pointer's screen, sliding
//  or fading, taken down when the screens change. Runs with a zero slide duration so nothing
//  waits, and hides the panel afterwards so no strip is left on screen.
//

import XCTest
@testable import StarBar

final class TrackAnnouncementPanelTests: XCTestCase {

    private var panel: TrackAnnouncementPanel!
    private var mouse = NSPoint.zero

    override func setUp() {
        super.setUp()
        mouse = NSScreen.main.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
        panel = TrackAnnouncementPanel(
            slideDuration: 0,
            screens: { NSScreen.screens },
            mouseLocation: { [unowned self] in self.mouse }
        )
    }

    override func tearDown() {
        panel.orderOut(nil)
        panel = nil
        super.tearDown()
    }

    private let sample = TrackAnnouncement(identity: "1", title: "Title", artist: "Artist", album: "Album")

    func testPanelNeverTakesFocusOrClicks() {
        XCTAssertTrue(panel.ignoresMouseEvents)
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        XCTAssertEqual(panel.level.rawValue, dockLevel - 1, "one step below the Dock, so a side Dock draws over the strip")
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.floating.rawValue)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    func testShowPlacesThePanelOnThePointersScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)

        panel.show(sample, reduceMotion: false, reduceTransparency: false)

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.phase, .shown)
        let scale = TrackAnnouncementLayout.scale(forScreenHeight: screen.frame.height)
        XCTAssertEqual(panel.scale, scale)
        XCTAssertEqual(panel.stripView.scale, scale)
        XCTAssertEqual(panel.frame, TrackAnnouncementPlacement.panelFrame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, scale: scale))
        XCTAssertEqual(panel.stripView.frame.origin, .zero)
        XCTAssertEqual(panel.stripView.frame.width, panel.frame.width)
        XCTAssertEqual(panel.stripView.leadingInset, screen.visibleFrame.minX - screen.frame.minX)
        XCTAssertEqual(panel.stripView.trailingInset, screen.frame.maxX - screen.visibleFrame.maxX)
        XCTAssertEqual(panel.lastTransition, .slide)
    }

    func testReduceMotionFadesInstead() {
        panel.show(sample, reduceMotion: true, reduceTransparency: false)

        XCTAssertEqual(panel.lastTransition, .fade)
        XCTAssertEqual(panel.stripView.frame.origin, .zero)
        XCTAssertEqual(panel.stripView.alphaValue, 1)
    }

    func testReduceTransparencyMakesTheStripOpaque() {
        panel.show(sample, reduceMotion: false, reduceTransparency: true)
        XCTAssertEqual(panel.stripView.backgroundAlpha, 1)

        panel.hide()
        panel.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(panel.stripView.backgroundAlpha, TrackAnnouncementLayout.backgroundAlpha)
    }

    func testSecondShowSwapsTheContentAndKeepsTheFrame() {
        panel.show(sample, reduceMotion: false, reduceTransparency: false)
        let frame = panel.frame
        let next = TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album")

        panel.show(next, reduceMotion: false, reduceTransparency: false)

        XCTAssertEqual(panel.stripView.announcement, next)
        XCTAssertEqual(panel.frame, frame)
        XCTAssertEqual(panel.phase, .shown)
    }

    func testTheScreenIsNotRepickedWhileVisible() throws {
        let screens = NSScreen.screens
        let last = try XCTUnwrap(screens.last)
        panel.show(sample, reduceMotion: false, reduceTransparency: false)
        let frame = panel.frame

        mouse = NSPoint(x: last.frame.midX, y: last.frame.midY)
        panel.show(sample, reduceMotion: false, reduceTransparency: false)

        XCTAssertEqual(panel.frame, frame)
    }

    func testHideTakesThePanelDown() {
        panel.show(sample, reduceMotion: false, reduceTransparency: false)
        panel.hide()

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.phase, .hidden)
        XCTAssertEqual(panel.stripView.frame.origin, TrackAnnouncementPlacement.stripOrigin(shown: false, scale: panel.scale))
    }

    func testHideWhileHiddenDoesNothing() {
        panel.hide()

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.phase, .hidden)
        XCTAssertNil(panel.lastTransition)
    }

    func testScreenChangeTakesThePanelDown() {
        panel.show(sample, reduceMotion: false, reduceTransparency: false)

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.phase, .hidden)
    }

    /// The slide, stepped by a fake clock: part-way up after half the duration, on screen
    /// part-way down on the way out, and only then ordered out
    func testSlideInAndOutStepWithTheClock() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, clock: clock)
        defer { animated.orderOut(nil) }

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.phase, .slidingIn)
        // The scale, and so the hidden offset, is known once the panel has picked a screen
        let hiddenScaled = TrackAnnouncementPlacement.stripOrigin(shown: false, scale: animated.scale).y
        XCTAssertEqual(animated.stripView.frame.origin.y, hiddenScaled)

        clock.advance(by: 0.15)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.frame.origin.y, hiddenScaled / 2, accuracy: 0.5, "half way at half time on an ease-in-out curve")
        XCTAssertEqual(animated.phase, .slidingIn)

        clock.advance(by: 0.2)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
        XCTAssertEqual(animated.phase, .shown)

        animated.hide()
        XCTAssertEqual(animated.phase, .slidingOut)
        clock.advance(by: 0.1)
        clock.fireRepeating()
        XCTAssertTrue(animated.isVisible, "the panel stays up while the strip slides down")
        XCTAssertLessThan(animated.stripView.frame.origin.y, 0)
        XCTAssertGreaterThan(animated.stripView.frame.origin.y, hiddenScaled)

        clock.advance(by: 0.3)
        clock.fireRepeating()
        XCTAssertFalse(animated.isVisible)
        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertEqual(animated.stripView.frame.origin.y, hiddenScaled)
    }

    func testShowDuringSlideOutTurnsRoundFromWhereItIs() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.advance(by: 0.5)
        clock.fireRepeating()
        animated.hide()
        clock.advance(by: 0.1)
        clock.fireRepeating()
        let midway = animated.stripView.frame.origin.y

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.phase, .slidingIn)
        XCTAssertEqual(animated.stripView.frame.origin.y, midway, "no jump when turning round")
        clock.advance(by: 0.5)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
        XCTAssertTrue(animated.isVisible)
    }

    func testFadeStepsAlphaWithTheClock() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, clock: clock)
        defer { animated.orderOut(nil) }

        animated.show(sample, reduceMotion: true, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.alphaValue, 0)
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
        clock.advance(by: 0.15)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.alphaValue, 0.5, accuracy: 0.01)
        clock.advance(by: 0.2)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.alphaValue, 1)
        XCTAssertEqual(animated.phase, .shown)
    }

    func testStripHasAnAccessibilityLabel() {
        panel.show(sample, reduceMotion: false, reduceTransparency: false)

        XCTAssertEqual(panel.stripView.accessibilityLabel(), "Now playing: Title by Artist")
    }

    func testStripDrawsWithAndWithoutArtwork() {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        XCTAssertFalse(view.dataWithPDF(inside: view.bounds).isEmpty)

        let image = NSImage(size: CGSize(width: 300, height: 200), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        view.announcement = TrackAnnouncement(identity: "2", title: "T", artist: "", album: "", artwork: image)
        XCTAssertFalse(view.dataWithPDF(inside: view.bounds).isEmpty)
    }

}
