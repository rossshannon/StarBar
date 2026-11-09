//
//  HeartBurstWindow.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-09.
//

import Cocoa
import os.log

/// A small see-through window over the menu bar that the heart's burst is drawn in.
///
/// StarBar's menu bar item is a window of its own, and nothing drawn in it can leave it: that
/// leaves about 4 points around the heart, no room for a ring, let alone dots. Widening the item
/// to make room is ruled out too, since on macOS 27 any narrowing slides the whole menu bar. So
/// the burst gets this window, laid over the heart at each click and taken down when the burst
/// ends: borderless, transparent, never key, ignoring the mouse so a quick second click still
/// reaches the heart underneath, one level above the menu bar's items, and on every Space.
/// Like the strip's panel it never goes through `WindowManager`, which would activate the app.
///
/// The burst is stepped by hand on a display link, as the strip's slide is, and its time is a
/// `SteppedTimeline`, so a stalled main thread pauses it rather than skipping it.
final class HeartBurstWindow: NSPanel {

    let burstView = HeartBurstView(frame: .zero)

    private var clock: RatingReminderClock
    private var timer: RatingReminderTimer?

    /// One level above the menu bar's items, so the ring and dots draw over the heart and its
    /// neighbours. Below pop-up menus, so an open menu stays on top.
    static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    /// - Parameter clock: steps the burst; a fake one in tests. By default a display link on
    ///   the window's screen, with a timer before macOS 14.
    init(clock: RatingReminderClock? = nil) {
        self.clock = clock ?? RunLoopClock()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = HeartBurstWindow.windowLevel
        ignoresMouseEvents = true
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isExcludedFromWindowsMenu = true
        setAccessibilityElement(false)
        contentView = burstView

        if clock == nil {
            self.clock = DisplayLinkClock(screen: { [weak self] in self?.screen })
        }
    }

    deinit {
        timer?.invalidate()
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    /// Where the window is put is where it goes. The heart is 12 points below the screen's top
    /// edge, so the window reaches above it; AppKit would otherwise push it down, off-centre.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    var isPlaying: Bool {
        return timer != nil
    }

    /// Burst around `heart`, the heart's frame in screen coordinates, and put the window away
    /// when the burst has finished. A burst already playing starts again.
    func play(around heart: NSRect, burst: HeartBurst, palette: HeartBurstPalette) {
        stop()
        // Whole points for the window; the burst is centred on the heart inside it
        let side = 2 * (burst.extent + 2).rounded(.up)
        let frame = NSRect(x: (heart.midX - side / 2).rounded(.down), y: (heart.midY - side / 2).rounded(.down),
                           width: side, height: side)
        setFrame(frame, display: false)
        burstView.frame = NSRect(origin: .zero, size: frame.size)
        burstView.centre = NSPoint(x: heart.midX - frame.minX, y: heart.midY - frame.minY)
        burstView.burst = burst
        burstView.palette = palette
        burstView.elapsed = 0
        burstView.change = .burst
        burstView.displayIfNeeded()
        orderFrontRegardless()
        os_log("%{public}s[%{public}ld], %{public}s: heart burst over the menu bar at %{public}s", ((#file as NSString).lastPathComponent), #line, #function, NSStringFromRect(frame))

        var timeline = SteppedTimeline(start: clock.now())
        // A real frame interval, never 0: before macOS 14 this is a Timer, and Foundation
        // clamps a non-positive interval to 0.1 ms
        timer = clock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            guard let self = self, self.timer != nil else { return }
            let elapsed = timeline.step(at: self.clock.now())
            if elapsed >= HeartBurst.duration {
                self.stop()
            } else {
                self.burstView.elapsed = elapsed
            }
        }
    }

    /// Take the burst down at once, wherever it has got to
    func stop() {
        timer?.invalidate()
        timer = nil
        burstView.change = nil
        orderOut(nil)
    }

}
