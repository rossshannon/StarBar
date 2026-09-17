//
//  TrackAnnouncementPanel.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Cocoa

/// The window the announcement strip slides up in. Borderless, click-through, on every
/// Space, one level below the Dock, not over full-screen apps, and never key: it must not
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
    /// Time for the slide, and its ticks: a display link when the system has one, else a timer
    private var clock: RatingReminderClock
    /// Bumped by every animation and by a cancel, so a stale timer tick does nothing
    private var animationGeneration = 0
    private var slideTimer: RatingReminderTimer?
    private var screenObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - slideDuration: 0 applies the final state at once, for tests
    ///   - screens: the screens to choose from
    ///   - mouseLocation: where the pointer is, to pick the screen the user is looking at
    ///   - clock: steps the slide; a fake one in tests. By default a display link on the
    ///     panel's screen, so each step lands on a refresh, with a timer before macOS 14.
    init(
        slideDuration: TimeInterval = TrackAnnouncementLayout.slideDuration,
        screens: @escaping () -> [NSScreen] = { NSScreen.screens },
        mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        clock: RatingReminderClock? = nil
    ) {
        self.slideDuration = slideDuration
        self.screens = screens
        self.mouseLocation = mouseLocation
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
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isExcludedFromWindowsMenu = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = false
        contentView = container
        container.addSubview(stripView)
        // Moving the strip must not redraw it: its contents change only with the announcement
        stripView.layerContentsRedrawPolicy = .onSetNeedsDisplay

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

}

// MARK: - Presenter

extension TrackAnnouncementPanel: TrackAnnouncementPresenter {

    func show(_ announcement: TrackAnnouncement, reduceMotion: Bool, reduceTransparency: Bool) {
        stripView.backgroundAlpha = reduceTransparency ? 1 : TrackAnnouncementLayout.backgroundAlpha
        let isNewAnnouncement = stripView.announcement != announcement
        stripView.announcement = announcement
        if isNewAnnouncement {
            NSAccessibility.post(
                element: stripView,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: announcement.accessibilityLabel,
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
        let transition = TrackAnnouncementPlacement.transition(reduceMotion: reduceMotion)

        switch phase {
        case .shown, .slidingIn:
            // Already on its way up or up: the new content is enough
            return
        case .slidingOut:
            // Turn round from wherever the strip has got to
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
            // Draw the first frame before the window shows, so the slide starts clean
            stripView.needsDisplay = true
            stripView.displayIfNeeded()
            orderFrontRegardless()
            slide(in: true, transition: transition)
        }
    }

    func hide() {
        guard phase == .shown || phase == .slidingIn else { return }
        // Fade back out if the strip faded in; the flag only matters for the way in
        let transition = lastTransition ?? .slide
        slide(in: false, transition: transition)
    }

    /// Move the strip up or down over `slideDuration`, stepping the view's frame from a
    /// 60 Hz timer with an ease-in-out curve, as Growl's NSAnimation did.
    ///
    /// The frame is stepped by hand rather than through `animator()`: on macOS 27 the panel's
    /// on-screen image follows the view's frame, not the layer's presentation values, so a
    /// Core Animation slide ran to completion without ever being drawn. A timer also keeps the
    /// motion testable with a fake clock.
    private func slide(in shown: Bool, transition: TrackAnnouncementPlacement.Transition) {
        phase = shown ? .slidingIn : .slidingOut
        lastTransition = transition
        slideTimer?.invalidate()
        slideTimer = nil
        animationGeneration += 1
        let generation = animationGeneration

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
            }
        }

        let apply = { [weak self] (progress: Double) in
            guard let self = self else { return }
            let eased = CGFloat(TrackAnnouncementPlacement.easeInOut(progress))
            switch transition {
            case .slide: self.stripView.setFrameOrigin(CGPoint(x: 0, y: startY + (targetY - startY) * eased))
            case .fade: self.stripView.alphaValue = startAlpha + (targetAlpha - startAlpha) * eased
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
        scale = TrackAnnouncementLayout.scale(forScreenHeight: screenFrame.height)
        stripView.scale = scale
        // The background runs behind a Dock at the side; the content stays clear of it
        stripView.leadingInset = max(0, visibleFrame.minX - screenFrame.minX)
        stripView.trailingInset = max(0, screenFrame.maxX - visibleFrame.maxX)
        let panelFrame = TrackAnnouncementPlacement.panelFrame(screenFrame: screenFrame, visibleFrame: visibleFrame, scale: scale)
        setFrame(panelFrame, display: false)
        contentView?.frame = NSRect(origin: .zero, size: panelFrame.size)
        stripView.frame = NSRect(origin: TrackAnnouncementPlacement.stripOrigin(shown: false, scale: scale), size: panelFrame.size)
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
    }

}

// MARK: - Display link clock

/// `RunLoopClock` for one-shot timers, and a display link for the slide's repeating ticks, so
/// each step lands on the screen's refresh instead of drifting against it. Falls back to the
/// run loop timer before macOS 14, where AppKit has no display link.
final class DisplayLinkClock: RatingReminderClock {

    /// Ticks below this interval are frame steps and go to the display link
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

    @objc private func tick(_ link: CADisplayLink) {
        action()
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }

}
