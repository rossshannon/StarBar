//
//  RatingWriter.swift
//  StarBar
//
//  When ratings the user chose reach Music. Owns the held write and its timer, so the
//  whole pipeline runs against a fake clock in `RatingWriterTests`.
//

import Foundation
import os

/// Sends ratings to Music: the first at once, and any that arrive while that write is still
/// fresh held and sent once when `RatingWriteThrottle`'s window closes.
///
/// `iTunesRadioStation` resolves which track a rating is for and hands over the write to
/// perform; this class only decides when. Two rules on top of the throttle:
///
/// - A held rating is for the song it was chosen for. If a rating for a *different* song
///   arrives while one is held, the held one is sent straight away rather than replaced:
///   the user chose it, and its song has been moved on from, so waiting gains nothing.
/// - `flush()` sends a held rating now, for `applicationWillTerminate`, so quitting inside
///   the window doesn't lose the last thing the user did.
final class RatingWriter {

    /// One rating to write, with what the caller resolved about it
    struct Request {
        /// 0 to 100
        let rating: Int
        /// The track to rate, or nil for whatever is playing when the write happens
        let track: iTunesTrack?
        /// Which song the rating was chosen for, from Music's notification, or nil when
        /// that isn't known (the launch gap). Two nils count as the same song.
        let identity: Int?
        /// For the log only
        let name: String
    }

    private var throttle: RatingWriteThrottle
    private let clock: RatingReminderClock
    private let write: (Request) -> Void
    private var held: Request?
    private var holdTimer: RatingReminderTimer?

    /// The rating waiting for the window to close, if any
    var heldRating: Int? {
        return held?.rating
    }

    init(interval: TimeInterval, clock: RatingReminderClock = RunLoopClock(), write: @escaping (Request) -> Void) {
        self.throttle = RatingWriteThrottle(interval: interval)
        self.clock = clock
        self.write = write
    }

    deinit {
        holdTimer?.invalidate()
    }

    /// The user chose a rating
    func rate(_ request: Request) {
        switch throttle.decide(at: clock.now()) {
        case .now:
            // Nothing held can be newer than this
            held = nil
            holdTimer?.invalidate()
            holdTimer = nil
            os_log("%{public}s[%{public}ld], %{public}s: set rating for %{public}s %{public}ld…", ((#file as NSString).lastPathComponent), #line, #function, request.name, request.rating)
            write(request)

        case .hold(let until):
            if let held = held, held.identity != request.identity {
                // A rating for another song: the user chose it, so it goes now, and the
                // window stays where it is because this is a track change, not a burst
                os_log("%{public}s[%{public}ld], %{public}s: the song changed, sending the held rating for %{public}s %{public}ld now", ((#file as NSString).lastPathComponent), #line, #function, held.name, held.rating)
                write(held)
            }
            // Keep only the newest rating for this song. The timer is already counting to
            // the same moment, so holding a shortcut down must not push the write further away.
            held = request
            guard holdTimer == nil else { return }

            os_log("%{public}s[%{public}ld], %{public}s: holding rating for %{public}s %{public}ld until the window closes…", ((#file as NSString).lastPathComponent), #line, #function, request.name, request.rating)
            let wait = max(0, until.timeIntervalSince(clock.now()))
            holdTimer = clock.schedule(after: wait, repeats: false) { [weak self] in
                self?.sendHeld()
            }
        }
    }

    /// Send a held rating now, without waiting for the window. For quitting.
    func flush() {
        guard held != nil else { return }
        holdTimer?.invalidate()
        sendHeld()
    }

    private func sendHeld() {
        holdTimer = nil
        guard let request = held else { return }
        held = nil

        throttle.didWrite(at: clock.now())
        os_log("%{public}s[%{public}ld], %{public}s: sending the held rating for %{public}s %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, request.name, request.rating)
        write(request)
    }

}
