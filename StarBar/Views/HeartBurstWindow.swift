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
/// It has no clock of its own: `MenuBarRatingControl` steps it with the heart's own change, on
/// one display link and one `SteppedTimeline`, so the ring and the heart popping through it
/// can't drift apart, and a stalled main thread pauses both alike. The control takes it down
/// when the change ends.
final class HeartBurstWindow: NSPanel {

    let burstView = HeartBurstView(frame: .zero)

    /// One level above the menu bar's items, so the ring and dots draw over the heart and its
    /// neighbours. Below pop-up menus, so an open menu stays on top.
    static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    init() {
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
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    /// Where the window is put is where it goes. The heart is 12 points below the screen's top
    /// edge, so the window reaches above it; AppKit would otherwise push it down, off-centre.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    var isPlaying: Bool {
        return burstView.change != nil
    }

    /// Put up the burst's first frame around `heart`, the heart's frame in screen coordinates.
    /// A burst already playing starts again.
    func play(around heart: NSRect, burst: HeartBurst, palette: HeartBurstPalette) {
        let square = HeartBurstView.square(around: NSPoint(x: heart.midX, y: heart.midY), extent: burst.extent)
        // The burst view is the content view, so it takes the window's size
        setFrame(square.frame, display: false)
        burstView.centre = square.centre
        burstView.burst = burst
        burstView.palette = palette
        burstView.elapsed = 0
        burstView.change = .burst
        burstView.displayIfNeeded()
        orderFrontRegardless()
        os_log("%{public}s[%{public}ld], %{public}s: heart burst over the menu bar at %{public}s", ((#file as NSString).lastPathComponent), #line, #function, NSStringFromRect(square.frame))
    }

    /// Draw the burst `elapsed` seconds in, if it is playing
    func step(to elapsed: TimeInterval) {
        guard isPlaying else { return }
        burstView.elapsed = elapsed
    }

    /// Take the burst down at once, wherever it has got to
    func stop() {
        burstView.change = nil
        orderOut(nil)
    }

}
