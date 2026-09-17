//
//  RatingReminderController.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Foundation
import Cocoa
import os

/// Reminds the user to rate a track before it ends: plays a bell and sweeps a hollow star
/// across the dots in the menu bar.
///
/// `MenuBarRatingControl` calls `playerDidUpdate(_:)` after each player update. While the
/// reminder is still to come, the controller reads the player position every 2 seconds,
/// because Music sends no notification when the user seeks. When the position says the
/// reminder is due, it reads the whole player again before it rings.
final class RatingReminderController {

    /// What the reminder needs to know about the player
    struct PlayerSnapshot {
        /// Music's persistent ID for the track
        let trackID: String
        let isPlaying: Bool
        /// Player position, in seconds
        let position: TimeInterval
        /// Track length in seconds; 0 for streams
        let duration: TimeInterval
        /// The track has a rating the user set
        let isRated: Bool
    }

    /// Shortest wait before reading the player again. Stops a stalled stream, whose position
    /// doesn't move, from reading the player many times a second.
    static let minimumWait: TimeInterval = 1
    /// Longest wait between position checks. Music sends no notification when the user seeks,
    /// so while a reminder is still to come the position is read this often.
    static let positionCheckInterval: TimeInterval = 2
    /// Reads in a row that may fail (Music too slow, or quit) before the reminder
    /// for this track gives up
    static let maximumFailedReads = 3

    private let ratingControl: RatingControl
    /// Reads the player now, or returns nil when Music isn't running or has no track
    private let readPlayer: () -> PlayerSnapshot?
    /// Reads only the player position (one Apple Event), or nil when Music isn't running
    private let readPosition: () -> TimeInterval?
    /// Marks the menu bar button for redrawing
    private let redraw: () -> Void
    /// True while the user drags across the stars; the reminder waits until they finish
    private let isBusy: () -> Bool
    private let bell: RatingReminderBell
    private let clock: RatingReminderClock

    /// Track of the last player update
    private var currentTrackID: String?
    /// Track the reminder fired for, or the user rated. It gets no (more) reminders.
    private var remindedTrackID: String?
    /// Last full player read, while its reminder is still to come
    private var pendingSnapshot: PlayerSnapshot?
    private var failedReads = 0
    private var reminderTimer: RatingReminderTimer?
    private var sweepTimer: RatingReminderTimer?
    private var sweepStart: Date?

    init(
        ratingControl: RatingControl,
        readPlayer: @escaping () -> PlayerSnapshot?,
        readPosition: @escaping () -> TimeInterval?,
        redraw: @escaping () -> Void,
        isBusy: @escaping () -> Bool = { false },
        bell: RatingReminderBell = SoundFileBell(name: "Bell Transition"),
        clock: RatingReminderClock = RunLoopClock()
    ) {
        self.ratingControl = ratingControl
        self.readPlayer = readPlayer
        self.readPosition = readPosition
        self.redraw = redraw
        self.isBusy = isBusy
        self.bell = bell
        self.clock = clock
    }

    deinit {
        reminderTimer?.invalidate()
        sweepTimer?.invalidate()
    }

}

extension RatingReminderController {

    /// Decide again after the player changed: a new track, play or pause, a new rating
    func playerDidUpdate(_ snapshot: PlayerSnapshot?) {
        evaluate(snapshot, isFullRead: true)
    }

    /// - Parameter isFullRead: false when only the position is new, and the rest comes from
    ///   the last full read
    private func evaluate(_ snapshot: PlayerSnapshot?, isFullRead: Bool) {
        reminderTimer?.invalidate()
        reminderTimer = nil
        pendingSnapshot = nil
        if isFullRead, snapshot != nil {
            failedReads = 0
        }

        // A bell and sweep already under way always finish, even if playback changes
        guard let snapshot = snapshot else { return }
        if snapshot.trackID != currentTrackID {
            // A new track, or the same one played again later, gets its own reminder
            currentTrackID = snapshot.trackID
            remindedTrackID = nil
        }
        guard snapshot.isPlaying else { return }

        let decision = RatingReminder.decision(
            position: snapshot.position,
            duration: snapshot.duration,
            isRated: snapshot.isRated,
            alreadyReminded: snapshot.trackID == remindedTrackID
        )
        switch decision {
        case .never:
            break
        case .remindNow where isBusy():
            // Don't sweep over the stars the user is dragging; look again shortly
            pendingSnapshot = snapshot
            scheduleCheck(after: RatingReminderController.minimumWait)
        case .remindNow where !isFullRead:
            // Due by the position alone: read everything again, in case the track was rated in Music
            if let fullSnapshot = readPlayer() {
                evaluate(fullSnapshot, isFullRead: true)
            } else {
                pendingSnapshot = snapshot
                retryAfterFailedRead()
            }
        case .remindNow:
            remindedTrackID = snapshot.trackID
            remind()
        case .wait(let seconds):
            if isFullRead {
                os_log("%{public}s[%{public}ld], %{public}s: rating reminder due in %{public}.0f s", ((#file as NSString).lastPathComponent), #line, #function, seconds)
            }
            failedReads = 0
            pendingSnapshot = snapshot
            // A little late is better than early: an early check only schedules another
            let wait = max(RatingReminderController.minimumWait, seconds + 0.25)
            scheduleCheck(after: min(RatingReminderController.positionCheckInterval, wait))
        }
    }

    /// The user set a rating. Music saves it 2 seconds later, so a check before then would
    /// still see an unrated track: mark the track as done now.
    func userDidRate() {
        remindedTrackID = currentTrackID
        cancel()
    }

    /// The Preferences checkbox changed
    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            playerDidUpdate(readPlayer())
        } else {
            cancel()
        }
    }

    /// Stop the sweep straight away, for example when the user clicks the stars
    func stopSweep() {
        sweepTimer?.invalidate()
        sweepTimer = nil
        sweepStart = nil
        guard ratingControl.sweepPosition != nil else { return }
        ratingControl.updateSweep(position: nil)
        redraw()
    }

    private func scheduleCheck(after seconds: TimeInterval) {
        reminderTimer = clock.schedule(after: seconds, repeats: false) { [weak self] in
            self?.checkPosition()
        }
    }

    /// Read only the position, and decide again with the rest of the last full read
    private func checkPosition() {
        guard let pending = pendingSnapshot else { return }
        guard let position = readPosition() else {
            retryAfterFailedRead()
            return
        }
        let snapshot = PlayerSnapshot(
            trackID: pending.trackID,
            isPlaying: pending.isPlaying,
            position: position,
            duration: pending.duration,
            isRated: pending.isRated
        )
        evaluate(snapshot, isFullRead: false)
    }

    /// A read failed: Music quit, or was too slow to answer. Keep `pendingSnapshot` and try
    /// again a few times before giving up on this track. If Music really quit, its
    /// notification cancels the reminder anyway.
    private func retryAfterFailedRead() {
        failedReads += 1
        if failedReads < RatingReminderController.maximumFailedReads {
            scheduleCheck(after: RatingReminderController.positionCheckInterval)
        } else {
            os_log("%{public}s[%{public}ld], %{public}s: giving up on the rating reminder after %{public}ld failed reads", ((#file as NSString).lastPathComponent), #line, #function, failedReads)
            pendingSnapshot = nil
            failedReads = 0
        }
    }

    private func cancel() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        pendingSnapshot = nil
        stopEffects()
    }

    /// Stop the bell and the sweep. Does nothing if they aren't running.
    private func stopEffects() {
        bell.stop()
        stopSweep()
    }

    private func remind() {
        os_log("%{public}s[%{public}ld], %{public}s: reminding the user to rate the current track", ((#file as NSString).lastPathComponent), #line, #function)
        bell.play()

        stopSweep()
        sweepStart = clock.now()
        sweepTimer = clock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            self?.tickSweep()
        }
        tickSweep()
    }

    private func tickSweep() {
        guard let sweepStart = sweepStart,
              let position = StarSweep.position(atElapsed: clock.now().timeIntervalSince(sweepStart)) else {
            stopSweep()
            return
        }
        guard position != ratingControl.sweepPosition else { return }
        ratingControl.updateSweep(position: position)
        redraw()
    }

}

// MARK: - Bell and clock

/// The reminder's sound
protocol RatingReminderBell {
    func play()
    func stop()
}

/// A sound file in the app bundle
final class SoundFileBell: RatingReminderBell {

    private let sound: NSSound?

    init(name: String) {
        sound = NSSound(named: name)
        if sound == nil {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: sound %{public}s is missing from the app bundle", ((#file as NSString).lastPathComponent), #line, #function, name)
        }
    }

    func play() {
        sound?.stop()
        sound?.play()
    }

    func stop() {
        guard sound?.isPlaying == true else { return }
        sound?.stop()
    }

}

protocol RatingReminderTimer {
    func invalidate()
}

extension Timer: RatingReminderTimer {}

/// Time and timers, so tests can run the reminder without waiting
protocol RatingReminderClock {
    func now() -> Date
    func schedule(after seconds: TimeInterval, repeats: Bool, action: @escaping () -> Void) -> RatingReminderTimer
}

/// Real time, with timers on the main run loop
struct RunLoopClock: RatingReminderClock {

    func now() -> Date {
        return Date()
    }

    func schedule(after seconds: TimeInterval, repeats: Bool, action: @escaping () -> Void) -> RatingReminderTimer {
        let timer = Timer(timeInterval: seconds, repeats: repeats) { _ in action() }
        // Let macOS group wake-ups; the sweep's 60 Hz timer needs to stay on time
        timer.tolerance = seconds >= 1 ? 0.2 : 0
        // .common keeps timers firing while AppKit tracks the mouse
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

}
