//
//  RatingReminder.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Foundation

/// When to remind the user to rate a track that has no rating.
///
/// Uses Music's play position, not the time since the track started, so pausing never
/// brings the reminder forward.
enum RatingReminder {

    enum Decision: Equatable {
        /// The reminder is due in this many seconds of playback
        case wait(seconds: TimeInterval)
        /// The reminder is due now
        case remindNow
        /// This track gets no reminder
        case never
    }

    /// Seconds into the track when the reminder is due: 75% of the way through, or 30 seconds
    /// before the end, whichever is later. Short tracks wait until 75%; long tracks don't
    /// remind minutes before they finish.
    static func reminderPosition(duration: TimeInterval) -> TimeInterval {
        return max(0.75 * duration, duration - 30)
    }

    /// What to do for a track playing at `position` seconds of `duration`.
    ///
    /// - Parameters:
    ///   - position: Music's player position, in seconds
    ///   - duration: track length in seconds; 0 for streams
    ///   - isRated: the track has a rating the user set
    ///   - alreadyReminded: the reminder already fired for this track
    static func decision(position: TimeInterval, duration: TimeInterval, isRated: Bool, alreadyReminded: Bool) -> Decision {
        // Rated, already reminded, a stream, or finished: nothing to do
        guard !isRated, !alreadyReminded, duration > 0, position < duration else { return .never }

        let reminderPosition = self.reminderPosition(duration: duration)
        // Also covers a seek forwards past the reminder point
        guard position < reminderPosition else { return .remindNow }
        return .wait(seconds: reminderPosition - position)
    }

}
