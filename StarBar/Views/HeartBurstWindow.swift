//
//  HeartBurstWindow.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-09.
//

import Cocoa
import os.log

/// The see-through window over the menu bar that the heart's burst is drawn in
/// (`MenuBarOverlayWindow`): the item leaves about 4 points around the heart, no room for a
/// ring, let alone dots. It is laid over the heart at each click and taken down when the burst
/// ends.
///
/// It has no clock of its own: `MenuBarRatingControl` steps it with the heart's own change, on
/// one display link and one `SteppedTimeline`, so the ring and the heart popping through it
/// can't drift apart, and a stalled main thread pauses both alike. The control takes it down
/// when the change ends.
final class HeartBurstWindow: MenuBarOverlayWindow {

    let burstView = HeartBurstView(frame: .zero)

    override init() {
        super.init()
        contentView = burstView
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
