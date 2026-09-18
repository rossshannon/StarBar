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
/// perform; this class only decides when. Three rules on top of the throttle:
///
/// - A held rating is for the song it was chosen for. If a rating for a *different* song
///   arrives while one is held, the held one is sent straight away rather than replaced:
///   the user chose it, and its song has been moved on from, so waiting gains nothing.
/// - `flush()` sends a held rating now, for `applicationWillTerminate`, so quitting inside
///   the window doesn't lose the last thing the user did.
/// - `discard()` drops a held rating, for when Music quits: there is nowhere left to write
///   it, and an Apple Event to a track whose app has gone could start Music again.
///
/// Main thread only, like everything else that touches the Scripting Bridge here.
final class RatingWriter {

    /// One rating to write, with what the caller resolved about it
    struct Request {
        /// 0 to 100
        let rating: Int
        /// The track to rate. Never "whatever is playing": a held write lands up to the
        /// window's length later, by which time that could be the next song.
        let track: iTunesTrack
        /// For the log only
        let name: String
        /// Which song the rating was chosen for, or nil when that can't be told. Two nils
        /// count as the same song.
        ///
        /// A closure because answering can cost an Apple Event, and the answer is only needed
        /// when a rating is already held or this one is about to be. It is called at most
        /// once, synchronously, inside `rate(_:)`, so it describes the same moment as `track`.
        /// It must come from the same snapshot as `track`: an identity that lags the track
        /// (Music's notification, say, which the rating shortcuts don't wait for) would make
        /// two songs look like one and the held rating would be replaced after all.
        let songIdentity: () -> String?
    }

    private var throttle: RatingWriteThrottle
    private let clock: RatingReminderClock
    private let write: (Request) -> Void
    private var held: (request: Request, songIdentity: String?)?
    private var holdTimer: RatingReminderTimer?

    /// The rating waiting for the window to close, if any
    var heldRating: Int? {
        return held?.request.rating
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
        dispatchPrecondition(condition: .onQueue(.main))
        var resolved: String??
        func songIdentity() -> String? {
            if let resolved = resolved { return resolved }
            let identity = request.songIdentity()
            resolved = .some(identity)
            return identity
        }

        // A held rating for another song is never discarded: the user chose it, so it goes
        // now, whichever way this request is handled. The window stays where it is, because
        // a track change is not the burst the throttle exists for. This runs before the
        // throttle decides: the hold timer has up to 200 ms of tolerance, so "the window has
        // closed" can arrive while a rating is still held.
        if let held = held, held.songIdentity != songIdentity() {
            os_log("%{public}s[%{public}ld], %{public}s: the song changed, sending the held rating for %{public}s %{public}ld now", ((#file as NSString).lastPathComponent), #line, #function, held.request.name, held.request.rating)
            self.held = nil
            write(held.request)
        }

        switch throttle.decide(at: clock.now()) {
        case .now:
            // Nothing held for this song can be newer than this
            held = nil
            holdTimer?.invalidate()
            holdTimer = nil
            os_log("%{public}s[%{public}ld], %{public}s: set rating for %{public}s %{public}ld…", ((#file as NSString).lastPathComponent), #line, #function, request.name, request.rating)
            write(request)

        case .hold(let until):
            // Keep only the newest rating for this song. The timer is already counting to
            // the same moment, so holding a shortcut down must not push the write further away.
            held = (request, songIdentity())
            guard holdTimer == nil else { return }

            os_log("%{public}s[%{public}ld], %{public}s: holding rating for %{public}s %{public}ld until the window closes…", ((#file as NSString).lastPathComponent), #line, #function, request.name, request.rating)
            let wait = max(0, until.timeIntervalSince(clock.now()))
            // `RunLoopClock` schedules on the main run loop in `.common` mode, so the write
            // isn't held back while AppKit tracks an open menu
            holdTimer = clock.schedule(after: wait, repeats: false) { [weak self] in
                self?.sendHeld()
            }
        }
    }

    /// Send a held rating now, without waiting for the window. For quitting.
    func flush() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard held != nil else { return }
        holdTimer?.invalidate()
        sendHeld()
    }

    /// Drop a held rating without sending it. For when Music has quit.
    func discard() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let held = held else { return }
        os_log("%{public}s[%{public}ld], %{public}s: dropping the held rating for %{public}s %{public}ld, there is nowhere to send it", ((#file as NSString).lastPathComponent), #line, #function, held.request.name, held.request.rating)
        self.held = nil
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func sendHeld() {
        holdTimer = nil
        guard let request = held?.request else { return }
        held = nil

        throttle.didWrite(at: clock.now())
        os_log("%{public}s[%{public}ld], %{public}s: sending the held rating for %{public}s %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, request.name, request.rating)
        write(request)
    }

}
