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

    private var readKnobs: (() -> TrackAnnouncementGlassKnobs)!
    private var readSeeThroughKnobs: (() -> TrackAnnouncementSeeThroughKnobs)!
    private var seeThroughKnobs = TrackAnnouncementSeeThroughKnobs()
    private var readSleeveKnobs: (() -> TrackAnnouncementSleeveKnobs)!
    /// The flat artwork, unless a test says otherwise: several tests count the repeating
    /// timers, and the sleeve steps on one of its own
    private var sleeveKnobs = TrackAnnouncementSleeveKnobs(breakout: false, tilt: false)
    /// No key pressed for a long while, unless a test says otherwise
    private var keys = KeyboardActivity(secondsSinceKeyDown: 600, commandKeysHeld: false)

    override func setUp() {
        super.setUp()
        // The tests are hosted in the app, whose defaults may carry the glass and see-through
        // experiment knobs; read fixed values instead
        readKnobs = TrackAnnouncementGlassKnobs.read
        TrackAnnouncementGlassKnobs.read = { TrackAnnouncementGlassKnobs() }
        readSeeThroughKnobs = TrackAnnouncementSeeThroughKnobs.read
        seeThroughKnobs = TrackAnnouncementSeeThroughKnobs()
        TrackAnnouncementSeeThroughKnobs.read = { [unowned self] in self.seeThroughKnobs }
        readSleeveKnobs = TrackAnnouncementSleeveKnobs.read
        sleeveKnobs = TrackAnnouncementSleeveKnobs(breakout: false, tilt: false)
        TrackAnnouncementSleeveKnobs.read = { [unowned self] in self.sleeveKnobs }
        mouse = NSScreen.main.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
        panel = TrackAnnouncementPanel(
            slideDuration: 0,
            screens: { NSScreen.screens },
            mouseLocation: { [unowned self] in self.mouse },
            keyboard: { [unowned self] in self.keys }
        )
    }

    override func tearDown() {
        panel.orderOut(nil)
        panel = nil
        TrackAnnouncementGlassKnobs.read = readKnobs
        TrackAnnouncementSeeThroughKnobs.read = readSeeThroughKnobs
        TrackAnnouncementSleeveKnobs.read = readSleeveKnobs
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
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary), "may join a full-screen Space rather than switch Spaces")
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
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
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

    /// A cover that comes after the strip went up (Spotify's, or Apple's for a song Music had
    /// none for) cross-fades from the placeholder, stepped by the clock
    func testACoverThatArrivesLaterFadesIn() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0, artworkFadeDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.artworkFade, 1)

        animated.refresh(TrackAnnouncement(copying: sample, artwork: NSImage(size: NSSize(width: 10, height: 10))))
        XCTAssertEqual(animated.stripView.artworkFade, 0, "the placeholder still shows on the first frame")
        clock.advance(by: 0.15)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.artworkFade, 0.5, accuracy: 0.01, "half way at half time on an ease-in-out curve")
        clock.advance(by: 0.2)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.artworkFade, 1)
        // Done: more frames change nothing
        clock.advance(by: 1)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.artworkFade, 1)
    }

    func testOnlyALateCoverForTheSameSongFades() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0, artworkFadeDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        let cover = NSImage(size: NSSize(width: 10, height: 10))

        // A song whose cover came with it shows it at once
        animated.show(TrackAnnouncement(copying: sample, artwork: cover), reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.artworkFade, 1)
        // and a change to its stars doesn't fade it again
        animated.refresh(TrackAnnouncement(identity: "1", title: "Title", artist: "Artist", album: "Album", rating: 80, artwork: cover))
        XCTAssertEqual(animated.stripView.artworkFade, 1)

        // Another song's arrival mid-fade shows its own artwork at once
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        animated.refresh(TrackAnnouncement(copying: sample, artwork: cover))
        XCTAssertEqual(animated.stripView.artworkFade, 0)
        animated.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album", artwork: cover), reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.artworkFade, 1)
        clock.advance(by: 0.1)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.artworkFade, 1, "the old song's fade doesn't carry on over the new one")
    }

    func testShowDuringSlideOutTurnsRoundFromWhereItIs() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
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

    func testHideWhileSlidingInTurnsRound() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.advance(by: 0.1)
        clock.fireRepeating()
        let midway = animated.stripView.frame.origin.y

        animated.hide()
        XCTAssertEqual(animated.phase, .slidingOut)
        XCTAssertEqual(animated.stripView.frame.origin.y, midway)
        clock.advance(by: 0.5)
        clock.fireRepeating()
        XCTAssertFalse(animated.isVisible)
        XCTAssertEqual(animated.phase, .hidden)
    }

    func testChangingTransitionMidTurnRoundSettlesTheOtherProperty() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.advance(by: 0.5)
        clock.fireRepeating()
        animated.hide()
        clock.advance(by: 0.1)
        clock.fireRepeating()
        XCTAssertLessThan(animated.stripView.frame.origin.y, 0)

        // Reduce Motion was turned on meanwhile: the fade must not leave the strip half down
        animated.show(sample, reduceMotion: true, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
        clock.advance(by: 0.5)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.alphaValue, 1)
        XCTAssertEqual(animated.phase, .shown)
    }

    func testStaleTickAfterAScreenChangeDoesNothing() {
        // With nothing to see through there is no watcher, so the one repeating timer is the slide's
        seeThroughKnobs.peephole = false
        seeThroughKnobs.typingWindow = false
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(clock.timers.filter { $0.repeats }.count, 1)
        let staleTick = try! XCTUnwrap(clock.timers.last { $0.repeats })

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        XCTAssertFalse(staleTick.isValid)
        XCTAssertEqual(animated.phase, .hidden)

        clock.advance(by: 0.5)
        staleTick.action()

        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertFalse(animated.isVisible)
    }

    func testFadeStepsAlphaWithTheClock() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
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

        XCTAssertEqual(panel.stripView.accessibilityLabel(), "Now playing: Title by Artist. No rating")
    }

    func testRefreshRedrawsOnlyWhileUp() {
        let rated = TrackAnnouncement(identity: "1", title: "Title", artist: "Artist", album: "Album", rating: 80, isFavorited: true)

        panel.refresh(rated)
        XCTAssertFalse(panel.isVisible, "a refresh never shows a hidden strip")
        XCTAssertNotEqual(panel.stripView.announcement, rated)

        panel.show(sample, reduceMotion: false, reduceTransparency: false)
        panel.refresh(rated)
        XCTAssertEqual(panel.stripView.announcement, rated)
        XCTAssertEqual(panel.phase, .shown)
    }

    // MARK: - Seeing through

    /// A panel whose see-through watcher runs on a fake clock, with the strip already up
    private func seeThroughPanel(_ clock: FakeClock) -> TrackAnnouncementPanel {
        let seeThrough = TrackAnnouncementPanel(
            slideDuration: 0,
            screens: { NSScreen.screens },
            mouseLocation: { [unowned self] in self.mouse },
            keyboard: { [unowned self] in self.keys },
            clock: clock
        )
        seeThrough.show(sample, reduceMotion: false, reduceTransparency: false)
        return seeThrough
    }

    /// The middle of the strip, on screen
    private func stripCentre(of panel: TrackAnnouncementPanel) -> NSPoint {
        let strip = panel.stripView.frame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        return NSPoint(x: strip.midX, y: strip.midY)
    }

    /// How far open the typing window is
    private func windowProgress(_ panel: TrackAnnouncementPanel) -> CGFloat {
        return panel.stripView.typingWindow?.progress ?? 0
    }

    private func tick(_ clock: FakeClock, _ seconds: TimeInterval = 1.0 / 60.0) {
        clock.advance(by: seconds)
        clock.fireRepeating()
    }

    func testThePointerOverTheStripCutsAHoleThatFollowsIt() throws {
        // Far above every screen, not mid-screen: on CI's 1024 by 768 screens the middle is
        // only about 220 points above the strip, inside the hole's reach. Off every screen,
        // the panel falls back to the main one.
        mouse = NSPoint(x: 0, y: 100_000)
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }
        XCTAssertNil(seeThrough.stripView.peephole, "the pointer starts well clear of the strip")

        mouse = stripCentre(of: seeThrough)
        tick(clock)
        let hole = try XCTUnwrap(seeThrough.stripView.peephole)
        XCTAssertEqual(hole.centre.x, seeThrough.stripView.bounds.midX, accuracy: 0.001)
        XCTAssertEqual(hole.centre.y, seeThrough.stripView.bounds.midY, accuracy: 0.001)
        XCTAssertEqual(hole.radius, TrackAnnouncementSeeThrough.peepholeRadius * seeThrough.scale, "scaled with the strip")
        XCTAssertEqual(hole.feather, TrackAnnouncementSeeThrough.peepholeFeather * seeThrough.scale)

        mouse.x += 200
        tick(clock)
        XCTAssertEqual(seeThrough.stripView.peephole?.centre.x ?? 0, seeThrough.stripView.bounds.midX + 200, accuracy: 0.001)

        mouse.y += 1000
        tick(clock)
        XCTAssertNil(seeThrough.stripView.peephole, "gone once the pointer leaves")
    }

    func testTypingOpensTheWindowAndItClosesAfterAPause() {
        let clock = FakeClock()
        var keyDownAt = clock.now().addingTimeInterval(-600)
        func step(_ seconds: TimeInterval) {
            clock.advance(by: seconds)
            keys = KeyboardActivity(secondsSinceKeyDown: clock.now().timeIntervalSince(keyDownAt), commandKeysHeld: false)
            clock.fireRepeating()
        }
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }
        XCTAssertEqual(windowProgress(seeThrough), 0)

        keyDownAt = clock.now()
        step(0.075)
        XCTAssertEqual(windowProgress(seeThrough), 0.5, accuracy: 0.01, "half open")
        step(0.1)
        XCTAssertEqual(windowProgress(seeThrough), 1)

        step(1.2)
        XCTAssertEqual(windowProgress(seeThrough), 1, "1.375 s after the key: still inside the pause")
        step(0.2)
        XCTAssertEqual(windowProgress(seeThrough), 0.5, accuracy: 0.01, "closing")
        step(0.3)
        XCTAssertEqual(windowProgress(seeThrough), 0)
    }

    func testARatingShortcutLeavesTheBackgroundAlone() {
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }

        keys = KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: true)
        tick(clock)
        tick(clock)

        XCTAssertEqual(windowProgress(seeThrough), 0)
    }

    func testTheStripArrivesOpenIfTheUserIsAlreadyTyping() {
        keys = KeyboardActivity(secondsSinceKeyDown: 0.2, commandKeysHeld: false)
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }

        XCTAssertEqual(windowProgress(seeThrough), 1, "no flash of blur over the text box being typed in")
    }

    func testHidingStopsWatchingAndRestoresTheBackground() throws {
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }
        mouse = stripCentre(of: seeThrough)
        keys = KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false)
        tick(clock)
        XCTAssertNotNil(seeThrough.stripView.peephole)
        XCTAssertGreaterThan(windowProgress(seeThrough), 0)
        let watcher = try XCTUnwrap(clock.timers.last { $0.repeats && $0.isValid })

        seeThrough.hide()

        XCTAssertEqual(seeThrough.phase, .hidden)
        XCTAssertFalse(watcher.isValid)
        XCTAssertNil(seeThrough.stripView.peephole)
        XCTAssertEqual(windowProgress(seeThrough), 0, "the next song starts with the whole background")
        watcher.action()
        XCTAssertNil(seeThrough.stripView.peephole, "a stale tick does nothing")
    }

    func testAScreenChangeStopsWatchingAndRestoresTheBackground() throws {
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }
        mouse = stripCentre(of: seeThrough)
        keys = KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false)
        tick(clock)
        XCTAssertNotNil(seeThrough.stripView.peephole)
        let watcher = try XCTUnwrap(clock.timers.last { $0.repeats && $0.isValid })

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)

        XCTAssertFalse(watcher.isValid)
        XCTAssertNil(seeThrough.stripView.peephole)
        XCTAssertEqual(windowProgress(seeThrough), 0)
    }

    func testTheShortcutThatBroughtTheStripUpDoesNotClearIt() {
        // Command-Right Arrow skipped the song 0.3 s ago, and Command came up since
        keys = KeyboardActivity(secondsSinceKeyDown: 0.3, commandKeysHeld: false, secondsSinceModifierChange: 0.2)
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }

        XCTAssertEqual(windowProgress(seeThrough), 0)
        keys.secondsSinceKeyDown += 1.0 / 60.0
        keys.secondsSinceModifierChange += 1.0 / 60.0
        tick(clock)
        XCTAssertEqual(windowProgress(seeThrough), 0, "and reading the same key again changes nothing")
    }

    func testReduceTransparencyKeepsTheWholeBackground() {
        let clock = FakeClock()
        let seeThrough = TrackAnnouncementPanel(slideDuration: 0, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { seeThrough.orderOut(nil) }
        keys = KeyboardActivity(secondsSinceKeyDown: 0.1, commandKeysHeld: false)

        seeThrough.show(sample, reduceMotion: false, reduceTransparency: true)
        mouse = stripCentre(of: seeThrough)
        tick(clock)

        XCTAssertTrue(clock.timers.filter { $0.repeats && $0.isValid }.isEmpty, "nothing watches")
        XCTAssertNil(seeThrough.stripView.peephole)
        XCTAssertNil(seeThrough.stripView.typingWindow)
    }

    func testTurningReduceTransparencyOnWhileTheStripIsUpClosesEverything() throws {
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }
        mouse = stripCentre(of: seeThrough)
        keys = KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false)
        tick(clock)
        XCTAssertNotNil(seeThrough.stripView.peephole)
        XCTAssertNotNil(seeThrough.stripView.typingWindow)
        let watcher = try XCTUnwrap(clock.timers.first { $0.repeats && $0.isValid })

        // The next song arrives with the setting now on
        seeThrough.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album"), reduceMotion: false, reduceTransparency: true)

        XCTAssertFalse(watcher.isValid)
        XCTAssertNil(seeThrough.stripView.peephole)
        XCTAssertNil(seeThrough.stripView.typingWindow)
    }

    func testTheKnobsTurnEachPartOffAndWithBothOffNothingWatches() {
        seeThroughKnobs.peephole = false
        seeThroughKnobs.typingWindow = false
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }

        XCTAssertTrue(clock.timers.filter { $0.repeats && $0.isValid }.isEmpty, "no ticking at the display's rate for nothing")
        mouse = stripCentre(of: seeThrough)
        keys = KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false)
        tick(clock)

        XCTAssertNil(seeThrough.stripView.peephole)
        XCTAssertEqual(windowProgress(seeThrough), 0)
    }

    func testOnlyTheHoleCanBeOn() {
        seeThroughKnobs.typingWindow = false
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }

        mouse = stripCentre(of: seeThrough)
        keys = KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false)
        tick(clock)

        XCTAssertNotNil(seeThrough.stripView.peephole)
        XCTAssertEqual(windowProgress(seeThrough), 0)
    }

    /// A timed panel: the watcher and the slide share the fake clock
    private func timedPanel(_ clock: FakeClock) -> TrackAnnouncementPanel {
        return TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
    }

    func testASlideOutThatFinishesStopsWatching() throws {
        let clock = FakeClock()
        let animated = timedPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 0.5)
        XCTAssertEqual(animated.phase, .shown)
        mouse = stripCentre(of: animated)
        tick(clock)
        XCTAssertNotNil(animated.stripView.peephole)
        let watcher = try XCTUnwrap(clock.timers.first { $0.repeats && $0.isValid })

        animated.hide()
        tick(clock, 0.5)

        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertFalse(watcher.isValid)
        XCTAssertNil(animated.stripView.peephole)
    }

    func testTurningRoundDuringTheSlideOutKeepsOneWatcher() {
        let clock = FakeClock()
        let animated = timedPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 0.5)
        XCTAssertEqual(clock.timers.filter { $0.repeats && $0.isValid }.count, 1, "the watcher, the slide done")

        animated.hide()
        tick(clock, 0.1)
        animated.show(sample, reduceMotion: false, reduceTransparency: false)

        XCTAssertEqual(animated.phase, .slidingIn)
        XCTAssertEqual(clock.timers.filter { $0.repeats && $0.isValid }.count, 2, "the same watcher, and the new slide")
    }

    func testTheHoleMovesWithTheStripWhileItSlides() throws {
        let clock = FakeClock()
        let animated = timedPanel(clock)
        defer { animated.orderOut(nil) }
        // The pointer where the middle of the strip will be once it is up
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        let shownCentre = NSPoint(x: animated.frame.minX + animated.stripView.bounds.midX, y: animated.frame.minY + animated.stripView.bounds.midY)
        mouse = shownCentre
        let slideTick = try XCTUnwrap(clock.timers.last { $0.repeats && $0.isValid })

        // Only the slide ticks: the hole must follow the strip without the watcher
        clock.advance(by: 0.2)
        slideTick.action()

        let stripY = animated.stripView.frame.minY
        XCTAssertLessThan(stripY, 0, "still sliding")
        let hole = try XCTUnwrap(animated.stripView.peephole)
        XCTAssertEqual(hole.centre.y, shownCentre.y - animated.frame.minY - stripY, accuracy: 0.001)
    }

    func testTheHoleAndTheTypingWindowTakeTheBackgroundButNotTheText() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 1600, height: 96))
        view.style = .blur
        let surface = try XCTUnwrap(view.subviews.first as? TrackAnnouncementSurfaceView)
        let content = try XCTUnwrap(view.subviews.last as? TrackAnnouncementContentView)
        XCTAssertTrue(surface.backdropView is NSVisualEffectView, "the blur is in the background's container")
        XCTAssertNil(surface.layer?.mask, "no mask without a hole")
        XCTAssertNil(surface.typingWindowMask)

        view.peephole = TrackAnnouncementPeephole(centre: CGPoint(x: 300, y: 48), radius: 40, feather: 10)
        view.setTypingWindow(radius: 360, feather: 144, progress: 1)
        XCTAssertTrue(surface.layer?.mask is TrackAnnouncementPeepholeMask)
        XCTAssertTrue(surface.typingWindowMask is TrackAnnouncementTypingMask, "on a view of its own, so the two holes multiply")
        XCTAssertNil(content.layer?.mask, "the text stays over both")

        view.peephole = nil
        view.setTypingWindow(radius: 360, feather: 144, progress: 0)
        XCTAssertNil(surface.layer?.mask)
        XCTAssertNil(surface.typingWindowMask)
    }

    func testTheTypingWindowOpensInTheMiddleAndKeepsTheTextsBackground() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 2000, height: 104))
        view.setTypingWindow(radius: 360, feather: 144, centreHeight: 90, progress: 0.5)

        let window = try XCTUnwrap(view.typingWindow)
        XCTAssertEqual(window.hole.centre, CGPoint(x: 1000, y: 194), "across the middle, above the top edge, so the strip gets a concave scoop")
        XCTAssertEqual(window.hole.radius, 360)
        XCTAssertEqual(window.progress, 0.5)
        // "Title", "Artist", "Album" and the stars end well short of the middle, and the kept
        // background ends a margin after them
        let text = TrackAnnouncementLayout.frames(in: view.bounds.size).title
        XCTAssertGreaterThan(window.kept.untilX, text.minX + TrackAnnouncementSeeThrough.keepMargin)
        XCTAssertLessThan(window.kept.untilX, 400)

        // A long title covers more, and keeps more
        view.announcement = TrackAnnouncement(identity: "2", title: "Calling My Name (Live New Orleans '89), Extended Version", artist: "Daniel Lanois", album: "Album")
        XCTAssertGreaterThan(try XCTUnwrap(view.typingWindow).kept.untilX, window.kept.untilX + 100)
    }

    func testThePointersHoleKeepsSomeOfTheTextsBackground() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 2000, height: 104))
        view.setTypingWindow(radius: 360, feather: 144, centreHeight: 90, progress: 1)
        let keep = try XCTUnwrap(view.peepholeKeep)
        XCTAssertEqual(keep.untilX, try XCTUnwrap(view.typingWindow).kept.untilX, "the same part of the strip the typing window keeps")
        XCTAssertEqual(keep.feather, TrackAnnouncementSeeThrough.keepFeather)
        XCTAssertEqual(keep.opacity, 0.3)

        // A long title covers more, and keeps more, without the typing window open
        view.setTypingWindow(radius: 0, feather: 0, progress: 0)
        view.announcement = TrackAnnouncement(identity: "2", title: "Calling My Name (Live New Orleans '89), Extended Version", artist: "Daniel Lanois", album: "Album")
        XCTAssertGreaterThan(try XCTUnwrap(view.peepholeKeep).untilX, keep.untilX + 100)

        view.peepholeKeepOpacity = 0
        XCTAssertNil(view.peepholeKeep, "at 0 the hole clears everything")
    }

    func testThePanelGivesTheStripTheKnobsKeptBackground() throws {
        seeThroughKnobs.peepholeKeep = 0.35
        mouse = NSPoint(x: 0, y: 100_000)
        let clock = FakeClock()
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }

        mouse = stripCentre(of: seeThrough)
        tick(clock)
        XCTAssertNotNil(seeThrough.stripView.peephole)
        XCTAssertEqual(try XCTUnwrap(seeThrough.stripView.peepholeKeep).opacity, 0.35, accuracy: 1e-6)
        let surface = try XCTUnwrap(seeThrough.stripView.subviews.first as? TrackAnnouncementSurfaceView)
        let mask = try XCTUnwrap(surface.layer?.mask as? TrackAnnouncementPeepholeMask)
        XCTAssertEqual(try XCTUnwrap(mask.keptLayers).solid.opacity, 0.35, accuracy: 1e-6, "in the mask the hole cuts")
    }

    /// Where the kept background ends for `announcement` on a wide strip at scale 1
    private func keepUntilX(_ announcement: TrackAnnouncement) throws -> CGFloat {
        let view = TrackAnnouncementView(announcement: announcement, frame: NSRect(x: 0, y: 0, width: 2000, height: 104))
        view.setTypingWindow(radius: 360, feather: 144, centreHeight: 90, progress: 1)
        return try XCTUnwrap(view.typingWindow).kept.untilX
    }

    func testEveryLineCountsTowardsTheKeptBackground() throws {
        let short = try keepUntilX(TrackAnnouncement(identity: "1", title: "T", artist: "A", album: "B"))
        let longArtist = try keepUntilX(TrackAnnouncement(identity: "1", title: "T", artist: "The Artist Formerly Known As Someone Else Entirely", album: "B"))
        let longAlbum = try keepUntilX(TrackAnnouncement(identity: "1", title: "T", artist: "A", album: "Calling My Name (Live New Orleans '89), Deluxe Edition"))
        let cannotRate = try keepUntilX(TrackAnnouncement(identity: "1", title: "T", artist: "A", album: "B", canRate: false))

        XCTAssertGreaterThan(longArtist, short + 100, "the artist line")
        XCTAssertGreaterThan(longAlbum, short + 100, "the album line")
        XCTAssertGreaterThan(cannotRate, short + 50, "the add-it-to-rate-it line is wider than the stars")
        // The stars row alone: five 12 pt stars and a heart with 3 pt spacing, past the text's edge
        let textX = TrackAnnouncementLayout.frames(in: CGSize(width: 2000, height: 104)).title.minX
        XCTAssertGreaterThanOrEqual(short, textX + 5 * 12 + 7 * 3 + 12 + TrackAnnouncementSeeThrough.keepMargin - 1, "the stars and heart")
    }

    func testAPointerOnAnotherDisplayOpensNoHole() throws {
        let clock = FakeClock()
        mouse = NSPoint(x: 0, y: 100_000)
        let seeThrough = seeThroughPanel(clock)
        defer { seeThrough.orderOut(nil) }
        let screen = try XCTUnwrap(seeThrough.screen ?? NSScreen.main)

        // Just below the strip's screen: close enough to reach the strip, but on another display
        mouse = NSPoint(x: stripCentre(of: seeThrough).x, y: screen.frame.minY - 10)
        tick(clock)

        XCTAssertNil(seeThrough.stripView.peephole)
    }

    func testASongArrivingWhileUpWatchesAgainOnceReduceTransparencyIsOff() {
        let clock = FakeClock()
        let seeThrough = TrackAnnouncementPanel(slideDuration: 0, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { seeThrough.orderOut(nil) }
        seeThrough.show(sample, reduceMotion: false, reduceTransparency: true)
        XCTAssertTrue(clock.timers.filter { $0.repeats && $0.isValid }.isEmpty)

        seeThrough.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album"), reduceMotion: false, reduceTransparency: false)
        mouse = stripCentre(of: seeThrough)
        tick(clock)

        XCTAssertEqual(clock.timers.filter { $0.repeats && $0.isValid }.count, 1)
        XCTAssertNotNil(seeThrough.stripView.peephole)
    }

    func testTheMaskCoversTheGlassWhereItHangsBelowTheStrip() throws {
        try skipWithoutLiquidGlass()
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.style = .glass
        let surface = try XCTUnwrap(view.subviews.first as? TrackAnnouncementSurfaceView)

        view.peephole = TrackAnnouncementPeephole(centre: CGPoint(x: 300, y: 48), radius: 40, feather: 10)

        let mask = try XCTUnwrap(surface.layer?.mask)
        XCTAssertEqual(mask.frame, view.bounds.union(view.backdropFrame))
        XCTAssertLessThan(mask.frame.minY, 0)
    }

    // MARK: - Styles

    func testClassicStyleHasNoBackdrop() {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))

        XCTAssertEqual(view.style, .classic)
        XCTAssertNil(view.backdropView)
        XCTAssertEqual(view.tintAlpha, TrackAnnouncementLayout.backgroundAlpha)
        XCTAssertEqual(view.tintColor, .black)
    }

    func testBlurStyleAddsAnActiveBehindWindowBlurUnderTheContent() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))

        view.style = .blur

        let blur = try XCTUnwrap(view.backdropView as? NSVisualEffectView)
        XCTAssertEqual(blur.blendingMode, .behindWindow)
        XCTAssertEqual(blur.state, .active, "the panel is never active, so the blur must not follow it")
        XCTAssertEqual(blur.frame, view.bounds)
        let surface = try XCTUnwrap(view.subviews.first as? TrackAnnouncementSurfaceView, "the background under the drawn content")
        XCTAssertTrue(blur.isDescendant(of: surface))
        XCTAssertTrue(blur.superview?.subviews.first === blur, "the backdrop sits under the wash")
        XCTAssertTrue(blur.superview?.subviews.last === surface.wash)
        XCTAssertEqual(view.tintAlpha, TrackAnnouncementLayout.blurTintAlpha)
    }

    func testGlassStyleUsesLiquidGlassWhereAvailable() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))

        view.style = .glass

        let backdrop = try XCTUnwrap(view.backdropView)
        XCTAssertEqual(view.tintColor, .black)
        // NSGlassEffectView is only in the macOS 26 SDK, so an older Xcode builds and
        // asserts the blur fallback, whatever macOS the tests run on
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            XCTAssertEqual(view.renderedStyle, .glass)
            XCTAssertEqual(view.tintAlpha, TrackAnnouncementLayout.glassTintAlpha)
            XCTAssertEqual(backdrop.frame, TrackAnnouncementLayout.glassFrame(in: view.bounds.size), "the glass is inset and hangs below the strip")
            let glass = try XCTUnwrap(backdrop as? NSGlassEffectView)
            XCTAssertNil(glass.tintColor, "untinted by default: the glass itself is what shows")
            XCTAssertEqual(TrackAnnouncementLayout.glassTint.alphaComponent, 0)
            XCTAssertEqual(glass.cornerRadius, TrackAnnouncementLayout.glassCornerRadius)
        } else {
            XCTAssertTrue(backdrop is NSVisualEffectView, "before macOS 26 the glass style falls back to the blur")
            XCTAssertEqual(view.renderedStyle, .blur, "and the geometry, wash and sheen follow the blur, not the request")
            XCTAssertEqual(view.tintAlpha, TrackAnnouncementLayout.blurTintAlpha)
            XCTAssertEqual(backdrop.frame, view.bounds)
            XCTAssertFalse(view.hasSheen)
            XCTAssertEqual(view.artworkCornerRadius, 0)
        }
        #else
        XCTAssertTrue(backdrop is NSVisualEffectView, "built without the macOS 26 SDK, the glass style is the blur")
        XCTAssertEqual(view.renderedStyle, .blur, "and the geometry, wash and sheen follow the blur, not the request")
        XCTAssertEqual(view.tintAlpha, TrackAnnouncementLayout.blurTintAlpha)
        XCTAssertEqual(backdrop.frame, view.bounds)
        XCTAssertFalse(view.hasSheen)
        XCTAssertEqual(view.artworkCornerRadius, 0)
        #endif
        XCTAssertFalse(view.dataWithPDF(inside: view.bounds).isEmpty)
    }

    /// The glass-only tests skip where the system has no Liquid Glass; the fallback there is
    /// covered by testGlassStyleUsesLiquidGlassWhereAvailable
    private func skipWithoutLiquidGlass() throws {
        try XCTSkipUnless(TrackAnnouncementView.effectiveStyle(for: .glass) == .glass, "no Liquid Glass on this system or SDK")
    }

    func testGlassFollowsTheScaleAndDockInsetsAndTheStripSize() throws {
        try skipWithoutLiquidGlass()
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.style = .glass
        view.scale = 2
        view.leadingInset = 70

        let backdrop = try XCTUnwrap(view.backdropView)
        XCTAssertEqual(backdrop.frame, TrackAnnouncementLayout.glassFrame(in: view.bounds.size, scale: 2, leadingInset: 70))
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
            XCTAssertEqual(glass.cornerRadius, TrackAnnouncementLayout.glassCornerRadius * 2)
        }
        #endif

        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 192)
        XCTAssertEqual(backdrop.frame, TrackAnnouncementLayout.glassFrame(in: view.bounds.size, scale: 2, leadingInset: 70), "the glass follows the strip's size")

        view.style = .blur
        XCTAssertEqual(try XCTUnwrap(view.backdropView).frame, view.bounds, "a blur fills the strip")
    }

    func testTheGlassDrawsTheEdgeLineByDefaultAndTheKnobsPickTheRest() throws {
        try skipWithoutLiquidGlass()
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        XCTAssertFalse(view.hasSheen, "classic: nothing drawn over it")

        view.style = .glass
        XCTAssertTrue(view.hasSheen, "glass: the bright line along the top edge, by default")
        XCTAssertFalse(view.dataWithPDF(inside: view.bounds).isEmpty, "draws with the edge line")

        view.style = .classic
        XCTAssertFalse(view.hasSheen, "back to classic while the strip is up: the line must go with the glass")
        view.style = .glass
        XCTAssertTrue(view.hasSheen)

        TrackAnnouncementGlassKnobs.read = {
            var knobs = TrackAnnouncementGlassKnobs()
            knobs.edgeLine = false
            return knobs
        }
        view.style = .classic
        view.style = .glass
        XCTAssertFalse(view.hasSheen, "edge line off and no shading: bare glass")

        TrackAnnouncementGlassKnobs.read = {
            var knobs = TrackAnnouncementGlassKnobs()
            knobs.edgeLine = false
            knobs.sheen = true
            return knobs
        }
        view.style = .classic
        view.style = .glass
        XCTAssertTrue(view.hasSheen, "the shading alone is enough to draw")

        view.style = .blur
        XCTAssertFalse(view.hasSheen, "blur: never")
    }

    func testGlassEdgeIsDrawnOnlyInLightAppearances() throws {
        let view = TrackAnnouncementWashView(frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.tintAlpha = 0
        view.sheen = .init(rect: NSRect(x: 10, y: -8, width: 580, height: 104), cornerRadius: 8)

        for appearance in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            view.appearance = try XCTUnwrap(NSAppearance(named: appearance))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 96,
                                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.clear.setFill()
            view.bounds.fill(using: .copy)
            view.effectiveAppearance.performAsCurrentDrawingAppearance { view.draw(view.bounds) }
            NSGraphicsContext.restoreGraphicsState()

            // This column is clear of artwork and text: only the top edge can paint it.
            let edgeAlpha = (0..<96).compactMap { bitmap.colorAt(x: 500, y: $0)?.alphaComponent }.max() ?? 0
            let isDark = appearance == .darkAqua || appearance == .accessibilityHighContrastDarkAqua
            if isDark {
                XCTAssertEqual(edgeAlpha, 0, "No extra white border in \(appearance)")
            } else {
                XCTAssertGreaterThan(edgeAlpha, 0.1, "Keep the glint in \(appearance)")
            }
        }
    }

    func testTheArtworkIsRoundedOnTheGlassStripOnly() throws {
        try skipWithoutLiquidGlass()
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        XCTAssertEqual(view.artworkCornerRadius, 0)

        view.style = .glass
        view.scale = 1.5
        XCTAssertEqual(view.artworkCornerRadius, 9)
        XCTAssertFalse(view.dataWithPDF(inside: view.bounds).isEmpty, "draws with the rounded artwork")

        view.style = .blur
        XCTAssertEqual(view.artworkCornerRadius, 0)
    }

    func testTheRenderedStyleIsTheRequestedOneExceptGlassWithoutLiquidGlass() {
        XCTAssertEqual(TrackAnnouncementView.effectiveStyle(for: .classic), .classic)
        XCTAssertEqual(TrackAnnouncementView.effectiveStyle(for: .blur), .blur)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            XCTAssertEqual(TrackAnnouncementView.effectiveStyle(for: .glass), .glass)
        } else {
            XCTAssertEqual(TrackAnnouncementView.effectiveStyle(for: .glass), .blur)
        }
        #else
        XCTAssertEqual(TrackAnnouncementView.effectiveStyle(for: .glass), .blur)
        #endif

        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        XCTAssertEqual(view.renderedStyle, .classic)
        view.style = .glass
        XCTAssertEqual(view.renderedStyle, TrackAnnouncementView.effectiveStyle(for: .glass))
        view.style = .classic
        XCTAssertEqual(view.renderedStyle, .classic)
    }

    func testTheGlassDefaultsAreTheChosenCombination() {
        let knobs = TrackAnnouncementGlassKnobs()
        XCTAssertTrue(knobs.regular, "the regular style, the one with the lensing")
        XCTAssertEqual(knobs.alpha, 1)
        XCTAssertEqual(knobs.tintAlpha, 0)
        XCTAssertEqual(knobs.cornerRadius, 8)
        XCTAssertTrue(knobs.edgeLine, "the bright line Ross liked")
        XCTAssertFalse(knobs.sheen, "no soft shading")
    }

    func testSwitchingBackToClassicRemovesTheBackdrop() {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.style = .blur
        view.style = .classic

        XCTAssertNil(view.backdropView)
        XCTAssertFalse(descendants(of: view).contains { $0 is NSVisualEffectView })
    }

    private func descendants(of view: NSView) -> [NSView] {
        return view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    func testTheClassicStripStillDrawsItsTintUnderTheText() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        // The right end of the strip is clear of the short title: only the wash paints it
        let colour = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide - 4, y: rep.pixelsHigh / 2))
        XCTAssertEqual(colour.alphaComponent, TrackAnnouncementLayout.backgroundAlpha, accuracy: 0.02, "Growl's 60% black")
        XCTAssertLessThan(colour.brightnessComponent, 0.05)
    }

    func testReduceTransparencyMakesEveryStyleOpaque() {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.backgroundAlpha = 1
        for style in TrackAnnouncementStyle.allCases {
            view.style = style
            XCTAssertEqual(view.tintAlpha, 1, "\(style) must be opaque with Reduce Transparency on")
        }
    }

    func testPanelForwardsTheStyleToTheStrip() {
        panel.style = .blur
        XCTAssertEqual(panel.stripView.style, .blur)
        XCTAssertNotNil(panel.stripView.backdropView)
    }

    func testStyleFallsBackToClassicForUnknownStoredValues() {
        XCTAssertEqual(TrackAnnouncementStyle(storedValue: nil), .classic)
        XCTAssertEqual(TrackAnnouncementStyle(storedValue: "sparkles"), .classic)
        XCTAssertEqual(TrackAnnouncementStyle(storedValue: "glass"), .glass)
    }

    func testStripDrawsWithAndWithoutArtwork() {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        XCTAssertFalse(view.dataWithPDF(inside: view.bounds).isEmpty)

        let image = NSImage(size: CGSize(width: 300, height: 200), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        view.announcement = TrackAnnouncement(identity: "2", title: "T", artist: "", album: "", rating: 70, isFavorited: true, artwork: image)
        XCTAssertFalse(view.dataWithPDF(inside: view.bounds).isEmpty)
    }

    // MARK: - The break-out sleeve

    /// A panel with the break-out sleeve on, stepped by a fake clock, and nothing to see
    /// through, so once the slide is done the sleeve's is the one repeating timer. The
    /// pointer starts well clear of every screen, so nothing tilts until a test moves it.
    private func sleevePanel(_ clock: FakeClock, slideDuration: TimeInterval = 0.3) -> TrackAnnouncementPanel {
        sleeveKnobs = TrackAnnouncementSleeveKnobs()
        seeThroughKnobs.peephole = false
        seeThroughKnobs.typingWindow = false
        mouse = NSPoint(x: 0, y: 100_000)
        return TrackAnnouncementPanel(slideDuration: slideDuration, artworkFadeDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
    }

    /// The middle of the sleeve's square on screen, wherever the strip has got to
    private func sleeveCentre(of panel: TrackAnnouncementPanel) -> NSPoint {
        let slot = panel.stripView.artworkFrame.offsetBy(dx: panel.frame.minX + panel.stripView.frame.minX, dy: panel.frame.minY + panel.stripView.frame.minY)
        return NSPoint(x: slot.midX, y: slot.midY)
    }

    /// Where the sleeve's view belongs in the panel, given where the strip is
    private func expectedSleeveFrame(_ panel: TrackAnnouncementPanel) -> NSRect {
        return panel.stripView.sleeveFrame.offsetBy(dx: panel.stripView.frame.minX, dy: panel.stripView.frame.minY)
    }

    private let drawnCover = NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
        NSColor.systemOrange.setFill()
        rect.fill()
        return true
    }

    func testTheSleeveStandsAboveTheStripAndRidesWithItAsItSlides() throws {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        let sleeve = animated.stripView.sleeve
        XCTAssertTrue(animated.stripView.breakout)
        XCTAssertFalse(sleeve.isHidden)
        XCTAssertTrue(sleeve.superview === animated.contentView, "beside the strip, not inside it, so the strip can't clip it")
        XCTAssertEqual(animated.stripView.artworkFrame.width, TrackAnnouncementSleeve.size * animated.scale)
        XCTAssertEqual(sleeve.frame, expectedSleeveFrame(animated))

        for _ in 0..<3 {
            tick(clock, 0.1)
            XCTAssertEqual(sleeve.frame, expectedSleeveFrame(animated), "moved on the same step as the strip")
        }
        tick(clock, 0.5)
        XCTAssertEqual(animated.phase, .shown)
        XCTAssertEqual(sleeve.frame, expectedSleeveFrame(animated))

        // In place: its top 124 points (scaled) above the strip's bottom, past the strip's
        // top edge, and the view inside the panel
        let scale = animated.scale
        let top = sleeve.frame.maxY - TrackAnnouncementSleeve.margin * scale
        XCTAssertEqual(top, animated.stripView.frame.minY + 124 * scale, accuracy: 0.001)
        XCTAssertGreaterThan(top, animated.stripView.frame.maxY + 16 * scale)
        XCTAssertLessThanOrEqual(sleeve.frame.maxY, try XCTUnwrap(animated.contentView).bounds.maxY + 0.001)
    }

    func testTheSleeveRisesOutOfTheStripAfterItStartsToSlide() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        let sleeve = animated.stripView.sleeve
        XCTAssertEqual(sleeve.rise, 0, "sunk into the strip")

        tick(clock, 0.1)
        XCTAssertEqual(sleeve.rise, 0, "waiting for the strip to get going")
        tick(clock, 0.25)
        XCTAssertGreaterThan(sleeve.rise, 0.5, "on its way up")
        tick(clock, 0.4)
        XCTAssertEqual(sleeve.rise, 1, "in place, the overshoot done")
        XCTAssertEqual(clock.pendingRepeating.count, 1, "the slide done, the sleeve still follows the pointer while the strip is up")
    }

    /// How far above the bottom of the panel, and so of the screen, the sleeve and its shadow
    /// reach as drawn now
    private func sleeveTop(_ panel: TrackAnnouncementPanel) -> CGFloat {
        return panel.stripView.frame.minY + TrackAnnouncementSleeve.top(rise: panel.stripView.sleeve.rise, tilt: panel.sleeveTilt, scale: panel.scale)
    }

    /// Ross saw the strip stutter about 80% of the way down and not always reach the bottom:
    /// the sleeve stands 20 points taller than the strip and rode down with it, so its top was
    /// still showing when the strip had gone, until the panel was taken away
    func testTheSleeveSinksOutOfSightWithTheStripAsItSlidesOut() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 1)
        XCTAssertEqual(animated.stripView.sleeve.rise, 1)
        XCTAssertGreaterThan(sleeveTop(animated), animated.stripView.frame.maxY)

        animated.hide()
        var last = sleeveTop(animated)
        for _ in 0..<17 {
            tick(clock)
            XCTAssertEqual(animated.phase, .slidingOut)
            let top = sleeveTop(animated)
            XCTAssertLessThan(top, last, "down on every step, never held")
            last = top
        }
        XCTAssertLessThan(animated.stripView.sleeve.rise, 0.01, "sunk into the strip")
        XCTAssertLessThanOrEqual(last, 0, "out of sight on the last frame before the panel goes")

        tick(clock, 0.1)
        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertEqual(animated.stripView.sleeve.rise, 1, "ready to rise again for the next song")
    }

    func testTurningRoundOnTheWayOutBringsTheSleeveBackUpFromWhereItSank() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 1)
        animated.hide()
        tick(clock, 0.15)
        let sunk = animated.stripView.sleeve.rise
        XCTAssertEqual(sunk, 0.5, accuracy: 0.01, "half way down at half time")

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.sleeve.rise, sunk, "no jump")
        tick(clock, 0.1)
        XCTAssertEqual(animated.stripView.sleeve.rise, sunk, accuracy: 0.001, "it waits for the strip, as on a new appearance")
        tick(clock, 0.6)
        XCTAssertEqual(animated.phase, .shown)
        XCTAssertEqual(animated.stripView.sleeve.rise, 1)
    }

    func testUnderReduceMotionTheSleeveFadesOutInPlace() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: true, reduceTransparency: false)
        tick(clock, 1)

        animated.hide()
        tick(clock, 0.15)

        XCTAssertEqual(animated.stripView.sleeve.rise, 1, "no sinking")
        XCTAssertEqual(animated.stripView.sleeve.alphaValue, 0.5, accuracy: 0.01, "it fades with the strip")
    }

    func testASongArrivingWhileUpSwapsTheCoverWithoutRisingAgain() {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 1)

        animated.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album", artwork: drawnCover), reduceMotion: false, reduceTransparency: false)

        XCTAssertEqual(animated.stripView.sleeve.rise, 1)
        XCTAssertTrue(animated.stripView.sleeve.artwork === drawnCover)
        XCTAssertEqual(animated.stripView.sleeve.coverOpacity, 1, "a song's own cover shows at once")
    }

    func testThePointerTipsTheSleeveTowardsItAndLetsGoWhenItLeaves() {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 1)
        let sleeve = animated.stripView.sleeve
        XCTAssertEqual(animated.sleeveTilt, .rest)
        XCTAssertEqual(sleeve.glareOpacity, 0)

        // Level with the sleeve and to its right, by the span that gives the whole turn
        let centre = sleeveCentre(of: animated)
        mouse = NSPoint(x: centre.x + TrackAnnouncementSleeve.tiltSpan * animated.scale, y: centre.y)
        tick(clock)
        XCTAssertGreaterThan(animated.sleeveTilt.y, 0, "it starts to turn on the next frame")
        XCTAssertLessThan(animated.sleeveTilt.y, TrackAnnouncementSleeve.maxTilt, "and eases over")
        for _ in 0..<60 { tick(clock) }
        XCTAssertEqual(animated.sleeveTilt.y, TrackAnnouncementSleeve.maxTilt, accuracy: 0.001, "turned further towards the pointer")
        XCTAssertEqual(animated.sleeveTilt.x, 0, accuracy: 0.001)
        XCTAssertGreaterThan(sleeve.glareOpacity, 0.9)

        mouse = NSPoint(x: 0, y: 100_000)
        for _ in 0..<60 { tick(clock) }
        XCTAssertEqual(animated.sleeveTilt, .rest)
        XCTAssertEqual(sleeve.glareOpacity, 0)
    }

    func testThePointerOnAnotherDisplayTipsNothing() throws {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 1)
        let screen = try XCTUnwrap(animated.screen ?? NSScreen.main)

        // Just below the strip's screen: within reach of the sleeve, but on another display
        mouse = NSPoint(x: sleeveCentre(of: animated).x, y: screen.frame.minY - 10)
        for _ in 0..<10 { tick(clock) }

        XCTAssertEqual(animated.sleeveTilt, .rest)
    }

    func testReduceMotionBringsTheSleeveInStillAndInPlace() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: true, reduceTransparency: false)
        let sleeve = animated.stripView.sleeve
        XCTAssertEqual(sleeve.rise, 1, "no rise")
        XCTAssertEqual(sleeve.alphaValue, 0, "it fades in with the strip")
        tick(clock, 0.15)
        XCTAssertEqual(sleeve.alphaValue, 0.5, accuracy: 0.01)

        let centre = sleeveCentre(of: animated)
        mouse = NSPoint(x: centre.x + 60, y: centre.y + 60)
        tick(clock, 0.5)
        XCTAssertEqual(sleeve.alphaValue, 1)
        XCTAssertEqual(animated.sleeveTilt, .rest, "no tilt")
        XCTAssertEqual(clock.pendingRepeating.count, 0, "and nothing left ticking once the fade is done")
    }

    func testWithTheTiltOffTheSleeveRisesThenStopsTicking() {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        sleeveKnobs.tilt = false
        animated.show(sample, reduceMotion: false, reduceTransparency: false)

        tick(clock, 1)
        XCTAssertEqual(animated.stripView.sleeve.rise, 1)
        XCTAssertEqual(clock.pendingRepeating.count, 0, "nothing to step once it has risen")

        let centre = sleeveCentre(of: animated)
        mouse = NSPoint(x: centre.x + 60, y: centre.y + 60)
        tick(clock)
        XCTAssertEqual(animated.sleeveTilt, .rest)
    }

    func testWithTheBreakoutOffTheStripKeepsItsFlatArtwork() {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        sleeveKnobs.breakout = false

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertFalse(animated.stripView.breakout)
        XCTAssertTrue(animated.stripView.sleeve.isHidden)
        XCTAssertEqual(animated.stripView.artworkFrame.width, TrackAnnouncementLayout.artworkSize * animated.scale)
        XCTAssertEqual(clock.pendingRepeating.count, 0, "no sleeve to step")

        // A changed default applies from the next appearance
        animated.hide()
        sleeveKnobs.breakout = true
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertTrue(animated.stripView.breakout)
        XCTAssertFalse(animated.stripView.sleeve.isHidden)
    }

    /// A cover that comes after the strip went up cross-fades from the placeholder on the
    /// sleeve as it does in the flat strip, on the same clock
    func testALateCoverCrossFadesOnTheSleeve() {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 1)
        let sleeve = animated.stripView.sleeve
        XCTAssertEqual(sleeve.coverOpacity, 0, "the placeholder")

        animated.refresh(TrackAnnouncement(copying: sample, artwork: drawnCover))
        XCTAssertEqual(sleeve.coverOpacity, 0, "still the placeholder on the first frame")
        tick(clock, 0.15)
        XCTAssertEqual(sleeve.coverOpacity, 0.5, accuracy: 0.01)
        tick(clock, 0.2)
        XCTAssertEqual(sleeve.coverOpacity, 1)
    }

    func testReduceTransparencyTipsTheSleeveWithoutTheGlare() {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: true)
        tick(clock, 1)

        let centre = sleeveCentre(of: animated)
        mouse = NSPoint(x: centre.x, y: centre.y + TrackAnnouncementSleeve.tiltSpan * animated.scale)
        for _ in 0..<60 { tick(clock) }

        XCTAssertEqual(animated.sleeveTilt.x, -TrackAnnouncementSleeve.maxTilt, accuracy: 0.001, "it still faces the pointer above it")
        XCTAssertEqual(animated.stripView.sleeve.glareOpacity, 0, "but with no translucent wash over the cover")
    }

    func testHidingStopsTheSleeveAndPutsItAtRest() throws {
        let clock = FakeClock()
        let animated = sleevePanel(clock, slideDuration: 0)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        tick(clock, 1)
        let centre = sleeveCentre(of: animated)
        mouse = NSPoint(x: centre.x + 50, y: centre.y + 50)
        tick(clock)
        XCTAssertNotEqual(animated.sleeveTilt, .rest)
        let ticker = try XCTUnwrap(clock.timers.last { $0.repeats && $0.isValid })

        animated.hide()

        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertFalse(ticker.isValid)
        XCTAssertEqual(animated.sleeveTilt, .rest)
        XCTAssertEqual(animated.stripView.sleeve.tilt, .rest, "the next song starts straight")
        ticker.action()
        XCTAssertEqual(animated.sleeveTilt, .rest, "a stale tick does nothing")
    }

}
