//
//  TrackAnnouncementPanel.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Cocoa
import os.log

/// The window the announcement strip slides up in. Borderless, click-through, on every
/// Space including full-screen ones, one level below the Dock, and never key: it must not
/// take focus from whatever the user is doing.
///
/// The panel spans the screen, sits still on the visible frame's bottom edge (above a Dock at
/// the bottom, behind one at the side) and clips; the strip view slides up inside it, drawn
/// at a scale that grows with the screen. Moving the window itself below the screen would
/// show on a display arranged underneath.
final class TrackAnnouncementPanel: NSPanel {

    enum Phase {
        case hidden
        case slidingIn
        case shown
        case slidingOut
    }

    private(set) var phase: Phase = .hidden
    /// How the last show or hide moved, for tests
    private(set) var lastTransition: TrackAnnouncementPlacement.Transition?
    let stripView: TrackAnnouncementView

    private let slideDuration: TimeInterval
    private let artworkFadeDuration: TimeInterval
    private var artworkFadeTimer: RatingReminderTimer?
    private let screens: () -> [NSScreen]
    private let mouseLocation: () -> NSPoint
    private let keyboard: () -> KeyboardActivity
    /// Time for the slide, and its ticks: a display link when the system has one, else a timer
    private var clock: RatingReminderClock
    /// Bumped by every animation and by a cancel, so a stale timer tick does nothing
    private var animationGeneration = 0
    private var slideTimer: RatingReminderTimer?
    private var screenObserver: NSObjectProtocol?

    /// Watches the pointer and the keyboard while the strip is on screen, to see through it
    private var seeThroughTimer: RatingReminderTimer?
    private var seeThroughKnobs = TrackAnnouncementSeeThroughKnobs()
    private var typing = TrackAnnouncementTyping()
    private var lastSeeThroughTick: Date?
    /// Whether the last tick found the user typing, to log only the changes
    private var wasTyping = false
    /// How far open the typing window is, 0 to 1
    private var typingProgress: CGFloat = 0
    /// The screen the strip was last placed on, so a pointer on another display near it
    /// opens no hole
    private var placedScreenFrame: CGRect?

    /// Steps the break-out sleeve's rise and its tilt towards the pointer while the strip is up
    private var sleeveTimer: RatingReminderTimer?
    private var sleeveKnobs = TrackAnnouncementSleeveKnobs()
    /// The rise under way: how long it has run, stepped with the slide so a stall pauses both
    /// alike, and where it started from (0, sunk into the strip, or part of the way down when
    /// the strip turned round on its way out). Nil once the sleeve is in place, or when there
    /// is none.
    private var sleeveRise: (time: SteppedTimeline, from: CGFloat)?
    private var lastSleeveTick: Date?
    /// The tilt as drawn, following the pointer's
    var sleeveTilt: TrackAnnouncementSleeve.Tilt {
        return stripView.sleeve.tilt
    }
    /// From the last show: no rise and no tilt under Reduce Motion
    private var reduceMotion = false
    /// Whether the last tick found the pointer near the sleeve, to log only the changes
    private var sleeveFollowsPointer = false

    /// Whether the panel is making its unseen first appearance (`warmUp`)
    private(set) var isWarmingUp = false
    private var warmUpTimer: RatingReminderTimer?
    /// Whether the strip has appeared since launch, seen or not: the warm-up is only worth
    /// making before the first
    private var hasAppeared = false

    /// - Parameters:
    ///   - slideDuration: 0 applies the final state at once, for tests
    ///   - artworkFadeDuration: how long a cover that arrives after the strip went up takes to
    ///     fade in over the placeholder; 0 draws it at once
    ///   - screens: the screens to choose from
    ///   - mouseLocation: where the pointer is, to pick the screen the user is looking at and
    ///     to put the see-through hole under it
    ///   - keyboard: how long ago a key went down, to clear the background while the user types
    ///   - clock: steps the slide; a fake one in tests. By default a display link on the
    ///     panel's screen, so each step lands on a refresh, with a timer before macOS 14.
    init(
        slideDuration: TimeInterval = TrackAnnouncementLayout.slideDuration,
        artworkFadeDuration: TimeInterval = TrackAnnouncementLayout.artworkFadeDuration,
        screens: @escaping () -> [NSScreen] = { NSScreen.screens },
        mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        keyboard: @escaping () -> KeyboardActivity = KeyboardActivity.system,
        clock: RatingReminderClock? = nil
    ) {
        self.slideDuration = slideDuration
        self.artworkFadeDuration = artworkFadeDuration
        self.screens = screens
        self.mouseLocation = mouseLocation
        self.keyboard = keyboard
        self.clock = clock ?? RunLoopClock()
        let size = CGSize(width: 800, height: TrackAnnouncementLayout.height)
        stripView = TrackAnnouncementView(announcement: .preview, frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Growl's panel, in AppKit's current names. Growl sat above the Dock; this sits just
        // below it, so a Dock at the side draws over the strip instead of being covered.
        level = TrackAnnouncementPanel.windowLevel
        ignoresMouseEvents = true
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // fullScreenAuxiliary lets the strip join a full-screen Space; without it, ordering a
        // window front while a full-screen app is up can switch Spaces, which is far worse
        // than a strip over the app
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isExcludedFromWindowsMenu = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = false
        contentView = container
        container.addSubview(stripView)
        // Above the strip, and beside it rather than inside it, so it can stand above the
        // strip's top edge; it follows the strip as it slides
        container.addSubview(stripView.sleeve)

        if clock == nil {
            self.clock = DisplayLinkClock(screen: { [weak self] in self?.screen })
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenParametersDidChange()
        }
    }

    deinit {
        slideTimer?.invalidate()
        seeThroughTimer?.invalidate()
        warmUpTimer?.invalidate()
        sleeveTimer?.invalidate()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    /// Above every ordinary and floating window, one step below the Dock
    static let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)

    /// The scale the strip is drawn at, from the screen it was last placed on
    private(set) var scale: CGFloat = 1

    /// The strip's background, from Preferences
    var style: TrackAnnouncementStyle {
        get { return stripView.style }
        set {
            stripView.style = newValue
            // The glass's side insets move the sleeve with the rest of the content
            layoutSleeve()
        }
    }

}

// MARK: - Presenter

extension TrackAnnouncementPanel: TrackAnnouncementPresenter {

    func show(_ announcement: TrackAnnouncement, reduceMotion: Bool, reduceTransparency: Bool) {
        // A song arriving during the warm-up gets a clean start of its own
        if isWarmingUp {
            endWarmUp()
        }
        hasAppeared = true
        self.reduceMotion = reduceMotion
        stripView.backgroundAlpha = reduceTransparency ? 1 : TrackAnnouncementLayout.backgroundAlpha
        // Reduce Transparency asks for a solid background under the text; seeing through the
        // strip takes it away, so neither the hole nor the typing window opens under it
        if reduceTransparency {
            stopSeeThrough()
        } else if phase != .hidden {
            // A song arriving while the strip is up, after an appearance under Reduce
            // Transparency: watch again. From hidden, the watcher starts once the strip is placed.
            startSeeThrough()
        }
        let isNewAnnouncement = stripView.announcement != announcement
        // A new song's artwork, or the placeholder, shows at once; only a cover that comes
        // later fades in
        stopArtworkFade()
        stripView.artworkFade = 1
        stripView.announcement = announcement
        let transition = TrackAnnouncementPlacement.transition(reduceMotion: reduceMotion)

        switch phase {
        case .shown, .slidingIn:
            // Already on its way up or up: the new content is enough, but a sleeve that stopped
            // ticking under Reduce Motion follows the pointer again once the setting is off
            if isNewAnnouncement {
                speak(announcement)
            }
            if sleeveTilts {
                startSleeve()
            }
            return
        case .slidingOut:
            // Turn round from wherever the strip has got to
            speak(announcement)
            slide(in: true, transition: transition)
        case .hidden:
            appear(transition: transition)
            // Every appearance is spoken, even of the same track again: the panel never takes
            // focus, so VoiceOver has no other way to notice it
            speak(announcement)
            slide(in: true, transition: transition)
        }
    }

    /// Put the strip at the start of its way in on the screen the user is looking at, draw it,
    /// and order the panel in, ready for `slide(in:transition:)`
    private func appear(transition: TrackAnnouncementPlacement.Transition) {
        // Read once per appearance, so a changed default applies from the next song
        sleeveKnobs = TrackAnnouncementSleeveKnobs.read()
        stripView.breakout = sleeveKnobs.breakout
        place(on: chooseScreen())
        switch transition {
        case .slide:
            stripView.alphaValue = 1
            stripView.setFrameOrigin(TrackAnnouncementPlacement.stripOrigin(shown: false, scale: scale))
        case .fade:
            stripView.alphaValue = 0
            stripView.setFrameOrigin(TrackAnnouncementPlacement.stripOrigin(shown: true, scale: scale))
        }
        // The sleeve starts sunk into the strip and rises out of it as the strip slides
        // in; a fade, which is what Reduce Motion asks for, brings it in already in place
        stripView.sleeve.rise = transition == .slide ? 0 : 1
        layoutSleeve()
        // Before the first frame is drawn, so a pointer already over the strip has its hole
        startSeeThrough()
        // Draw the first frame before the window shows, so the slide starts clean
        stripView.needsDisplay = true
        stripView.displayIfNeeded()
        orderFrontRegardless()
    }

    /// Ask VoiceOver to read the announcement. Posted with the panel, which is on screen;
    /// a view inside a window that is never key does not reach VoiceOver.
    private func speak(_ announcement: TrackAnnouncement) {
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement.accessibilityLabel,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    func refresh(_ announcement: TrackAnnouncement) {
        guard !isWarmingUp, phase != .hidden, stripView.announcement != announcement else { return }
        let coverArrived = stripView.announcement.identity == announcement.identity
            && stripView.announcement.artwork == nil && announcement.artwork != nil
        stripView.announcement = announcement
        if coverArrived {
            fadeInArtwork()
        }
    }

    /// Cross-fade from the placeholder to a cover that arrived after the strip went up
    /// (Spotify's, or Apple's for a song Music had none for), over `artworkFadeDuration`.
    ///
    /// Stepped on the slide's clock, as the slide and the fade are, rather than with a
    /// `CATransition`: on macOS 27 a Core Animation animation on this panel ran to completion
    /// without ever being drawn.
    private func fadeInArtwork() {
        stopArtworkFade()
        guard artworkFadeDuration > 0 else {
            stripView.artworkFade = 1
            return
        }
        stripView.artworkFade = 0
        // A stall pauses the fade rather than skipping it, as it does the slide
        var timeline = SteppedTimeline(start: clock.now())
        artworkFadeTimer = clock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            guard let self = self else { return }
            let progress = min(1, timeline.step(at: self.clock.now()) / self.artworkFadeDuration)
            self.stripView.artworkFade = CGFloat(TrackAnnouncementPlacement.easeInOut(progress))
            if progress >= 1 {
                self.stopArtworkFade()
            }
        }
    }

    private func stopArtworkFade() {
        artworkFadeTimer?.invalidate()
        artworkFadeTimer = nil
    }

    func hide() {
        guard !isWarmingUp, phase == .shown || phase == .slidingIn else { return }
        // Fade back out if the strip faded in; the flag only matters for the way in
        let transition = lastTransition ?? .slide
        slide(in: false, transition: transition)
    }

    /// Move the strip up or down over `slideDuration`, stepping the view's frame on each
    /// display refresh with an ease-in-out curve, as Growl's NSAnimation did.
    ///
    /// The frame is stepped by hand rather than through `animator()`: on macOS 27 the panel's
    /// on-screen image follows the view's frame, not the layer's presentation values, so a
    /// Core Animation slide ran to completion without ever being drawn. Stepping also keeps
    /// the motion testable with a fake clock.
    ///
    /// The time is a `SteppedTimeline`, so a main thread held up by Apple Events pauses the
    /// slide where it was drawn instead of finishing it unseen.
    private func slide(in shown: Bool, transition: TrackAnnouncementPlacement.Transition) {
        phase = shown ? .slidingIn : .slidingOut
        lastTransition = transition
        slideTimer?.invalidate()
        slideTimer = nil
        animationGeneration += 1
        let generation = animationGeneration

        // Turning round from the other kind of transition: settle the property this one
        // doesn't move, or the strip would hold half faded or half off screen
        switch transition {
        case .slide: stripView.alphaValue = 1
        case .fade: stripView.setFrameOrigin(TrackAnnouncementPlacement.stripOrigin(shown: true, scale: scale))
        }
        layoutSleeve()
        // The sleeve rises out of the strip as it comes up, and sinks back into it on the way
        // down, on the slide's own steps below
        let sinkFrom = stripView.sleeve.rise
        if stripView.breakout {
            if shown {
                beginSleeveRise(transition: transition)
            } else {
                sleeveRise = nil
            }
        }

        let startY = stripView.frame.origin.y
        let targetY = TrackAnnouncementPlacement.stripOrigin(shown: shown, scale: scale).y
        let startAlpha = stripView.alphaValue
        let targetAlpha: CGFloat = shown ? 1 : 0

        let finish = { [weak self] in
            guard let self = self, self.animationGeneration == generation else { return }
            if shown {
                self.phase = .shown
            } else {
                self.orderOut(nil)
                self.phase = .hidden
                self.stopSeeThrough()
                self.stopSleeve()
            }
        }

        let apply = { [weak self] (progress: Double) in
            guard let self = self else { return }
            let eased = CGFloat(TrackAnnouncementPlacement.easeInOut(progress))
            switch transition {
            case .slide:
                self.stripView.setFrameOrigin(CGPoint(x: 0, y: startY + (targetY - startY) * eased))
                self.updatePeephole()
                if !shown && self.stripView.breakout {
                    // Down into the strip, so it is out of sight when the strip is
                    self.stripView.sleeve.rise = TrackAnnouncementSleeve.sink(from: sinkFrom, eased: eased)
                }
            case .fade:
                self.stripView.alphaValue = startAlpha + (targetAlpha - startAlpha) * eased
            }
            // The sleeve rides with the strip on the same step, so the two never part
            self.layoutSleeve()
        }

        guard slideDuration > 0 else {
            apply(1)
            finish()
            return
        }

        var timeline = SteppedTimeline(start: clock.now())
        slideTimer = clock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            guard let self = self, self.animationGeneration == generation else { return }
            let progress = min(1, timeline.step(at: self.clock.now()) / self.slideDuration)
            apply(progress)
            if progress >= 1 {
                self.slideTimer?.invalidate()
                self.slideTimer = nil
                finish()
            }
        }
    }

    /// Size the panel to the bottom of `screen`'s visible frame, scaled to the screen, and
    /// the strip to match
    private func place(on screen: NSScreen?) {
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        placedScreenFrame = screen?.frame
        scale = TrackAnnouncementLayout.scale(forScreenHeight: screenFrame.height)
        stripView.scale = scale
        // The background runs behind a Dock at the side; the content stays clear of it
        stripView.leadingInset = max(0, visibleFrame.minX - screenFrame.minX)
        stripView.trailingInset = max(0, screenFrame.maxX - visibleFrame.maxX)
        let panelFrame = TrackAnnouncementPlacement.panelFrame(screenFrame: screenFrame, visibleFrame: visibleFrame, scale: scale)
        setFrame(panelFrame, display: false)
        contentView?.frame = NSRect(origin: .zero, size: panelFrame.size)
        stripView.frame = NSRect(
            origin: TrackAnnouncementPlacement.stripOrigin(shown: false, scale: scale),
            size: TrackAnnouncementPlacement.stripSize(panelFrame: panelFrame, scale: scale)
        )
    }

    /// The screen under the pointer, else the main screen
    private func chooseScreen() -> NSScreen? {
        let screens = self.screens()
        let mouse = mouseLocation()
        return screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? screens.first
    }

    /// A display was added, removed or rearranged: rather than let AppKit move the strip to
    /// another screen, take it down
    private func screenParametersDidChange() {
        guard phase != .hidden else { return }
        if isWarmingUp {
            endWarmUp()
        } else {
            takeDown()
        }
    }

    /// Take the strip away at once, wherever it has got to
    private func takeDown() {
        animationGeneration += 1
        slideTimer?.invalidate()
        slideTimer = nil
        stopArtworkFade()
        orderOut(nil)
        phase = .hidden
        stopSeeThrough()
        stopSleeve()
    }

    /// Whether anything the user can see is moving: the strip sliding in or out, or the
    /// sleeve rising. A main thread held up meanwhile stalls the motion where it is, so
    /// `iTunesRadioStation` holds back a repeated notification from Music, and the reads it
    /// sets off, until this is false. The pointer's tilt doesn't count: it can run for as
    /// long as the strip is up, and catches up after a stall by design.
    var isMoving: Bool {
        guard !isWarmingUp else { return false }
        return phase == .slidingIn || phase == .slidingOut || sleeveRise != nil
    }

}

// MARK: - Warming up

extension TrackAnnouncementPanel {

    /// How long the warm-up keeps the panel in: the slide in, the sleeve's rise, and time over
    /// for the one-time work it is there to set off, which ended 146 to 167 ms after the first
    /// strip was announced when it was measured
    static let warmUpDuration: TimeInterval = 1.0

    /// The panel's alpha while it warms up. Not 0: a window that draws nothing may be left out
    /// of compositing altogether, and the warm-up needs it drawn as a song's strip is. At 1%
    /// the brightest pixel of the strip moves what is under it by under three levels in 255.
    static let warmUpAlpha: CGFloat = 0.01

    /// Make the strip's first appearance now, unseen, so the one-time cost of first drawing
    /// it is paid before a song needs it.
    ///
    /// Measured on macOS 27 on 2026-11-03, the first strip after every launch held for about
    /// 50 ms, 84 to 100 ms into its slide, with the break-out sleeve on and off alike. The hold
    /// ended as the main thread logged "IOSurface Compression Enabled" (Core Animation) and
    /// Metal was set up on a new thread; no later strip held. So the warm-up goes through
    /// everything a song's strip does, through the same code, with a cover decoded from JPEG
    /// data as Music's are: placed on the screen, drawn, ordered in, slid up on a display
    /// link and the sleeve risen, then taken down at once. Only the panel's alpha differs,
    /// and nothing is spoken.
    ///
    /// Only before the strip has first appeared, and only while it is hidden. A song arriving
    /// meanwhile ends the warm-up and starts its own strip from the beginning.
    func warmUp(reduceMotion: Bool, reduceTransparency: Bool, duration: TimeInterval = TrackAnnouncementPanel.warmUpDuration) {
        guard !hasAppeared, phase == .hidden else { return }
        hasAppeared = true
        isWarmingUp = true
        os_log("%{public}s[%{public}ld], %{public}s: warming up the strip unseen, so the first song's doesn't wait for Core Animation's first-use setup", ((#file as NSString).lastPathComponent), #line, #function)
        alphaValue = TrackAnnouncementPanel.warmUpAlpha
        self.reduceMotion = reduceMotion
        stripView.backgroundAlpha = reduceTransparency ? 1 : TrackAnnouncementLayout.backgroundAlpha
        stopArtworkFade()
        stripView.artworkFade = 1
        stripView.announcement = TrackAnnouncementPanel.warmUpAnnouncement
        let transition = TrackAnnouncementPlacement.transition(reduceMotion: reduceMotion)
        appear(transition: transition)
        slide(in: true, transition: transition)
        warmUpTimer = clock.schedule(after: duration, repeats: false) { [weak self] in
            self?.endWarmUp()
        }
    }

    /// Take the warm-up down, and put the panel's alpha back for the first song
    private func endWarmUp() {
        guard isWarmingUp else { return }
        warmUpTimer?.invalidate()
        warmUpTimer = nil
        takeDown()
        isWarmingUp = false
        alphaValue = 1
        os_log("%{public}s[%{public}ld], %{public}s: warm-up done", ((#file as NSString).lastPathComponent), #line, #function)
    }

    /// The sample strip, with a cover decoded from JPEG data, as a cover read from Music is
    /// (`iTunesTrack.firstArtworkImage`), at the 600 pixels a cover usually has
    static var warmUpAnnouncement: TrackAnnouncement {
        let sample = TrackAnnouncement.preview
        return TrackAnnouncement(copying: sample, artwork: jpegCover(drawing: sample.artwork) ?? sample.artwork)
    }

    private static func jpegCover(drawing image: NSImage?, pixels: Int = 600) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.darkGray.setFill()
        rect.fill()
        image?.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return NSImage(data: data)
    }

}

// MARK: - The break-out sleeve

extension TrackAnnouncementPanel {

    /// Put the break-out sleeve over the strip's artwork slot, wherever the strip has slid to,
    /// and fade it with the strip. Called on every step of the slide, so the two never part.
    fileprivate func layoutSleeve() {
        let sleeve = stripView.sleeve
        guard stripView.breakout else { return }
        sleeve.frame = stripView.sleeveFrame.offsetBy(dx: stripView.frame.minX, dy: stripView.frame.minY)
        sleeve.alphaValue = stripView.alphaValue
    }

    /// Start the sleeve rising out of the strip from wherever it is, as the strip slides in:
    /// sunk on a new appearance, or part of the way down when the strip turns round on its way
    /// out. A fade brings it in already in place.
    fileprivate func beginSleeveRise(transition: TrackAnnouncementPlacement.Transition) {
        let sleeve = stripView.sleeve
        if transition == .slide && sleeve.rise < 1 {
            sleeveRise = (SteppedTimeline(start: clock.now()), sleeve.rise)
        } else {
            sleeveRise = nil
            sleeve.rise = 1
        }
        startSleeve()
    }

    /// Step the sleeve's rise and its tilt towards the pointer on each display refresh, from
    /// the start of the slide in until the strip has gone. A real frame interval, never 0:
    /// before macOS 14 this is a Timer, and Foundation clamps a non-positive interval to 0.1 ms.
    ///
    /// The panel ignores the mouse, so the pointer is read rather than followed, as the
    /// see-through watcher reads it; the two are separate because that one stops under Reduce
    /// Transparency and this one under Reduce Motion.
    fileprivate func startSleeve() {
        guard stripView.breakout, sleeveTimer == nil else { return }
        lastSleeveTick = nil
        os_log("%{public}s[%{public}ld], %{public}s: break-out sleeve, %{public}s, tilt %{public}s", ((#file as NSString).lastPathComponent), #line, #function, sleeveRise == nil ? "in place" : "rising", sleeveTilts ? "on" : (sleeveKnobs.tilt ? "off under Reduce Motion" : "off"))
        sleeveTimer = clock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            self?.tickSleeve()
        }
        tickSleeve()
    }

    /// Stop stepping, and put the sleeve back at rest for the next appearance
    fileprivate func stopSleeve() {
        sleeveTimer?.invalidate()
        sleeveTimer = nil
        lastSleeveTick = nil
        sleeveRise = nil
        sleeveFollowsPointer = false
        stripView.sleeve.tilt = .rest
        stripView.sleeve.rise = 1
    }

    /// Whether the sleeve follows the pointer this appearance
    private var sleeveTilts: Bool {
        return sleeveKnobs.tilt && !reduceMotion
    }

    private func tickSleeve() {
        guard sleeveTimer != nil else { return }
        let now = clock.now()
        let elapsed = lastSleeveTick.map { now.timeIntervalSince($0) } ?? 0
        lastSleeveTick = now

        if var rise = sleeveRise {
            let since = rise.time.step(at: now)
            if since >= TrackAnnouncementSleeve.riseDelay + TrackAnnouncementSleeve.riseDuration {
                sleeveRise = nil
                stripView.sleeve.rise = 1
            } else {
                sleeveRise = rise
                stripView.sleeve.rise = TrackAnnouncementSleeve.rise(elapsed: since, from: rise.from)
            }
        }

        let target = sleeveTilts ? pointerTilt() : .rest
        let following = target != .rest
        if following != sleeveFollowsPointer {
            sleeveFollowsPointer = following
            os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, following ? String(format: "pointer near: tipping the sleeve to %.1f°, %.1f°", Double(target.x), Double(target.y)) : "pointer gone: the sleeve settles back")
        }
        // The view ignores a tilt that hasn't changed
        stripView.sleeve.tilt = TrackAnnouncementSleeve.approach(sleeveTilt, toward: target, elapsed: elapsed)

        // Risen, still, and with no pointer to follow: nothing more to step this appearance
        if !sleeveTilts && sleeveRise == nil && sleeveTilt == .rest {
            sleeveTimer?.invalidate()
            sleeveTimer = nil
        }
    }

    /// The tilt for where the pointer is now: towards it when it is near the sleeve on the
    /// strip's screen, at rest otherwise
    private func pointerTilt() -> TrackAnnouncementSleeve.Tilt {
        guard let pointer = pointerOnStripScreen() else { return .rest }
        // The sleeve's square on screen, where it rests
        let strip = stripOnScreen
        let slot = stripView.artworkFrame.offsetBy(dx: strip.minX, dy: strip.minY)
        let offset = CGVector(dx: (pointer.x - slot.midX) / scale, dy: (pointer.y - slot.midY) / scale)
        return TrackAnnouncementSleeve.tilt(pointerOffset: offset)
    }

}

// MARK: - Seeing through

extension TrackAnnouncementPanel {

    /// Start watching the pointer and the keyboard, once per appearance. The knobs are read
    /// here, so a changed default applies from the next song.
    ///
    /// The panel ignores the mouse, so no tracking area or mouse-moved event ever reaches it;
    /// the pointer is read on each display refresh instead, and only while the strip is up.
    private func startSeeThrough() {
        guard seeThroughTimer == nil, stripView.backgroundAlpha < 1 else { return }
        seeThroughKnobs = TrackAnnouncementSeeThroughKnobs.read()
        let knobs = seeThroughKnobs
        stripView.peepholeKeepOpacity = knobs.peepholeKeep
        os_log("%{public}s[%{public}ld], %{public}s: hole %{public}s (radius %.0f, feather %.0f, keeps %.0f%% behind the text), typing window %{public}s (radius %.0f, feather %.0f, pause %.1f s), last key %.1f s ago", ((#file as NSString).lastPathComponent), #line, #function, knobs.peephole ? "on" : "off", Double(knobs.radius), Double(knobs.feather), Double(knobs.peepholeKeep * 100), knobs.typingWindow ? "on" : "off", Double(knobs.typingRadius), Double(knobs.typingFeather), knobs.typingPause, keyboard().secondsSinceKeyDown)
        // Nothing to watch for: don't tick at the display's rate for nothing
        guard knobs.peephole || knobs.typingWindow else { return }
        typing = TrackAnnouncementTyping()
        wasTyping = false
        typingProgress = 0
        lastSeeThroughTick = nil
        // A real frame interval, never 0: before macOS 14 this is a Timer, and Foundation
        // clamps a non-positive interval to 0.1 ms
        seeThroughTimer = clock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            self?.updateSeeThrough()
        }
        updateSeeThrough()
    }

    /// Stop watching, and put the whole background back for the next appearance
    private func stopSeeThrough() {
        seeThroughTimer?.invalidate()
        seeThroughTimer = nil
        lastSeeThroughTick = nil
        stripView.peephole = nil
        typingProgress = 0
        stripView.setTypingWindow(radius: 0, feather: 0, progress: 0)
    }

    private func updateSeeThrough() {
        guard seeThroughTimer != nil else { return }
        // The keyboard straight after the clock: the pair places the last key in time, and
        // drawing the first hole in between would age the key by the drawing time
        let now = clock.now()
        let keys = seeThroughKnobs.typingWindow ? keyboard() : nil
        let isFirstTick = lastSeeThroughTick == nil
        let elapsed = lastSeeThroughTick.map { now.timeIntervalSince($0) } ?? 0
        lastSeeThroughTick = now

        updatePeephole()

        if let keys = keys {
            typing.observe(keys, at: now)
            let isTyping = typing.isTyping(at: now, pause: seeThroughKnobs.typingPause)
            if isTyping != wasTyping {
                wasTyping = isTyping
                os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, isTyping ? "typing: opening the window" : "typing stopped: closing the window")
            }
            let target: CGFloat = isTyping ? 1 : 0
            // The first tick of an appearance jumps straight there: the strip is not up yet
            let progress = isFirstTick
                ? target
                : TrackAnnouncementSeeThrough.typingProgress(typingProgress, toward: target, elapsed: elapsed)
            if progress != typingProgress || isFirstTick {
                typingProgress = progress
                stripView.setTypingWindow(
                    radius: seeThroughKnobs.typingRadius * scale,
                    feather: seeThroughKnobs.typingFeather * scale,
                    centreHeight: seeThroughKnobs.typingCentreHeight * scale,
                    progress: progress
                )
            }
        }
    }

    /// Put the hole under the pointer, or take it away. Also called from each step of the
    /// slide, which runs on its own display link: the strip moves under a still pointer, and
    /// the hole would otherwise trail it by a frame.
    fileprivate func updatePeephole() {
        guard seeThroughTimer != nil, seeThroughKnobs.peephole else { return }
        let hadHole = stripView.peephole != nil
        stripView.peephole = pointerOnStripScreen().flatMap {
            TrackAnnouncementSeeThrough.peephole(
                pointer: $0,
                stripFrame: stripOnScreen,
                radius: seeThroughKnobs.radius * scale,
                feather: seeThroughKnobs.feather * scale
            )
        }
        if let hole = stripView.peephole, !hadHole {
            os_log("%{public}s[%{public}ld], %{public}s: hole opened at %.0f, %.0f in the strip", ((#file as NSString).lastPathComponent), #line, #function, Double(hole.centre.x), Double(hole.centre.y))
        } else if hadHole && stripView.peephole == nil {
            os_log("%{public}s[%{public}ld], %{public}s: hole closed", ((#file as NSString).lastPathComponent), #line, #function)
        }
    }

    /// The strip's frame on screen: it slides inside the panel, so this moves with it
    fileprivate var stripOnScreen: NSRect {
        return stripView.frame.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// Where the pointer is, or nil when it is on another display than the strip's: there it
    /// opens no hole and tips nothing, however close it is
    fileprivate func pointerOnStripScreen() -> NSPoint? {
        let pointer = mouseLocation()
        if let screen = placedScreenFrame, !screen.contains(pointer) {
            return nil
        }
        return pointer
    }

}

// MARK: - Display link clock

/// `RunLoopClock` for one-shot timers, and a display link for the slide's repeating ticks, so
/// each step lands on the screen's refresh instead of drifting against it. Falls back to the
/// run loop timer before macOS 14, where AppKit has no display link.
///
/// A repeating interval under `frameInterval` means "every frame": the display link ticks at
/// the screen's own rate and ignores the exact interval, so callers must measure elapsed time
/// with `now()` rather than count ticks, as `TrackAnnouncementPanel.slide` does.
final class DisplayLinkClock: RatingReminderClock {

    /// Repeating intervals below this are frame steps and go to the display link
    static let frameInterval: TimeInterval = 0.1

    private let screen: () -> NSScreen?
    private let fallback = RunLoopClock()

    init(screen: @escaping () -> NSScreen?) {
        self.screen = screen
    }

    func now() -> Date {
        return Date()
    }

    func schedule(after seconds: TimeInterval, repeats: Bool, action: @escaping () -> Void) -> RatingReminderTimer {
        if repeats, seconds < DisplayLinkClock.frameInterval, #available(macOS 14.0, *),
           let screen = screen() ?? NSScreen.main {
            return DisplayLinkTimer(screen: screen, action: action)
        }
        return fallback.schedule(after: seconds, repeats: repeats, action: action)
    }

}

@available(macOS 14.0, *)
private final class DisplayLinkTimer: NSObject, RatingReminderTimer {

    private var link: CADisplayLink?
    private let action: () -> Void

    init(screen: NSScreen, action: @escaping () -> Void) {
        self.action = action
        super.init()
        let link = screen.displayLink(target: self, selector: #selector(DisplayLinkTimer.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    deinit {
        invalidate()
    }

    @objc private func tick(_ link: CADisplayLink) {
        // The action may invalidate this timer, which drops the display link's hold on it
        withExtendedLifetime(self) { action() }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }

}
