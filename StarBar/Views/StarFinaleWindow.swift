//
//  StarFinaleWindow.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-24.
//

import Cocoa
import os.log

/// The see-through window over the menu bar that the five-star finale is drawn in
/// (`MenuBarOverlayWindow`): its small stars fly about 30 points below the menu bar's stars,
/// which nothing drawn in the item can do. It is laid over the stars when a song is given five
/// stars and taken down when the finale ends.
///
/// It has no clock of its own: `MenuBarRatingControl` steps it with the stars' flourish, on
/// one display link and one `SteppedTimeline`, so each small star leaves as the run reaches
/// its star, and a stalled main thread pauses both alike. The control takes it down when the
/// flourish ends.
final class StarFinaleWindow: MenuBarOverlayWindow {

    let finaleView = StarFinaleView(frame: .zero)

    override init() {
        super.init()
        contentView = finaleView
    }

    var isPlaying: Bool {
        return finaleView.finale != nil
    }

    /// Put up the finale's first frame, which is empty, for stars whose first is centred at
    /// `centre` in screen coordinates. A finale already playing starts again.
    func play(_ finale: StarFinale, firstStarAt centre: NSPoint) {
        let placed = StarFinaleView.frame(for: finale, firstStarAt: centre)
        // The finale view is the content view, so it takes the window's size
        setFrame(placed.frame, display: false)
        finaleView.origin = placed.origin
        finaleView.elapsed = 0
        finaleView.finale = finale
        finaleView.displayIfNeeded()
        orderFrontRegardless()
        os_log("%{public}s[%{public}ld], %{public}s: five-star finale over the menu bar at %{public}s", ((#file as NSString).lastPathComponent), #line, #function, NSStringFromRect(placed.frame))
    }

    /// Draw the finale `elapsed` seconds into the flourish, if it is playing
    func step(to elapsed: TimeInterval) {
        guard isPlaying else { return }
        finaleView.elapsed = elapsed
    }

    /// Take the finale down at once, wherever it has got to
    func stop() {
        finaleView.finale = nil
        orderOut(nil)
    }

}
