//
//  FrameCadence.swift
//  StarBar
//

import Foundation

/// How evenly an animation stepped by hand was drawn, for the log.
///
/// The menu bar's transitions are drawn frame by frame on the main thread, which also sends
/// Music its Apple Events, so a read that lands in a transition holds its frames. Nothing
/// recorded that: a hitch could only be reproduced and filmed, or pieced together from the
/// gaps between other log lines. Each transition now counts its frames and the gaps between
/// them and logs one line when it ends, so a hitch the user saw can be read back from the
/// log, with how long the main thread was held and how far through the transition it was.
/// The system log keeps StarBar's lines for about half a day (13 hours on 2026-11-12), so
/// read it the same day.
struct FrameCadence {

    /// A gap longer than this missed at least one refresh of a 60 Hz display
    static let lateAfter: TimeInterval = 1.5 / 60.0

    /// Frames drawn
    private(set) var frames = 0
    /// Frames that came more than `lateAfter` after the one before
    private(set) var lateFrames = 0
    /// The longest wait between two frames
    private(set) var longestGap: TimeInterval = 0
    /// How long the animation had run, as drawn, at the frame before the longest wait: where
    /// in the motion it stood still
    private(set) var longestGapAt: TimeInterval = 0
    /// Clock time from the first frame to the last
    private(set) var span: TimeInterval = 0

    private var first: Date?
    private var last: (time: Date, animationTime: TimeInterval)?

    /// Count a frame drawn at `time`, when the animation had run for `animationTime` as drawn
    mutating func frame(at time: Date, animationTime: TimeInterval) {
        frames += 1
        if let last = last {
            let gap = time.timeIntervalSince(last.time)
            if gap > FrameCadence.lateAfter {
                lateFrames += 1
            }
            if gap > longestGap {
                longestGap = gap
                longestGapAt = last.animationTime
            }
        }
        let start = first ?? time
        first = start
        span = time.timeIntervalSince(start)
        last = (time, animationTime)
    }

    /// One line for the log
    var summary: String {
        guard frames > 1 else {
            return "\(frames) frame\(frames == 1 ? "" : "s")"
        }
        return String(format: "%d frames in %.3f s, %d late, longest gap %.0f ms at %.2f s in",
                      frames, span, lateFrames, longestGap * 1000, longestGapAt)
    }

}
