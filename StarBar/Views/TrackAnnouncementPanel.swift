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

    /// - Parameters:
    ///   - slideDuration: 0 applies the final state at once, for tests
    ///   - screens: the screens to choose from
    ///   - mouseLocation: where the pointer is, to pick the screen the user is looking at and
    ///     to put the see-through hole under it
    ///   - keyboard: how long ago a key went down, to clear the background while the user types
    ///   - clock: steps the slide; a fake one in tests. By default a display link on the
    ///     panel's screen, so each step lands on a refresh, with a timer before macOS 14.
    init(
        slideDuration: TimeInterval = TrackAnnouncementLayout.slideDuration,
        screens: @escaping () -> [NSScreen] = { NSScreen.screens },
        mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        keyboard: @escaping () -> KeyboardActivity = KeyboardActivity.system,
        clock: RatingReminderClock? = nil
    ) {
        self.slideDuration = slideDuration
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
        set { stripView.style = newValue }
    }

}

// MARK: - Presenter

extension TrackAnnouncementPanel: TrackAnnouncementPresenter {

    func show(_ announcement: TrackAnnouncement, reduceMotion: Bool, reduceTransparency: Bool) {
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
        stripView.announcement = announcement
        let transition = TrackAnnouncementPlacement.transition(reduceMotion: reduceMotion)

        switch phase {
        case .shown, .slidingIn:
            // Already on its way up or up: the new content is enough
            if isNewAnnouncement {
                speak(announcement)
            }
            return
        case .slidingOut:
            // Turn round from wherever the strip has got to
            speak(announcement)
            slide(in: true, transition: transition)
        case .hidden:
            place(on: chooseScreen())
            switch transition {
            case .slide:
                stripView.alphaValue = 1
                stripView.setFrameOrigin(TrackAnnouncementPlacement.stripOrigin(shown: false, scale: scale))
            case .fade:
                stripView.alphaValue = 0
                stripView.setFrameOrigin(TrackAnnouncementPlacement.stripOrigin(shown: true, scale: scale))
            }
            // Before the first frame is drawn, so a pointer already over the strip has its hole
            startSeeThrough()
            // Draw the first frame before the window shows, so the slide starts clean
            stripView.needsDisplay = true
            stripView.displayIfNeeded()
            orderFrontRegardless()
            // Every appearance is spoken, even of the same track again: the panel never takes
            // focus, so VoiceOver has no other way to notice it
            speak(announcement)
            slide(in: true, transition: transition)
        }
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
        guard phase != .hidden, stripView.announcement != announcement else { return }
        stripView.announcement = announcement
    }

    func hide() {
        guard phase == .shown || phase == .slidingIn else { return }
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
            }
        }

        let apply = { [weak self] (progress: Double) in
            guard let self = self else { return }
            let eased = CGFloat(TrackAnnouncementPlacement.easeInOut(progress))
            switch transition {
            case .slide:
                self.stripView.setFrameOrigin(CGPoint(x: 0, y: startY + (targetY - startY) * eased))
                self.updatePeephole()
            case .fade:
                self.stripView.alphaValue = startAlpha + (targetAlpha - startAlpha) * eased
            }
        }

        guard slideDuration > 0 else {
            apply(1)
            finish()
            return
        }

        let start = clock.now()
        slideTimer = clock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            guard let self = self, self.animationGeneration == generation else { return }
            let progress = min(1, self.clock.now().timeIntervalSince(start) / self.slideDuration)
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
        animationGeneration += 1
        slideTimer?.invalidate()
        slideTimer = nil
        orderOut(nil)
        phase = .hidden
        stopSeeThrough()
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
        os_log("%{public}s[%{public}ld], %{public}s: hole %{public}s (radius %.0f, feather %.0f), typing window %{public}s (radius %.0f, feather %.0f, pause %.1f s), last key %.1f s ago", ((#file as NSString).lastPathComponent), #line, #function, knobs.peephole ? "on" : "off", Double(knobs.radius), Double(knobs.feather), knobs.typingWindow ? "on" : "off", Double(knobs.typingRadius), Double(knobs.typingFeather), knobs.typingPause, keyboard().secondsSinceKeyDown)
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
        // The strip slides inside the panel, so its place on screen moves with it
        let stripOnScreen = stripView.frame.offsetBy(dx: frame.minX, dy: frame.minY)
        let hadHole = stripView.peephole != nil
        let pointer = mouseLocation()
        let onStripScreen = placedScreenFrame.map { $0.contains(pointer) } ?? true
        stripView.peephole = onStripScreen
            ? TrackAnnouncementSeeThrough.peephole(
                pointer: pointer,
                stripFrame: stripOnScreen,
                radius: seeThroughKnobs.radius * scale,
                feather: seeThroughKnobs.feather * scale
            )
            : nil
        if let hole = stripView.peephole, !hadHole {
            os_log("%{public}s[%{public}ld], %{public}s: hole opened at %.0f, %.0f in the strip", ((#file as NSString).lastPathComponent), #line, #function, Double(hole.centre.x), Double(hole.centre.y))
        } else if hadHole && stripView.peephole == nil {
            os_log("%{public}s[%{public}ld], %{public}s: hole closed", ((#file as NSString).lastPathComponent), #line, #function)
        }
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
