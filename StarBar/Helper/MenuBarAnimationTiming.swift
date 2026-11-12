import Foundation

/// How long a menu bar transition has run, as drawn.
///
/// The time starts at the first display callback, not when the transition was asked for:
/// synchronous Music reads have delayed that callback by 198 to 261 ms, which used up a whole
/// 0.2 s rating transition before any frame was drawn.
///
/// From there a held main thread pauses the transition rather than skipping it, as it does the
/// strip's slide (`SteppedTimeline`). The transitions used to follow the wall clock after
/// their first frame, so whatever held the main thread while the stars rolled in moved them
/// on by as much in one frame. On 2026-11-12 the log showed one: Music's repeat of a song's
/// notification was passed on about 0.46 s into a rollout, and the menu bar's reads for it
/// alone took 124 ms, seven frames at 60 Hz. That repeat now waits for the rollout to end
/// (`RepeatedUpdateHold`); this is for whatever else holds the thread.
struct MenuBarAnimationTiming {
    let duration: TimeInterval
    private var timeline: SteppedTimeline?

    init(duration: TimeInterval) {
        precondition(duration > 0)
        self.duration = duration
    }

    /// How long the transition has run, as drawn: nothing at the first call, which starts it
    private(set) var elapsed: TimeInterval = 0

    mutating func progress(at time: Date) -> Double {
        var timeline = self.timeline ?? SteppedTimeline(start: time)
        elapsed = timeline.step(at: time)
        self.timeline = timeline
        return min(1, max(0, elapsed / duration))
    }
}
