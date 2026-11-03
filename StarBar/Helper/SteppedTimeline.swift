//
//  SteppedTimeline.swift
//  StarBar
//

import Foundation

/// The time an animation stepped by hand has run, which a stalled main thread pauses rather
/// than skips.
///
/// The strip's slide, the sleeve's rise and the cover's cross-fade are stepped on each display
/// refresh, and each step used to take the clock's time since the start. A step that came late
/// therefore jumped as far as the wall clock had moved: on 2026-11-03 Music sent a second
/// notification for the same song 15 ms after a strip was announced, the menu bar's re-read
/// held the main thread for about 440 ms, and the 0.3 s slide had finished unseen by the next
/// frame, so the strip appeared already in place. The first strip after a launch also held for
/// about 50 ms and then jumped.
///
/// Here each step counts the time since the last one, but never more than `maxStep`, so after a
/// stall the animation carries on from where it was drawn. A step on time counts in full, so on
/// a main thread that keeps up the animation runs exactly as long as it did.
struct SteppedTimeline {

    /// The most one step can count: two frames at 60 Hz, so a frame or two late still counts in
    /// full and only a longer stall is cut short
    static let maxStep: TimeInterval = 2.0 / 60.0

    /// How long the animation has run, as drawn
    private(set) var elapsed: TimeInterval = 0
    private var lastStep: Date

    /// - Parameter start: when the animation started, which the first step counts from
    init(start: Date) {
        lastStep = start
    }

    /// Count a step at `time`, and answer how long the animation has now run
    @discardableResult
    mutating func step(at time: Date) -> TimeInterval {
        elapsed += min(max(0, time.timeIntervalSince(lastStep)), SteppedTimeline.maxStep)
        lastStep = time
        return elapsed
    }

}
