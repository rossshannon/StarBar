//
//  RatingWriteThrottle.swift
//  StarBar
//
//  When a rating should be sent to Music. Pure timing rule, no Apple Events: see
//  `RatingWriteThrottleTests`.
//

import Foundation

/// Decides when a rating the user chose is written to Music.
///
/// The first rating goes out **immediately**, so an ordinary click or keystroke lands at once
/// instead of waiting for a timer. Ratings that arrive while that write is still fresh are
/// held and sent once, when the window closes, so holding a rating shortcut down doesn't send
/// Music a burst of Apple Events.
///
/// Dragging across the stars doesn't come through here repeatedly. `RatingClickController`
/// previews a drag with `RatingControl.update(rating:)`, which is display only, and commits
/// once on release. The window is here for the keyboard shortcuts, which really can repeat.
struct RatingWriteThrottle {

    /// How long after a write the next one is held rather than sent
    let interval: TimeInterval

    /// When the last rating was sent to Music, or nil if none has been
    private(set) var lastWriteDate: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// What to do with a rating the user just chose.
    enum Decision: Equatable {
        /// Send it to Music now
        case now
        /// Hold it until this date, replacing any rating already held
        case hold(until: Date)
    }

    /// Ask what to do with a rating chosen at `date`.
    ///
    /// Returns `.now` when nothing has been written inside the window, and records the write.
    /// Otherwise returns `.hold(until:)` with the moment the window closes; the caller keeps
    /// only the newest held rating and calls `didWrite(at:)` when it sends it.
    mutating func decide(at date: Date) -> Decision {
        guard let lastWriteDate = lastWriteDate,
              date.timeIntervalSince(lastWriteDate) < interval else {
            self.lastWriteDate = date
            return .now
        }

        return .hold(until: lastWriteDate.addingTimeInterval(interval))
    }

    /// Record that a held rating has been sent, so the next one starts a fresh window.
    mutating func didWrite(at date: Date) {
        lastWriteDate = date
    }

}
