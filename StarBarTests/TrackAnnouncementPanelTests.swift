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
    private var readGlowKnobs: (() -> TrackAnnouncementGlowKnobs)!
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
        readGlowKnobs = TrackAnnouncementGlowKnobs.read
        TrackAnnouncementGlowKnobs.read = { TrackAnnouncementGlowKnobs() }
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
        TrackAnnouncementGlowKnobs.read = readGlowKnobs
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

        clock.runFrames(for: 0.15)
        XCTAssertEqual(animated.stripView.frame.origin.y, hiddenScaled / 2, accuracy: 0.5, "half way at half time on an ease-in-out curve")
        XCTAssertEqual(animated.phase, .slidingIn)

        clock.runFrames(for: 0.2)
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
        XCTAssertEqual(animated.phase, .shown)

        animated.hide()
        XCTAssertEqual(animated.phase, .slidingOut)
        clock.runFrames(for: 0.1)
        XCTAssertTrue(animated.isVisible, "the panel stays up while the strip slides down")
        XCTAssertLessThan(animated.stripView.frame.origin.y, 0)
        XCTAssertGreaterThan(animated.stripView.frame.origin.y, hiddenScaled)

        clock.runFrames(for: 0.3)
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
        clock.runFrames(for: 0.15)
        XCTAssertEqual(animated.stripView.artworkFade, 0.5, accuracy: 0.01, "half way at half time on an ease-in-out curve")
        clock.runFrames(for: 0.2)
        XCTAssertEqual(animated.stripView.artworkFade, 1)
        // Done: more frames change nothing
        clock.runFrames(for: 1)
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
        clock.runFrames(for: 0.1)
        XCTAssertEqual(animated.stripView.artworkFade, 1, "the old song's fade doesn't carry on over the new one")
    }

    func testShowDuringSlideOutTurnsRoundFromWhereItIs() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.5)
        animated.hide()
        clock.runFrames(for: 0.1)
        let midway = animated.stripView.frame.origin.y

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.phase, .slidingIn)
        XCTAssertEqual(animated.stripView.frame.origin.y, midway, "no jump when turning round")
        clock.runFrames(for: 0.5)
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
        XCTAssertTrue(animated.isVisible)
    }

    func testHideWhileSlidingInTurnsRound() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.1)
        let midway = animated.stripView.frame.origin.y

        animated.hide()
        XCTAssertEqual(animated.phase, .slidingOut)
        XCTAssertEqual(animated.stripView.frame.origin.y, midway)
        clock.runFrames(for: 0.5)
        XCTAssertFalse(animated.isVisible)
        XCTAssertEqual(animated.phase, .hidden)
    }

    func testChangingTransitionMidTurnRoundSettlesTheOtherProperty() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.5)
        animated.hide()
        clock.runFrames(for: 0.1)
        XCTAssertLessThan(animated.stripView.frame.origin.y, 0)

        // Reduce Motion was turned on meanwhile: the fade must not leave the strip half down
        animated.show(sample, reduceMotion: true, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
        clock.runFrames(for: 0.5)
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
        clock.runFrames(for: 0.15)
        XCTAssertEqual(animated.stripView.alphaValue, 0.5, accuracy: 0.01)
        clock.runFrames(for: 0.2)
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
        clock.runFrames(for: seconds)
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
        XCTAssertEqual(keep.opacity, 0.4)

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

    func testTurningReduceMotionOffWhileTheStripIsUpBringsTheTiltBack() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: true, reduceTransparency: false)
        tick(clock, 0.5)
        XCTAssertEqual(clock.pendingRepeating.count, 0, "faded in, and nothing to follow")

        animated.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album"), reduceMotion: false, reduceTransparency: false)
        let centre = sleeveCentre(of: animated)
        mouse = NSPoint(x: centre.x + TrackAnnouncementSleeve.tiltSpan * animated.scale, y: centre.y)
        for _ in 0..<60 { tick(clock) }
        XCTAssertEqual(animated.sleeveTilt.y, TrackAnnouncementSleeve.maxTilt, accuracy: 0.001, "the next song follows the pointer again")
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

    func testAnUnseenCoverAndItsColourAreReadyOnTheFirstExposedFrame() throws {
        let cover = try solidCover(0.8, 0.2, 0.1)
        for breakout in [false, true] {
            for reduceMotion in [false, true] {
                let clock = FakeClock()
                let animated = sleevePanel(clock)
                defer { animated.orderOut(nil) }
                sleeveKnobs.breakout = breakout
                animated.albumTintMode = breakout ? .glow : .strip
                animated.show(sample, reduceMotion: reduceMotion, reduceTransparency: true)
                if !reduceMotion {
                    clock.runFrames(for: 1.0 / 60.0) // Both slots are still clipped.
                }
                let origin = animated.stripView.frame.origin
                animated.refresh(TrackAnnouncement(copying: sample, artwork: cover))

                XCTAssertEqual(animated.stripView.artworkFade, 1)
                if breakout {
                    XCTAssertEqual(animated.stripView.sleeve.coverOpacity, 1)
                    XCTAssertEqual(animated.stripView.sleeve.placeholderOpacity, 0)
                }
                XCTAssertEqual(animated.stripView.albumTint, AlbumTint.colour(of: cover))
                XCTAssertFalse(animated.isFadingTint)
                XCTAssertEqual(animated.stripView.frame.origin, origin)
                XCTAssertEqual(animated.phase, .slidingIn)
            }
        }
    }

    func testAnExposedPlaceholderFadesEvenBeforeTheSleevesRise() throws {
        let cover = try solidCover(0.8, 0.2, 0.1)
        for breakout in [false, true] {
            for reduceMotion in [false, true] {
                let clock = FakeClock()
                let animated = sleevePanel(clock)
                defer { animated.orderOut(nil) }
                sleeveKnobs.breakout = breakout
                animated.albumTintMode = breakout ? .glow : .strip
                animated.show(sample, reduceMotion: reduceMotion, reduceTransparency: false)
                clock.runFrames(for: reduceMotion ? 1.0 / 60.0 : 0.12)
                if breakout && !reduceMotion { XCTAssertEqual(animated.stripView.sleeve.rise, 0) }
                animated.refresh(TrackAnnouncement(copying: sample, artwork: cover))

                XCTAssertEqual(animated.stripView.artworkFade, 0)
                if breakout { XCTAssertEqual(animated.stripView.sleeve.placeholderOpacity, 1) }
                XCTAssertTrue(animated.isFadingTint)
                clock.runFrames(for: 0.15)
                XCTAssertEqual(animated.stripView.artworkFade, 0.5, accuracy: 0.01)
            }
        }
    }

    func testATurnaroundRemembersTheSlotWasExposedAndANewAppearanceForgets() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.warmUp(reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.7)
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        animated.refresh(TrackAnnouncement(copying: sample, artwork: drawnCover))
        XCTAssertEqual(animated.stripView.artworkFade, 1, "the warm-up's frames belong to the warm-up")

        clock.runFrames(for: 0.7)
        animated.hide()
        clock.runFrames(for: 0.29)
        let next = song("next", cover: nil)
        animated.show(next, reduceMotion: false, reduceTransparency: false)
        animated.refresh(TrackAnnouncement(copying: next, artwork: drawnCover))
        XCTAssertEqual(animated.stripView.artworkFade, 0, "turning round keeps the exposed slot")
        animated.hide()
        clock.runFrames(for: 0.4)
        animated.refresh(TrackAnnouncement(copying: sample, artwork: drawnCover))
        XCTAssertEqual(animated.stripView.announcement.identity, next.identity, "a hidden strip ignores the refresh")
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        animated.refresh(TrackAnnouncement(copying: sample, artwork: drawnCover))
        XCTAssertEqual(animated.stripView.artworkFade, 1)
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

    // MARK: - Stalls

    /// Measured 2026-11-03: Music's second notification for a song held the main thread for
    /// about 440 ms as the strip set off, and the next frame drew it already in place. A stall
    /// now pauses the slide where it was drawn, and the slide carries on from there.
    func testAStalledMainThreadPausesTheSlideRatherThanSkippingIt() {
        let clock = FakeClock()
        let animated = timedPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.05)
        let beforeStall = animated.stripView.frame.origin.y

        // 440 ms with no frame, then one late frame
        clock.advance(by: 0.44)
        clock.fireRepeating()
        XCTAssertEqual(animated.phase, .slidingIn, "not finished unseen")
        let afterStall = animated.stripView.frame.origin.y
        XCTAssertGreaterThan(afterStall, beforeStall, "it moves on")
        // The cosine ease moves at most π/2 times its average speed
        let hidden = TrackAnnouncementPlacement.stripOrigin(shown: false, scale: animated.scale).y
        let mostAStepMoves = -hidden * CGFloat(SteppedTimeline.maxStep / 0.3) * 2
        XCTAssertLessThan(afterStall - beforeStall, mostAStepMoves, "but by no more than a step or two's worth")

        // The rest of the slide takes the rest of its time
        clock.runFrames(for: 0.2)
        XCTAssertEqual(animated.phase, .slidingIn, "0.05 + 1/30 + 0.2 s drawn is short of 0.3")
        clock.runFrames(for: 0.05)
        XCTAssertEqual(animated.phase, .shown)
        XCTAssertEqual(animated.stripView.frame.origin.y, 0)
    }

    func testTheSleevesRiseKeepsInStepWithTheSlideThroughAStall() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.1)

        clock.advance(by: 0.5)
        clock.fireRepeating()
        XCTAssertEqual(animated.stripView.sleeve.rise, 0, "still waiting for the strip to get going, as the strip is")
        XCTAssertEqual(animated.stripView.sleeve.frame, expectedSleeveFrame(animated), "and riding with it")

        clock.runFrames(for: 0.6)
        XCTAssertEqual(animated.stripView.sleeve.rise, 1, "and up once the drawn time is past its rise")
    }

    func testAStallPausesALateCoversFadeToo() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0, artworkFadeDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        animated.refresh(TrackAnnouncement(copying: sample, artwork: NSImage(size: NSSize(width: 10, height: 10))))

        clock.advance(by: 1)
        clock.fireRepeating()

        XCTAssertLessThan(animated.stripView.artworkFade, 0.2, "the cover doesn't arrive all at once")
    }

    func testTheStripIsMovingWhileItSlidesAndTheSleeveRises() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }
        XCTAssertFalse(animated.isMoving)

        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertTrue(animated.isMoving)
        clock.runFrames(for: 0.4)
        XCTAssertEqual(animated.phase, .shown)
        XCTAssertTrue(animated.isMoving, "the slide done, the sleeve still rising")
        clock.runFrames(for: 0.4)
        XCTAssertFalse(animated.isMoving, "up and still; the pointer's tilt doesn't count")

        animated.hide()
        XCTAssertTrue(animated.isMoving)
        clock.runFrames(for: 0.4)
        XCTAssertFalse(animated.isMoving)
    }

    // MARK: - Warming up

    func testTheWarmUpIsAnUnseenFirstAppearanceTakenDownAtOnce() {
        let clock = FakeClock()
        let animated = sleevePanel(clock)
        defer { animated.orderOut(nil) }

        animated.warmUp(reduceMotion: false, reduceTransparency: false)

        XCTAssertTrue(animated.isWarmingUp)
        XCTAssertTrue(animated.isVisible, "ordered in, so it is drawn as a song's strip is")
        XCTAssertEqual(animated.alphaValue, TrackAnnouncementPanel.warmUpAlpha, accuracy: 0.0001)
        XCTAssertGreaterThan(animated.alphaValue, 0, "a window that draws nothing may not be drawn at all")
        XCTAssertEqual(animated.phase, .slidingIn, "through the same slide")
        XCTAssertFalse(animated.isMoving, "nothing anyone can see, so Music's repeats needn't wait for it")
        XCTAssertNotNil(animated.stripView.announcement.artwork, "with a cover to draw")
        XCTAssertTrue(animated.stripView.announcement.artwork?.representations.first is NSBitmapImageRep, "decoded from data, as Music's are")

        clock.runFrames(for: 0.8)
        XCTAssertEqual(animated.phase, .shown)
        XCTAssertTrue(animated.isVisible)
        XCTAssertEqual(animated.stripView.sleeve.rise, 1, "the sleeve rose")

        clock.fireAllOneShots()
        XCTAssertFalse(animated.isWarmingUp)
        XCTAssertFalse(animated.isVisible, "taken down at once, with no slide out")
        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertEqual(animated.alphaValue, 1, "ready for the first song")
        XCTAssertEqual(clock.pendingRepeating.count, 0, "nothing left ticking")
    }

    func testASongDuringTheWarmUpStartsItsOwnStripFromTheBeginning() throws {
        let clock = FakeClock()
        let animated = timedPanel(clock)
        defer { animated.orderOut(nil) }
        animated.warmUp(reduceMotion: false, reduceTransparency: false)
        let warmUpsEnd = try XCTUnwrap(clock.pendingOneShot)
        clock.runFrames(for: 0.5)
        XCTAssertEqual(animated.phase, .shown)

        animated.show(sample, reduceMotion: false, reduceTransparency: false)

        XCTAssertFalse(animated.isWarmingUp)
        XCTAssertEqual(animated.alphaValue, 1)
        XCTAssertEqual(animated.phase, .slidingIn, "slid in, not shown already up")
        XCTAssertEqual(animated.stripView.frame.origin.y, TrackAnnouncementPlacement.stripOrigin(shown: false, scale: animated.scale).y)
        XCTAssertEqual(animated.stripView.announcement, sample)
        XCTAssertTrue(animated.isMoving)

        // The warm-up's own end is called off, and a stale one changes nothing
        XCTAssertFalse(warmUpsEnd.isValid)
        warmUpsEnd.action()
        XCTAssertTrue(animated.isVisible)
        XCTAssertEqual(animated.phase, .slidingIn)
        XCTAssertEqual(animated.alphaValue, 1)
    }

    func testTheWarmUpIgnoresTheControllerAndHappensOnlyBeforeTheFirstStrip() {
        let clock = FakeClock()
        let animated = timedPanel(clock)
        defer { animated.orderOut(nil) }
        animated.warmUp(reduceMotion: false, reduceTransparency: false)
        let shown = animated.stripView.announcement

        animated.hide()
        animated.refresh(TrackAnnouncement(copying: shown, rating: 100))
        XCTAssertEqual(animated.phase, .slidingIn, "the controller has nothing up to hide")
        XCTAssertEqual(animated.stripView.announcement, shown)

        clock.fireAllOneShots()
        animated.warmUp(reduceMotion: false, reduceTransparency: false)
        XCTAssertFalse(animated.isWarmingUp, "once is enough")
        XCTAssertFalse(animated.isVisible)

        let later = timedPanel(clock)
        defer { later.orderOut(nil) }
        later.show(sample, reduceMotion: false, reduceTransparency: false)
        later.warmUp(reduceMotion: false, reduceTransparency: false)
        XCTAssertFalse(later.isWarmingUp, "a strip has already appeared")
        XCTAssertEqual(later.alphaValue, 1)
    }

    func testAScreenChangeEndsTheWarmUp() {
        let clock = FakeClock()
        let animated = timedPanel(clock)
        defer { animated.orderOut(nil) }
        animated.warmUp(reduceMotion: false, reduceTransparency: false)

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)

        XCTAssertFalse(animated.isWarmingUp)
        XCTAssertFalse(animated.isVisible)
        XCTAssertEqual(animated.alphaValue, 1)
    }

    // MARK: - The heart changing

    private func heartPanel(_ clock: FakeClock, slideDuration: TimeInterval = 0) -> TrackAnnouncementPanel {
        return TrackAnnouncementPanel(slideDuration: slideDuration, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
    }

    /// The strip's heart in the panel's content view, wherever the strip has slid to
    private func heartCentre(_ panel: TrackAnnouncementPanel) throws -> NSPoint {
        let heart = try XCTUnwrap(panel.stripView.heartFrame)
        return NSPoint(x: panel.stripView.frame.minX + heart.midX, y: panel.stripView.frame.minY + heart.midY)
    }

    private func drawnCentre(_ panel: TrackAnnouncementPanel) throws -> NSPoint {
        let centre = try XCTUnwrap(panel.heartView.centre)
        return NSPoint(x: panel.heartView.frame.minX + centre.x, y: panel.heartView.frame.minY + centre.y)
    }

    func testASetHeartBurstsOverTheStripsOwnHeartAndPutsItBack() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        animated.refresh(TrackAnnouncement(copying: sample, isFavorited: true))

        animated.animateHeart(.burst)

        XCTAssertTrue(animated.isAnimatingHeart)
        XCTAssertFalse(animated.heartView.isHidden)
        XCTAssertTrue(animated.stripView.hidesHeart, "the strip leaves its heart out meanwhile")
        XCTAssertEqual(animated.heartView.change, .burst)
        XCTAssertEqual(animated.heartView.palette.ringStart, Stars.favoriteHeartColor)
        let burst = try XCTUnwrap(animated.heartView.burst)
        XCTAssertEqual(burst, HeartBurst.strip(heartSize: TrackAnnouncementLayout.ratingStarSize * animated.scale))
        XCTAssertGreaterThanOrEqual(animated.heartView.frame.width / 2, burst.extent)
        let drawn = try drawnCentre(animated)
        let heart = try heartCentre(animated)
        XCTAssertEqual(drawn.x, heart.x, accuracy: 0.001)
        XCTAssertEqual(drawn.y, heart.y, accuracy: 0.001)
        XCTAssertEqual(animated.heartView.hearts?.size, animated.stripView.heartFrame?.size)

        clock.runFrames(for: 0.4)
        XCTAssertEqual(animated.heartView.elapsed, 0.4, accuracy: 0.001)

        clock.runFrames(for: HeartBurst.duration - 0.4 + 0.02)
        XCTAssertFalse(animated.isAnimatingHeart)
        XCTAssertTrue(animated.heartView.isHidden)
        XCTAssertFalse(animated.stripView.hidesHeart, "the strip draws its own heart again")
        XCTAssertNil(animated.heartView.change)
    }

    func testAClearedHeartDipsWithoutABurstAndEndsSooner() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(TrackAnnouncement(copying: sample, isFavorited: true), reduceMotion: false, reduceTransparency: false)
        animated.refresh(sample)

        animated.animateHeart(.dip)
        XCTAssertEqual(animated.heartView.change, .dip)
        clock.runFrames(for: HeartChange.dipDuration + 0.02)

        XCTAssertFalse(animated.isAnimatingHeart)
        XCTAssertFalse(animated.stripView.hidesHeart)
    }

    func testTheHeartIsWhereTheStripDrawsIt() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        let afterStars = try XCTUnwrap(animated.stripView.heartFrame)

        animated.show(TrackAnnouncement(copying: sample, canRate: false), reduceMotion: false, reduceTransparency: false)
        let first = try XCTUnwrap(animated.stripView.heartFrame)
        XCTAssertLessThan(first.minX, afterStars.minX, "first on the row when there are no stars")
        XCTAssertEqual(first.midY, afterStars.midY, accuracy: 0.001)

        let spotify = TrackAnnouncement(identity: "spotify:track:S", title: "T", artist: "A", album: "B", canRate: false, source: .spotify, showsSpotifyHeart: true)
        animated.show(spotify, reduceMotion: false, reduceTransparency: false)
        XCTAssertEqual(animated.stripView.heartFrame, first)

        let signedOut = TrackAnnouncement(identity: "spotify:track:S", title: "T", artist: "A", album: "B", canRate: false, source: .spotify)
        animated.show(signedOut, reduceMotion: false, reduceTransparency: false)
        XCTAssertNil(animated.stripView.heartFrame, "no heart without a sign-in")
        animated.animateHeart(.burst)
        XCTAssertFalse(animated.isAnimatingHeart, "so nothing to animate")
    }

    func testASpotifyLikeBurstsGreen() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        let liked = TrackAnnouncement(identity: "spotify:track:S", title: "T", artist: "A", album: "B", isFavorited: true, canRate: false, source: .spotify, showsSpotifyHeart: true)
        animated.show(liked, reduceMotion: false, reduceTransparency: false)

        animated.animateHeart(.burst)

        XCTAssertEqual(animated.heartView.palette.ringStart, Stars.spotifyHeartColor)
    }

    func testNothingAnimatesWhileTheStripIsDownOrWarmingUp() {
        let clock = FakeClock()
        let animated = heartPanel(clock, slideDuration: 0.3)
        defer { animated.orderOut(nil) }

        animated.animateHeart(.burst)
        XCTAssertFalse(animated.isAnimatingHeart)

        animated.warmUp(reduceMotion: false, reduceTransparency: false)
        animated.animateHeart(.burst)
        XCTAssertFalse(animated.isAnimatingHeart, "the warm-up is never seen")
        XCTAssertTrue(animated.heartView.isHidden)
    }

    func testTheHeartRidesWithTheStripWhileItSlidesIn() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock, slideDuration: 0.3)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.05)

        animated.animateHeart(.burst)
        XCTAssertTrue(animated.isAnimatingHeart, "a heart set as the strip comes up")
        clock.runFrames(for: 0.1)

        XCTAssertEqual(animated.phase, .slidingIn)
        let drawn = try drawnCentre(animated)
        let heart = try heartCentre(animated)
        XCTAssertEqual(drawn.x, heart.x, accuracy: 0.001)
        XCTAssertEqual(drawn.y, heart.y, accuracy: 0.001)
    }

    func testANewSongOrARefusedHeartEndsTheChange() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        let favourite = TrackAnnouncement(copying: sample, isFavorited: true)
        animated.show(favourite, reduceMotion: false, reduceTransparency: false)

        animated.animateHeart(.burst)
        animated.refresh(TrackAnnouncement(copying: favourite, rating: 80))
        XCTAssertTrue(animated.isAnimatingHeart, "a new rating leaves the heart changing")

        animated.refresh(sample)
        XCTAssertFalse(animated.isAnimatingHeart, "Music refused it: the old heart is back")
        XCTAssertFalse(animated.stripView.hidesHeart)

        animated.refresh(favourite)
        animated.animateHeart(.burst)
        animated.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album"), reduceMotion: false, reduceTransparency: false)
        XCTAssertFalse(animated.isAnimatingHeart, "the heart belonged to the song before")
        XCTAssertTrue(animated.heartView.isHidden)
    }

    func testHidingTakesTheHeartDown() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(TrackAnnouncement(copying: sample, isFavorited: true), reduceMotion: false, reduceTransparency: false)
        animated.animateHeart(.burst)

        animated.hide()

        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertFalse(animated.isAnimatingHeart)
        XCTAssertFalse(animated.stripView.hidesHeart)
    }

    // MARK: - The stars' flourish

    /// Four stars saved over two, as the strip's controller makes it
    private let raise = StarFlourish(saving: 80, from: 40, showing: 40, reduceMotion: false, look: .afterglow)

    private func rated(_ rating: Int) -> TrackAnnouncement {
        return TrackAnnouncement(copying: sample, rating: rating)
    }

    func testASavedRatingFlourishesInTheStripsOwnRowAndEndsAtRest() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(40), reduceMotion: false, reduceTransparency: false)
        animated.refresh(rated(80))
        XCTAssertFalse(animated.isAnimatingStars)

        animated.animateStars(raise)

        XCTAssertTrue(animated.isAnimatingStars)
        let first = try XCTUnwrap(animated.stripView.starFlourish)
        XCTAssertEqual(first.flourish, raise)
        XCTAssertEqual(first.elapsed, 0)

        clock.runFrames(for: 0.1)
        XCTAssertEqual(try XCTUnwrap(animated.stripView.starFlourish).elapsed, 0.1, accuracy: 0.001)

        clock.runFrames(for: raise.duration - 0.1 + 0.02)
        XCTAssertFalse(animated.isAnimatingStars)
        XCTAssertNil(animated.stripView.starFlourish, "the strip draws its stars at rest again")
    }

    /// Stepped, as the slide is: a held main thread pauses the stars where they were drawn
    func testAStallPausesTheStarsRatherThanSkippingThem() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(80), reduceMotion: false, reduceTransparency: false)
        animated.animateStars(raise)
        clock.runFrames(for: 0.1)

        // Half a second with no frame, then one late frame
        clock.advance(by: 0.5)
        clock.fireRepeating()

        XCTAssertTrue(animated.isAnimatingStars, "not finished unseen")
        XCTAssertEqual(try XCTUnwrap(animated.stripView.starFlourish).elapsed, 0.1 + SteppedTimeline.maxStep, accuracy: 0.001)
    }

    func testOnlyStarsTheStripShowsFlourish() {
        let clock = FakeClock()
        let animated = heartPanel(clock, slideDuration: 0.3)
        defer { animated.orderOut(nil) }

        animated.animateStars(raise)
        XCTAssertFalse(animated.isAnimatingStars, "the strip is down")

        animated.warmUp(reduceMotion: false, reduceTransparency: false)
        animated.animateStars(raise)
        XCTAssertFalse(animated.isAnimatingStars, "the warm-up is never seen")

        animated.show(TrackAnnouncement(copying: rated(80), canRate: false), reduceMotion: false, reduceTransparency: false)
        animated.animateStars(raise)
        XCTAssertFalse(animated.isAnimatingStars, "a song that can't be rated shows no stars")

        let spotify = TrackAnnouncement(identity: "spotify:track:S", title: "T", artist: "A", album: "B", rating: 80, canRate: false, source: .spotify, showsSpotifyHeart: true)
        animated.show(spotify, reduceMotion: false, reduceTransparency: false)
        animated.animateStars(raise)
        XCTAssertFalse(animated.isAnimatingStars, "nor does a Spotify song the user doesn't have")

        animated.show(rated(60), reduceMotion: false, reduceTransparency: false)
        animated.animateStars(raise)
        XCTAssertFalse(animated.isAnimatingStars, "a flourish that ends at other stars than the strip shows")
        XCTAssertNil(animated.stripView.starFlourish)
    }

    func testTheStarsFlourishWhileTheStripSlidesInButNotOnItsWayOut() {
        let clock = FakeClock()
        let animated = heartPanel(clock, slideDuration: 0.3)
        defer { animated.orderOut(nil) }
        animated.show(rated(80), reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.05)
        XCTAssertEqual(animated.phase, .slidingIn)

        animated.animateStars(raise)
        XCTAssertTrue(animated.isAnimatingStars, "a rating saved as the strip comes up")

        clock.runFrames(for: 0.3 + raise.duration)
        XCTAssertEqual(animated.phase, .shown)
        XCTAssertFalse(animated.isAnimatingStars)

        animated.hide()
        XCTAssertEqual(animated.phase, .slidingOut)
        animated.animateStars(raise)
        XCTAssertFalse(animated.isAnimatingStars)
    }

    func testAnotherRatingANewSongOrHidingEndsTheFlourish() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(80), reduceMotion: false, reduceTransparency: false)

        animated.animateStars(raise)
        animated.refresh(TrackAnnouncement(copying: rated(80), isFavorited: true))
        XCTAssertTrue(animated.isAnimatingStars, "a heart set meanwhile leaves the stars in their flourish")

        animated.refresh(rated(40))
        XCTAssertFalse(animated.isAnimatingStars, "Music refused the rating: the old stars are back, at rest")
        XCTAssertNil(animated.stripView.starFlourish)

        animated.refresh(rated(80))
        animated.animateStars(raise)
        animated.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album", rating: 80), reduceMotion: false, reduceTransparency: false)
        XCTAssertFalse(animated.isAnimatingStars, "the stars belonged to the song before")

        animated.animateStars(raise)
        XCTAssertTrue(animated.isAnimatingStars)
        animated.hide()
        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertFalse(animated.isAnimatingStars)
        XCTAssertNil(animated.stripView.starFlourish)
    }

    /// A second rating ends the first one's flourish and starts its own, on one timer
    func testARatingSavedDuringAFlourishStartsItsOwn() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(80), reduceMotion: false, reduceTransparency: false)
        animated.animateStars(raise)
        clock.runFrames(for: 0.1)
        let timers = clock.pendingRepeating.count

        let second = StarFlourish(saving: 100, from: 80, showing: 80, reduceMotion: false, look: .afterglow)
        animated.refresh(rated(100))
        animated.animateStars(second)

        let running = try XCTUnwrap(animated.stripView.starFlourish)
        XCTAssertEqual(running.flourish, second)
        XCTAssertEqual(running.elapsed, 0)
        XCTAssertEqual(clock.pendingRepeating.count, timers, "the first one's timer has gone")
    }

    // MARK: The five-star finale

    /// Five stars saved over three, in the one-colour run
    private let fiveStars = StarFlourish(saving: 100, from: 60, showing: 60, reduceMotion: false, look: .run)

    /// The first star's centre on the panel, wherever the strip has slid to
    private func firstStarCentre(_ panel: TrackAnnouncementPanel) throws -> NSPoint {
        let star = try XCTUnwrap(panel.stripView.firstStarFrame)
        return StarFlourish.centre(ofStarIn: star.offsetBy(dx: panel.stripView.frame.minX, dy: panel.stripView.frame.minY))
    }

    /// Where the finale's view has the first star's centre, on the panel
    private func finaleCentre(_ panel: TrackAnnouncementPanel) -> NSPoint {
        return NSPoint(x: panel.finaleView.frame.minX + panel.finaleView.origin.x, y: panel.finaleView.frame.minY + panel.finaleView.origin.y)
    }

    func testASongGivenFiveStarsThrowsTheFinaleUpFromTheStripsStars() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(60), reduceMotion: false, reduceTransparency: false)
        animated.refresh(rated(100))
        XCTAssertTrue(animated.finaleView.isHidden)
        XCTAssertTrue(fiveStars.hasFinale)

        animated.animateStars(fiveStars)

        XCTAssertTrue(animated.isAnimatingStars)
        XCTAssertFalse(animated.finaleView.isHidden)
        let star = try XCTUnwrap(animated.stripView.firstStarFrame)
        let finale = try XCTUnwrap(animated.finaleView.finale)
        XCTAssertEqual(finale, StarFinale.strip(starSize: star.width, spacing: animated.stripView.starSpacing, stagger: 0.05))
        XCTAssertEqual(finale.fan, .up, "the panel ends at the strip's bottom edge")
        XCTAssertEqual(animated.finaleView.elapsed, 0, "its first frame, which is empty")
        XCTAssertTrue(animated.finaleView.superview === animated.heartView.superview, "beside the strip, as the heart's burst is")

        let centre = try firstStarCentre(animated)
        XCTAssertEqual(finaleCentre(animated).x, centre.x, accuracy: 0.001)
        XCTAssertEqual(finaleCentre(animated).y, centre.y, accuracy: 0.001)
        XCTAssertTrue(animated.finaleView.frame.contains(finale.bounds.offsetBy(dx: centre.x, dy: centre.y)), "room for every small star")
        XCTAssertTrue(animated.stripView.frame.contains(animated.finaleView.frame), "and all of it over the strip")

        clock.runFrames(for: 0.3)
        XCTAssertEqual(animated.finaleView.elapsed, 0.3, accuracy: 0.001, "stepped with the stars")
        XCTAssertEqual(try XCTUnwrap(animated.stripView.starFlourish).elapsed, 0.3, accuracy: 0.001)

        // The run is over by now, and the small stars are still in the air
        clock.runFrames(for: 0.3)
        XCTAssertLessThan(fiveStars.starsDuration, 0.6)
        XCTAssertTrue(animated.isAnimatingStars, "the flourish lasts as long as its finale")
        XCTAssertFalse(animated.finaleView.isHidden)

        clock.runFrames(for: fiveStars.duration - 0.6 + 0.02)
        XCTAssertFalse(animated.isAnimatingStars)
        XCTAssertTrue(animated.finaleView.isHidden)
        XCTAssertNil(animated.finaleView.finale)
        XCTAssertNil(animated.stripView.starFlourish, "the strip draws its stars at rest again")
    }

    func testOtherRatingsAndReduceMotionHaveNoFinale() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(80), reduceMotion: false, reduceTransparency: false)

        animated.animateStars(raise)
        XCTAssertTrue(animated.isAnimatingStars)
        XCTAssertTrue(animated.finaleView.isHidden, "four stars pop, and that is all")
        XCTAssertNil(animated.finaleView.finale)

        // Five stars for a song that had five
        animated.refresh(rated(100))
        animated.animateStars(StarFlourish(saving: 100, from: 100, showing: 100, reduceMotion: false, look: .run))
        XCTAssertTrue(animated.isAnimatingStars)
        XCTAssertTrue(animated.finaleView.isHidden)

        animated.animateStars(StarFlourish(saving: 100, from: 60, showing: 60, reduceMotion: true, look: .run))
        XCTAssertTrue(animated.isAnimatingStars, "the stars cross-fade")
        XCTAssertTrue(animated.finaleView.isHidden, "and nothing flies")
    }

    func testTheFinaleRidesWithTheStripWhileItSlidesIn() throws {
        let clock = FakeClock()
        let animated = heartPanel(clock, slideDuration: 0.3)
        defer { animated.orderOut(nil) }
        animated.show(rated(100), reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.05)

        animated.animateStars(fiveStars)
        XCTAssertFalse(animated.finaleView.isHidden, "five stars saved as the strip comes up")
        let low = try firstStarCentre(animated)
        XCTAssertEqual(finaleCentre(animated).y, low.y, accuracy: 0.001)
        clock.runFrames(for: 0.1)

        XCTAssertEqual(animated.phase, .slidingIn)
        let centre = try firstStarCentre(animated)
        XCTAssertGreaterThan(centre.y, low.y, "the strip has moved up")
        XCTAssertEqual(finaleCentre(animated).x, centre.x, accuracy: 0.001)
        XCTAssertEqual(finaleCentre(animated).y, centre.y, accuracy: 0.001)
        XCTAssertEqual(animated.finaleView.alphaValue, animated.stripView.alphaValue)
    }

    func testAnotherRatingANewSongOrHidingTakesTheFinaleDown() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(100), reduceMotion: false, reduceTransparency: false)

        animated.animateStars(fiveStars)
        animated.refresh(TrackAnnouncement(copying: rated(100), isFavorited: true))
        XCTAssertFalse(animated.finaleView.isHidden, "a heart set meanwhile leaves the small stars flying")

        animated.refresh(rated(60))
        XCTAssertTrue(animated.finaleView.isHidden, "Music refused the rating: the old stars are back")
        XCTAssertNil(animated.finaleView.finale)

        animated.refresh(rated(100))
        animated.animateStars(fiveStars)
        XCTAssertFalse(animated.finaleView.isHidden)
        animated.show(TrackAnnouncement(identity: "2", title: "Next", artist: "Artist", album: "Album", rating: 100), reduceMotion: false, reduceTransparency: false)
        XCTAssertTrue(animated.finaleView.isHidden, "the small stars belonged to the song before")

        animated.animateStars(fiveStars)
        XCTAssertFalse(animated.finaleView.isHidden)
        animated.hide()
        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertTrue(animated.finaleView.isHidden)
        XCTAssertNil(animated.finaleView.finale)
    }

    /// A second rating takes the first one's small stars down with its flourish
    func testALowerRatingSavedDuringTheFinaleEndsIt() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(100), reduceMotion: false, reduceTransparency: false)
        animated.animateStars(fiveStars)
        clock.runFrames(for: 0.2)
        XCTAssertFalse(animated.finaleView.isHidden)

        animated.refresh(rated(80))
        animated.animateStars(StarFlourish(saving: 80, from: 100, showing: 100, reduceMotion: false, look: .run))

        XCTAssertTrue(animated.isAnimatingStars, "the stars fold back")
        XCTAssertTrue(animated.finaleView.isHidden, "with nothing in the air")
        XCTAssertNil(animated.finaleView.finale)
    }

    /// A strip that shows no stars has no first star for the finale to start from
    func testAStripWithNoStarsHasNoFirstStar() {
        let clock = FakeClock()
        let animated = heartPanel(clock)
        defer { animated.orderOut(nil) }
        animated.show(rated(100), reduceMotion: false, reduceTransparency: false)
        XCTAssertNotNil(animated.stripView.firstStarFrame)
        XCTAssertGreaterThan(animated.stripView.starSpacing, 0)

        animated.show(TrackAnnouncement(copying: rated(100), canRate: false), reduceMotion: false, reduceTransparency: false)
        XCTAssertNil(animated.stripView.firstStarFrame, "the cannot-rate line")

        let spotify = TrackAnnouncement(identity: "spotify:track:S", title: "T", artist: "A", album: "B", rating: 100, canRate: false, source: .spotify, showsSpotifyHeart: true)
        animated.show(spotify, reduceMotion: false, reduceTransparency: false)
        XCTAssertNil(animated.stripView.firstStarFrame, "Spotify's name")
        animated.animateStars(fiveStars)
        XCTAssertTrue(animated.finaleView.isHidden)
    }

    /// The first star is where the strip draws it: on the heart's row, five stars before it
    func testTheFirstStarIsWhereTheStripDrawsIt() throws {
        let size = NSSize(width: 260, height: TrackAnnouncementLayout.stripHeight(scale: 1))
        let view = TrackAnnouncementContentView(announcement: rated(100), frame: NSRect(origin: .zero, size: size))
        let star = try XCTUnwrap(view.firstStarFrame)
        XCTAssertEqual(star.size, NSSize(width: 12, height: 12))
        XCTAssertTrue(view.starFlourishRect.contains(star), "in the row a flourish is drawn in")
        let heart = try XCTUnwrap(view.heartFrame)
        XCTAssertEqual(star.midY, heart.midY, accuracy: 0.001, "on the heart's row")
        XCTAssertEqual(heart.minX - star.minX, 5 * 15 + 3, accuracy: 0.001, "five stars, their gaps and the gap before the heart")
    }

    // MARK: The stars' flourish as drawn

    /// The strip's content drawn into a bitmap, at rest or at a moment of a flourish
    private func drawn(_ announcement: TrackAnnouncement, _ flourish: StarFlourish? = nil, at elapsed: TimeInterval = 0) throws -> (rep: NSBitmapImageRep, view: TrackAnnouncementContentView) {
        let size = NSSize(width: 260, height: TrackAnnouncementLayout.stripHeight(scale: 1))
        let view = TrackAnnouncementContentView(announcement: announcement, frame: NSRect(origin: .zero, size: size))
        if let flourish = flourish {
            view.starFlourish = (flourish, elapsed)
        }
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, view)
    }

    /// A pixel's alpha and its colour premultiplied, since a clear pixel's colour means nothing
    private func premultiplied(_ colour: NSColor) -> [CGFloat] {
        let alpha = colour.alphaComponent
        return [alpha, colour.redComponent * alpha, colour.greenComponent * alpha, colour.blueComponent * alpha]
    }

    /// Where two pictures of one view differ, as points in the view (its origin bottom left),
    /// with whether the second picture is coloured there
    private func differences(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep, in bounds: NSRect) -> [(point: NSPoint, isColoured: Bool)] {
        var found: [(point: NSPoint, isColoured: Bool)] = []
        let scale = CGFloat(first.pixelsWide) / bounds.width
        let tolerance: CGFloat = 0.02
        for y in 0..<min(first.pixelsHigh, second.pixelsHigh) {
            for x in 0..<min(first.pixelsWide, second.pixelsWide) {
                guard let one = first.colorAt(x: x, y: y), let other = second.colorAt(x: x, y: y) else { continue }
                let differs = zip(premultiplied(one), premultiplied(other)).contains { abs($0 - $1) > tolerance }
                guard differs else { continue }
                let point = NSPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(first.pixelsHigh - y) - 0.5) / scale)
                let isColoured = other.alphaComponent > 0.5 && other.saturationComponent > 0.4
                found.append((point: point, isColoured: isColoured))
            }
        }
        return found
    }

    /// The frame of a flourish is taller than the stars at rest and has no heart, so it is
    /// drawn lower and the heart beside it. Its last frame has to be the picture at rest, or
    /// the stars would jump as the flourish ends.
    func testAFlourishEndsOnThePictureOfTheStarsAtRest() throws {
        for isFavorited in [false, true] {
            let announcement = TrackAnnouncement(copying: rated(80), isFavorited: isFavorited)
            let rest = try drawn(announcement)
            let ended = try drawn(announcement, raise, at: raise.duration)

            let moved = differences(rest.rep, ended.rep, in: rest.view.bounds)
            XCTAssertTrue(moved.isEmpty, "\(moved.count) pixels differ at rest, favourite \(isFavorited), the first at \(String(describing: moved.first?.point))")
        }
    }

    /// Only the stars' row is drawn again at each step, so everything a frame draws, colour
    /// and shadow included, has to fall inside it
    func testAFrameOfTheFlourishDrawsOnlyInTheRowDrawnAgain() throws {
        let rest = try drawn(rated(80))
        // The first star near its biggest and the second on its way up, both in colour
        let popping = try drawn(rated(80), raise, at: 0.1)

        let changed = differences(rest.rep, popping.rep, in: rest.view.bounds)
        XCTAssertFalse(changed.isEmpty, "the flourish draws something")
        let row = popping.view.starFlourishRect
        let outside = changed.filter { !row.contains($0.point) }
        XCTAssertTrue(outside.isEmpty, "\(outside.count) pixels changed outside \(row), the first at \(String(describing: outside.first?.point))")
        XCTAssertTrue(popping.view.bounds.contains(row), "and the row is on the strip")
        XCTAssertTrue(changed.contains { $0.isColoured }, "the icon's colours over the white stars")
    }

    func testARunInOneColourDrawsNoColour() throws {
        let run = StarFlourish(saving: 80, from: 40, showing: 40, reduceMotion: false, look: .run)
        let rest = try drawn(rated(80))
        let popping = try drawn(rated(80), run, at: 0.1)

        let changed = differences(rest.rep, popping.rep, in: rest.view.bounds)
        XCTAssertFalse(changed.isEmpty)
        XCTAssertFalse(changed.contains { $0.isColoured })
    }

    // MARK: The album tint

    private func tintPanel(_ clock: FakeClock) -> TrackAnnouncementPanel {
        return TrackAnnouncementPanel(slideDuration: 0, artworkFadeDuration: 0, tintFadeDuration: 0.5, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, keyboard: { [unowned self] in self.keys }, clock: clock)
    }

    /// A cover of one sRGB colour, as a cover read from Music would be drawn
    private func solidCover(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) throws -> NSImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 16, height: 16))
    }

    private func song(_ identity: String, cover: NSImage?) -> TrackAnnouncement {
        return TrackAnnouncement(identity: identity, title: "Title \(identity)", artist: "Artist", album: "Album \(identity)", artwork: cover)
    }

    /// The classic strip's background in `cover`'s colour
    private func classicWash(_ cover: NSImage) throws -> TrackAnnouncementWash {
        return TrackAnnouncementWash(colour: try XCTUnwrap(AlbumTint.colour(of: cover)), alpha: TrackAnnouncementLayout.backgroundAlpha)
    }

    private let classicBlack = TrackAnnouncementWash(colour: .black, alpha: TrackAnnouncementLayout.backgroundAlpha)

    private func assertWash(_ wash: TrackAnnouncementWash, _ expected: TrackAnnouncementWash, accuracy: Double = 0.002, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(wash.alpha), Double(expected.alpha), accuracy: accuracy, "alpha. \(message)", file: file, line: line)
        XCTAssertEqual(wash.colour.l, expected.colour.l, accuracy: accuracy, "L. \(message)", file: file, line: line)
        XCTAssertEqual(wash.colour.a, expected.colour.a, accuracy: accuracy, "a. \(message)", file: file, line: line)
        XCTAssertEqual(wash.colour.b, expected.colour.b, accuracy: accuracy, "b. \(message)", file: file, line: line)
    }

    func testTheAlbumTintIsOffUntilTurnedOn() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }

        animated.show(song("1", cover: try solidCover(0.8, 0.1, 0.1)), reduceMotion: false, reduceTransparency: false)

        XCTAssertEqual(animated.albumTintMode, .off)
        XCTAssertNil(animated.stripView.albumTint)
        XCTAssertNil(animated.stripView.albumTintLayerColor, "no colour layer")
        XCTAssertTrue(animated.stripView.washDrawsTint, "the style's own black, drawn as it always was")
        XCTAssertFalse(animated.isFadingTint)
    }

    func testAStripArrivesAlreadyInItsColour() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        let cover = try solidCover(0.8, 0.1, 0.1)

        animated.show(song("1", cover: cover), reduceMotion: false, reduceTransparency: false)

        XCTAssertFalse(animated.isFadingTint, "no fade on the way in: the strip slides up in its colour")
        XCTAssertEqual(animated.stripView.albumTint, AlbumTint.colour(of: cover))
        assertWash(animated.stripView.displayedWash, try classicWash(cover))
        XCTAssertEqual(try XCTUnwrap(animated.stripView.albumTintLayerColor).alpha, TrackAnnouncementLayout.backgroundAlpha, accuracy: 0.001)
        XCTAssertFalse(animated.stripView.washDrawsTint, "the colour takes the black wash's place rather than going over it")
    }

    func testANewSongFadesFromTheOldColourToItsOwn() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        let redCover = try solidCover(0.8, 0.1, 0.1)
        let blueCover = try solidCover(0.1, 0.3, 0.9)
        let red = try classicWash(redCover)
        let blue = try classicWash(blueCover)
        animated.show(song("1", cover: redCover), reduceMotion: false, reduceTransparency: false)

        animated.show(song("2", cover: blueCover), reduceMotion: false, reduceTransparency: false)

        XCTAssertTrue(animated.isFadingTint)
        assertWash(animated.stripView.displayedWash, red, "still the old colour on the first frame")
        clock.runFrames(for: 0.25)
        assertWash(animated.stripView.displayedWash, .mix(red, blue, progress: 0.5), accuracy: 0.01, "half way at half time on an ease-in-out curve")
        clock.runFrames(for: 0.3)
        XCTAssertFalse(animated.isFadingTint)
        assertWash(animated.stripView.displayedWash, blue)
        // Done: more frames change nothing
        clock.runFrames(for: 0.5)
        assertWash(animated.stripView.displayedWash, blue)
    }

    func testALateCoverBloomsItsColourIn() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
        XCTAssertNil(animated.stripView.albumTint, "no cover yet: the style's black")
        assertWash(animated.stripView.displayedWash, classicBlack)
        let cover = try solidCover(0.8, 0.1, 0.1)
        let red = try classicWash(cover)
        let withCover = TrackAnnouncement(copying: sample, artwork: cover)

        animated.refresh(withCover)

        XCTAssertTrue(animated.isFadingTint)
        clock.runFrames(for: 0.25)
        assertWash(animated.stripView.displayedWash, .mix(classicBlack, red, progress: 0.5), accuracy: 0.01)
        clock.runFrames(for: 0.3)
        assertWash(animated.stripView.displayedWash, red)
        // A change to the stars leaves the colour as it is
        animated.refresh(TrackAnnouncement(copying: withCover, rating: 80))
        XCTAssertFalse(animated.isFadingTint)
        assertWash(animated.stripView.displayedWash, red)
    }

    func testAChangeOfColourCaughtPartWayGoesOnFromWhatIsShown() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        let greenCover = try solidCover(0.2, 0.7, 0.3)
        animated.show(song("1", cover: try solidCover(0.8, 0.1, 0.1)), reduceMotion: false, reduceTransparency: false)
        animated.show(song("2", cover: try solidCover(0.1, 0.3, 0.9)), reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.25)
        let shown = animated.stripView.displayedWash

        animated.show(song("3", cover: greenCover), reduceMotion: false, reduceTransparency: false)

        assertWash(animated.stripView.displayedWash, shown, "no jump back to the first colour or on to the second")
        clock.runFrames(for: 1.0 / 60.0)
        assertWash(animated.stripView.displayedWash, shown, accuracy: 0.01, "and the first step is a small one")
        clock.runFrames(for: 0.6)
        XCTAssertFalse(animated.isFadingTint)
        assertWash(animated.stripView.displayedWash, try classicWash(greenCover))
    }

    func testASongWithNoColourFadesBackToTheStylesBlack() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        animated.show(song("1", cover: try solidCover(0.8, 0.1, 0.1)), reduceMotion: false, reduceTransparency: false)

        animated.show(song("2", cover: try solidCover(0.5, 0.5, 0.5)), reduceMotion: false, reduceTransparency: false)

        XCTAssertNil(animated.stripView.albumTint, "a grey cover has no colour to give")
        XCTAssertTrue(animated.isFadingTint)
        clock.runFrames(for: 0.6)
        assertWash(animated.stripView.displayedWash, classicBlack)
        XCTAssertEqual(try XCTUnwrap(animated.stripView.albumTintLayerColor).alpha, TrackAnnouncementLayout.backgroundAlpha, accuracy: 0.001)

        // A song with no cover at all is the same black: nothing to change
        animated.show(song("3", cover: nil), reduceMotion: false, reduceTransparency: false)
        XCTAssertFalse(animated.isFadingTint)
    }

    func testAStripThatHasGoneComesBackInItsNewColourAtOnce() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        let blueCover = try solidCover(0.1, 0.3, 0.9)
        let greenCover = try solidCover(0.2, 0.7, 0.3)
        animated.show(song("1", cover: try solidCover(0.8, 0.1, 0.1)), reduceMotion: false, reduceTransparency: false)
        animated.show(song("2", cover: blueCover), reduceMotion: false, reduceTransparency: false)
        XCTAssertTrue(animated.isFadingTint)

        animated.hide()

        XCTAssertEqual(animated.phase, .hidden)
        XCTAssertFalse(animated.isFadingTint, "the change ends with the strip")
        assertWash(animated.stripView.displayedWash, try classicWash(blueCover), "at the colour it was heading for")

        animated.show(song("3", cover: greenCover), reduceMotion: false, reduceTransparency: false)
        XCTAssertFalse(animated.isFadingTint)
        assertWash(animated.stripView.displayedWash, try classicWash(greenCover))
    }

    func testReduceTransparencyMakesTheColourOpaque() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        let cover = try solidCover(0.9, 0.8, 0.2)

        animated.show(song("1", cover: cover), reduceMotion: false, reduceTransparency: true)

        let tint = try XCTUnwrap(AlbumTint.colour(of: cover))
        assertWash(animated.stripView.displayedWash, TrackAnnouncementWash(colour: tint, alpha: 1))
        XCTAssertEqual(try XCTUnwrap(animated.stripView.albumTintLayerColor).alpha, 1)
        XCTAssertGreaterThanOrEqual(tint.contrastWithWhite, 4.5, "white text stays readable on the colour drawn solid")
    }

    func testTurningTheTintOffAndOnWhileTheStripIsUp() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        let cover = try solidCover(0.8, 0.1, 0.1)
        animated.show(song("1", cover: cover), reduceMotion: false, reduceTransparency: false)

        animated.albumTintMode = .off

        XCTAssertNil(animated.stripView.albumTintLayerColor)
        XCTAssertTrue(animated.stripView.washDrawsTint, "the black is back at once")
        XCTAssertFalse(animated.isFadingTint)

        animated.albumTintMode = .strip

        XCTAssertTrue(animated.isFadingTint, "the colour fades in, as a late cover's does")
        assertWash(animated.stripView.displayedWash, classicBlack)
        clock.runFrames(for: 0.6)
        assertWash(animated.stripView.displayedWash, try classicWash(cover))
    }

    func testTheBlurTakesTheCoversColourInPlaceOfItsBlackWash() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.style = .blur
        XCTAssertNil(view.albumTintLayerColor)

        view.albumTintMode = .strip

        XCTAssertFalse(view.washDrawsTint)
        XCTAssertEqual(try XCTUnwrap(view.albumTintLayerColor).alpha, TrackAnnouncementLayout.blurTintAlpha, accuracy: 0.001, "no colour yet: the blur's own black, on the colour layer")
        view.setAlbumTint(AlbumTint.legible(OKLab(red: 0.8, green: 0.1, blue: 0.1)))
        XCTAssertEqual(try XCTUnwrap(view.albumTintLayerColor).alpha, TrackAnnouncementLayout.blurAlbumTintAlpha, accuracy: 0.001, "stronger than the black, so the colour reads through the blur")

        view.albumTintMode = .off
        XCTAssertNil(view.albumTintLayerColor)
        XCTAssertTrue(view.washDrawsTint)
    }

    /// Liquid Glass takes the colour through its own tint, so it keeps its lensing and edge
    func testTheAlbumTintColoursLiquidGlassThroughItsOwnTint() throws {
        try skipWithoutLiquidGlass()
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.style = .glass
        view.albumTintMode = .strip
        let tint = AlbumTint.legible(OKLab(red: 0.8, green: 0.1, blue: 0.1))

        view.setAlbumTint(tint)

        XCTAssertNil(view.albumTintLayerColor, "no layer over the glass")
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(view.backdropView as? NSGlassEffectView)
            let colour = try XCTUnwrap(glass.tintColor?.usingColorSpace(.sRGB))
            XCTAssertEqual(colour.alphaComponent, TrackAnnouncementLayout.glassAlbumTintAlpha, accuracy: 0.001)
            XCTAssertEqual(Double(colour.redComponent), tint.sRGB.red, accuracy: 0.001)
            XCTAssertEqual(Double(colour.greenComponent), tint.sRGB.green, accuracy: 0.001)
            XCTAssertEqual(Double(colour.blueComponent), tint.sRGB.blue, accuracy: 0.001)

            view.setAlbumTint(nil)
            XCTAssertNil(glass.tintColor, "no colour in the cover: the glass untinted, as it was built")

            view.setAlbumTint(tint)
            view.albumTintMode = .off
            XCTAssertNil(glass.tintColor, "turned off: the glass as it was built")
        }
        #endif
    }

    // MARK: The glow from behind the cover

    /// The classic strip's glow for `cover`: its light, as strong as the title allows
    private func classicGlow(_ cover: NSImage) throws -> TrackAnnouncementWash {
        let light = AlbumTint.light(try XCTUnwrap(AlbumTint.colour(of: cover)))
        return TrackAnnouncementWash(colour: light, alpha: AlbumTint.Glow.peak(for: light, most: 1))
    }

    func testTheGlowShinesFromBehindTheSleeveOverTheStylesBlack() throws {
        sleeveKnobs = TrackAnnouncementSleeveKnobs(breakout: true, tilt: false)
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .glow
        let cover = try solidCover(0.1, 0.3, 0.9)

        animated.show(song("1", cover: cover), reduceMotion: false, reduceTransparency: false)

        let view = animated.stripView
        XCTAssertFalse(animated.isFadingTint, "no fade on the way in")
        assertWash(view.displayedWash, try classicGlow(cover))
        assertWash(try XCTUnwrap(view.glowLight), try classicGlow(cover))
        XCTAssertGreaterThan(try XCTUnwrap(view.glowLight).colour.l, AlbumTint.lightness.upperBound, "a light, brighter than the whole-strip tint is allowed")
        // Under it, the classic strip's own black, on the colour layer rather than the wash
        XCTAssertFalse(view.washDrawsTint)
        let black = try XCTUnwrap(view.albumTintLayerColor)
        XCTAssertEqual(black.alpha, TrackAnnouncementLayout.backgroundAlpha, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(black.components).prefix(3).max() ?? 1, 0, accuracy: 0.001, "black")

        // From the sleeve's centre, full strength out to its edge
        let shape = try XCTUnwrap(view.glowShape)
        let sleeve = view.artworkFrame
        XCTAssertEqual(view.glowFrame, view.bounds, "the classic strip glows edge to edge")
        XCTAssertEqual(shape.centre.x, sleeve.midX, accuracy: 0.001)
        XCTAssertEqual(shape.centre.y, sleeve.midY, accuracy: 0.001)
        XCTAssertEqual(shape.core, TrackAnnouncementSleeve.size / 2 * animated.scale, accuracy: 0.001)
        XCTAssertEqual(shape.reach, AlbumTint.Glow.defaultReach * animated.scale, accuracy: 0.001)
    }

    func testTheGlowFadesFromSongToSongAndFromNothing() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .glow
        let redCover = try solidCover(0.8, 0.1, 0.1)
        let blueCover = try solidCover(0.1, 0.3, 0.9)
        animated.show(song("1", cover: redCover), reduceMotion: false, reduceTransparency: false)

        animated.show(song("2", cover: blueCover), reduceMotion: false, reduceTransparency: false)

        XCTAssertTrue(animated.isFadingTint)
        clock.runFrames(for: 0.25)
        assertWash(animated.stripView.displayedWash, .mix(try classicGlow(redCover), try classicGlow(blueCover), progress: 0.5), accuracy: 0.01)
        clock.runFrames(for: 0.3)
        assertWash(animated.stripView.displayedWash, try classicGlow(blueCover))

        // A grey cover puts the light out, and the strip is today's black
        animated.show(song("3", cover: try solidCover(0.5, 0.5, 0.5)), reduceMotion: false, reduceTransparency: false)
        clock.runFrames(for: 0.6)
        XCTAssertEqual(animated.stripView.displayedWash.alpha, 0)
        XCTAssertNil(animated.stripView.glowLight, "no glow layer at all")
        XCTAssertEqual(try XCTUnwrap(animated.stripView.albumTintLayerColor).alpha, TrackAnnouncementLayout.backgroundAlpha, accuracy: 0.001)

        // A late cover lights it again, growing in its own colour from nothing
        animated.refresh(song("3", cover: redCover))
        XCTAssertTrue(animated.isFadingTint)
        clock.runFrames(for: 0.25)
        let half = animated.stripView.displayedWash
        let red = try classicGlow(redCover)
        XCTAssertEqual(Double(half.alpha), Double(red.alpha) / 2, accuracy: 0.01)
        XCTAssertEqual(half.colour.l, red.colour.l, accuracy: 0.001, "the light's own colour, only weaker")
        clock.runFrames(for: 0.3)
        assertWash(animated.stripView.displayedWash, red)
    }

    func testChangingBetweenTheTintAndTheGlowWhileTheStripIsUp() throws {
        let clock = FakeClock()
        let animated = tintPanel(clock)
        defer { animated.orderOut(nil) }
        animated.albumTintMode = .strip
        let cover = try solidCover(0.8, 0.1, 0.1)
        animated.show(song("1", cover: cover), reduceMotion: false, reduceTransparency: false)
        assertWash(animated.stripView.displayedWash, try classicWash(cover))
        XCTAssertNil(animated.stripView.glowLight)

        animated.albumTintMode = .glow

        XCTAssertTrue(animated.isFadingTint, "the light comes up")
        XCTAssertEqual(try XCTUnwrap(animated.stripView.albumTintLayerColor).alpha, TrackAnnouncementLayout.backgroundAlpha, accuracy: 0.001, "the strip is back to its black under the light")
        XCTAssertEqual(animated.stripView.displayedWash.alpha, 0, "and the light starts from nothing")
        clock.runFrames(for: 0.6)
        assertWash(animated.stripView.displayedWash, try classicGlow(cover))

        animated.albumTintMode = .off

        XCTAssertNil(animated.stripView.glowLight)
        XCTAssertNil(animated.stripView.albumTintLayerColor)
        XCTAssertTrue(animated.stripView.washDrawsTint, "today's strip at once")
        XCTAssertFalse(animated.isFadingTint)
    }

    func testTheGlowLayersCircleIsRoundOnAWideStrip() {
        let glow = AlbumTint.Glow(centre: CGPoint(x: 68, y: 36), core: 56, reach: 480, halo: 10)
        let points = TrackAnnouncementGlowView.points(for: glow, in: CGSize(width: 1440, height: 104))
        XCTAssertEqual(points.start.x * 1440, 68, accuracy: 1e-9)
        XCTAssertEqual(points.start.y * 104, 36, accuracy: 1e-9)
        XCTAssertEqual((points.end.x - points.start.x) * 1440, 480, accuracy: 1e-9)
        XCTAssertEqual((points.end.y - points.start.y) * 104, 480, accuracy: 1e-9, "the same radius both ways, though the strip is far wider than tall")
    }

    /// The light is brightest by the artwork and gone at the far end, drawn where the view
    /// says: not upside down, and not off to one side
    func testTheGlowLayerDrawsItsLightBehindTheArtwork() throws {
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 900, height: TrackAnnouncementLayout.height))
        // The sleeve's centre is above the strip's middle, so the light is too
        view.breakout = true
        view.albumTintMode = .glow
        view.setAlbumTint(AlbumTint.legible(OKLab(red: 0.1, green: 0.3, blue: 0.9)))
        let gradient = try XCTUnwrap(view.glowLayer)
        XCTAssertEqual(gradient.type, .radial)
        XCTAssertEqual((gradient.colors ?? []).count, gradient.locations?.count)

        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        gradient.render(in: context)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        // The context's y counts up from the bottom, as the view's does, but its first row in
        // memory is the top one
        let alpha = { (x: CGFloat, y: CGFloat) -> Int in Int(data[((height - 1 - Int(y)) * width + Int(x)) * 4 + 3]) }
        let artwork = view.artworkFrame
        XCTAssertGreaterThan(artwork.midY, view.bounds.midY)
        let beside = alpha(artwork.maxX + 4, 60)
        XCTAssertGreaterThan(beside, 120, "bright just past the sleeve")
        XCTAssertGreaterThan(alpha(artwork.minX - 4, 60), 120, "on both sides of it")
        XCTAssertLessThan(alpha(artwork.maxX + 200, 60), beside - 60, "and much less further out")
        XCTAssertGreaterThan(alpha(artwork.maxX + 10, 100), alpha(artwork.maxX + 10, 2) + 10, "brighter near the strip's top edge, which is nearer the sleeve's centre: not upside down")
        XCTAssertEqual(alpha(CGFloat(width - 2), 2), 0, "nothing at the far end")
    }

    func testTheGlowStaysInsideLiquidGlassAndLeavesItsTintAlone() throws {
        try skipWithoutLiquidGlass()
        let view = TrackAnnouncementView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
        view.style = .glass
        view.albumTintMode = .glow

        view.setAlbumTint(AlbumTint.legible(OKLab(red: 0.8, green: 0.1, blue: 0.1)))

        XCTAssertEqual(view.glowFrame, view.backdropFrame, "the glass's shape")
        XCTAssertGreaterThan(view.glowCornerRadius, 0, "and its corners")
        XCTAssertEqual(Double(try XCTUnwrap(view.glowLight).alpha), Double(AlbumTint.Glow.strongest(for: .glass, opaque: false)), accuracy: 0.05)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(view.backdropView as? NSGlassEffectView)
            XCTAssertNil(glass.tintColor, "the glass keeps the tint it was built with")
        }
        #endif

        // Reduce Transparency covers the glass with black: the light goes edge to edge over it
        view.backgroundAlpha = 1
        XCTAssertEqual(view.glowFrame, view.bounds)
        XCTAssertEqual(view.glowCornerRadius, 0)
        XCTAssertEqual(try XCTUnwrap(view.albumTintLayerColor).alpha, 1, "the opaque black, under the light")
    }

}
