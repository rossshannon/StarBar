import Foundation

/// Start elapsed time when the display can draw, after synchronous Music reads finish.
struct MenuBarAnimationTiming {
    let duration: TimeInterval
    private var firstFrame: Date?

    init(duration: TimeInterval) {
        precondition(duration > 0)
        self.duration = duration
    }

    mutating func progress(at time: Date) -> Double {
        let start = firstFrame ?? time
        firstFrame = start
        return min(1, max(0, time.timeIntervalSince(start) / duration))
    }
}
