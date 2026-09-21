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

    override func setUp() {
        super.setUp()
        // The tests are hosted in the app, whose defaults may carry the glass experiment
        // knobs; read fixed values instead
        readKnobs = TrackAnnouncementGlassKnobs.read
        TrackAnnouncementGlassKnobs.read = { TrackAnnouncementGlassKnobs() }
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
        TrackAnnouncementGlassKnobs.read = readKnobs
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

    func testHideWhileSlidingInTurnsRound() {
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, clock: clock)
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
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, clock: clock)
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
        let clock = FakeClock()
        let animated = TrackAnnouncementPanel(slideDuration: 0.3, screens: { NSScreen.screens }, mouseLocation: { [unowned self] in self.mouse }, clock: clock)
        defer { animated.orderOut(nil) }
        animated.show(sample, reduceMotion: false, reduceTransparency: false)
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
        XCTAssertTrue(view.subviews.first === blur, "the backdrop sits under the drawn content")
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
        let view = TrackAnnouncementContentView(announcement: sample, frame: NSRect(x: 0, y: 0, width: 600, height: 96))
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
        XCTAssertFalse(view.subviews.contains { $0 is NSVisualEffectView })
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

}
