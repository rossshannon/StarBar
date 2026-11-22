//
//  SpotifyPlaybackPlace.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-21.
//

import Foundation
import os

/// Where Spotify is playing: on this Mac, or on another device through Spotify Connect.
///
/// The Mac's Spotify app posts the same `PlaybackStateChanged` notification when it is only
/// the remote control for another device (a speaker, a TV, a phone), and nothing in that
/// notification or in Spotify's AppleScript says which device is playing (measured
/// 2026-11-20 with Spotify 1.3.10, `docs/spotify.md`). What does tell them apart is whether
/// Spotify's own process is sending sound to an output on this Mac, which Core Audio reports
/// from macOS 14.2 (`ProcessAudioOutput`). This is the rule that turns the two into a place:
///
/// - Playing with sound going out: here.
/// - Playing a new song while the sound has been going out since before it (`freshSound`), and
///   the song before wasn't due to end (`dueToEnd`): wait `confirmWait` to see whether the
///   sound goes on, and here only if it does. That sound may be the last song's, still
///   draining: measured 2026-11-21, a song started on an Alexa while this Mac played another
///   was announced 0.86 s before this Mac's sound stopped. A song that follows the last one
///   when it ends, or that this Mac's sound started for, needs no wait. A song the user skips
///   to on this Mac does, and reaches the strip `confirmWait` late.
/// - Playing with no sound: wait up to `outputWait` for it, since nothing promises that the
///   notification comes after the sound starts; elsewhere if it doesn't come. The caller holds
///   the notification meanwhile, so a song on another device never reaches the strip or the
///   menu bar. Once elsewhere, a new song there needs no wait.
/// - The sound stopping while Spotify last said Playing: the same wait, then elsewhere, for
///   playback moved to another device in the middle of a song. A Paused that arrives meanwhile
///   was a pause on this Mac, and keeps it here.
/// - The sound starting: here, whatever Spotify last said, so music moved to this Mac shows at
///   once.
/// - Paused or stopped: there is no sound either way, so the place stays as it was.
/// - Core Audio can't say (before macOS 14.2, or a read that failed): here, which is what
///   StarBar assumed before it could tell.
///
/// The sound is read afresh with each notification and when the wait ends (`readOutput`), as
/// well as being reported when it changes (`outputChanged(_:)`), so a listener Core Audio
/// never calls can't leave a stale answer behind. The wait is one timer on `clock`, and
/// everything else answers an event: nothing is polled. Main thread only.
final class SpotifyPlaybackPlace {

    enum Place: String {
        case here
        case elsewhere
    }

    /// What a decision is waiting for
    enum Waiting: Equatable {
        case none
        /// Spotify said Playing with no sound going out, and its notification is held
        case afterPlaying
        /// The sound stopped while Spotify last said Playing
        case afterSilence
        /// Spotify said Playing for a new song while the sound it was already sending went on,
        /// and its notification is held to see whether the sound stops
        case afterNewSong
    }

    /// What a notification said of its song, for telling a new song from the one before and
    /// whether that one was due to end
    private struct Heard {
        let song: String
        let state: SpotifyPlayInfo.State
        /// Seconds into the song when Spotify posted
        let position: TimeInterval?
        /// Seconds
        let duration: TimeInterval?
        let at: Date
    }

    /// How long Spotify may say Playing before its sound starts, before it counts as playing
    /// on another device. A guess, to be measured: Spotify posts its notification 0.6 to 1.1 s
    /// after the command (`docs/spotify.md`), and this Mac's sound may start either side of it.
    static let outputWait: TimeInterval = 2.0

    /// How long a new song's notification is held while the sound from the song before goes
    /// on, to see whether it stops. Measured once, 2026-11-21: the sound stopped 0.86 s after
    /// Spotify announced a song started on another device.
    static let confirmWait: TimeInterval = 1.5

    /// Sound that started at most this long before a Playing notification is that song's own.
    /// Measured 2026-11-21: a song started on this Mac began sending sound 26 ms before Spotify
    /// announced it.
    static let freshSound: TimeInterval = 0.5

    /// A new song that comes when the one before had at most this long left is the next in
    /// the queue, playing where the last one did. Generous, because Spotify's crossfade starts
    /// the next song up to 12 s early, and because Spotify says nothing on a seek, so the time
    /// left is worked out from the last notification and can be out.
    static let dueToEnd: TimeInterval = 15

    private(set) var place: Place = .here
    private(set) var waiting: Waiting = .none
    /// Whether Spotify's process is sending sound to an output on this Mac; nil when Core Audio
    /// can't say
    private(set) var output: Bool?
    private let readOutput: () -> Bool?
    /// When the sound last started, while it is going out
    private var soundSince: Date?
    /// What Spotify last said, so the sound stopping can be told from a pause
    private var lastState: SpotifyPlayInfo.State = .unknown
    /// The last notification that named a song
    private var lastHeard: Heard?
    private var timer: RatingReminderTimer?
    private let clock: RatingReminderClock

    /// A decision made after the event that started it: a held notification can go out now,
    /// or the place changed with no notification from Spotify. Not called for a notification
    /// that `heard(_:)` answered at once.
    var didDecide: (() -> Void)?

    /// - Parameter readOutput: whether Spotify's process is sending sound to an output now,
    ///   nil when that can't be read
    init(clock: RatingReminderClock = RunLoopClock(), readOutput: @escaping () -> Bool?) {
        self.clock = clock
        self.readOutput = readOutput
    }

    /// Spotify posted a notification in `state`.
    ///
    /// - Parameters:
    ///   - song: the notification's Track ID, nil when it named none
    ///   - position: seconds into the song when Spotify posted
    ///   - duration: the song's length in seconds
    /// - Returns: true when the notification can be passed on now, false when it waits for
    ///   the sound, and `didDecide` will say when it can
    func heard(_ state: SpotifyPlayInfo.State, song: String? = nil, position: TimeInterval? = nil, duration: TimeInterval? = nil) -> Bool {
        let now = clock.now()
        let before = lastHeard
        lastState = state
        noteOutput(readOutput())
        if let song = song {
            lastHeard = Heard(song: song, state: state, position: position, duration: duration, at: now)
        }
        guard state == .playing else {
            switch waiting {
            case .afterPlaying:
                // Playing, then something else before any sound came. On this Mac it would
                // have started, so this was another device.
                _ = settle(output == false ? .elsewhere : .here, because: "Spotify said Playing and then \(state) with no sound from it")
            case .afterNewSong:
                // A new song, then a pause before the wait ended. With the sound gone it could
                // be either; another device is the likelier, since its sound stops by itself
                // and a pause on this Mac so soon after choosing a song is rare. A song that is
                // then played here shows as its sound starts.
                _ = settle(output == false ? .elsewhere : .here, because: "Spotify said Playing a new song and then \(state), with its sound \(output == false ? "off" : "going out")")
            case .afterSilence:
                // The sound stopped because Spotify paused here
                _ = settle(.here, because: "the sound stopped for a pause")
            case .none:
                break
            }
            return true
        }
        switch output {
        case true?:
            if waiting == .afterNewSong, song == nil || song == before?.song {
                // Spotify said it again: the sound still decides
                return false
            }
            if let song = song, let before = before, song != before.song,
               let since = soundSince, now.timeIntervalSince(since) > SpotifyPlaybackPlace.freshSound,
               !SpotifyPlaybackPlace.wasDueToEnd(before, at: now) {
                os_log("%{public}s[%{public}ld], %{public}s: Spotify says Playing a new song while the sound it has sent for %.1f s goes on, and the song before wasn't due to end; waiting %.1f s to see whether the sound stops", ((#file as NSString).lastPathComponent), #line, #function, now.timeIntervalSince(since), SpotifyPlaybackPlace.confirmWait)
                wait(for: .afterNewSong)
                return false
            }
            _ = settle(.here, because: "Spotify says Playing and its sound is going out")
            return true
        case nil:
            _ = settle(.here, because: "Spotify says Playing and this Mac can't tell where")
            return true
        case false?:
            if waiting == .afterNewSong {
                // The sound stopped while a new song was held: the wait decides, so that a
                // gap between songs on this Mac isn't taken for another device
                return false
            }
            if place == .elsewhere, waiting == .none {
                os_log("%{public}s[%{public}ld], %{public}s: Spotify says Playing with no sound from it; still on another device", ((#file as NSString).lastPathComponent), #line, #function)
                return true
            }
            os_log("%{public}s[%{public}ld], %{public}s: Spotify says Playing with no sound from it; waiting up to %.1f s for its sound", ((#file as NSString).lastPathComponent), #line, #function, SpotifyPlaybackPlace.outputWait)
            wait(for: .afterPlaying)
            return false
        }
    }

    /// Core Audio says whether Spotify's process is sending sound to an output: nil when it
    /// can't say
    func outputChanged(_ isRunning: Bool?) {
        guard isRunning != output else { return }
        noteOutput(isRunning)
        switch isRunning {
        case true?:
            if settle(.here, because: "its sound started") {
                didDecide?()
            }
        case nil:
            if settle(.here, because: "this Mac can no longer tell where it plays") {
                didDecide?()
            }
        case false?:
            // A pause stops the sound too, and comes with its own notification. Only sound
            // that stops while Spotify says it is still playing needs a look. While a new song
            // is held, its wait decides.
            guard lastState == .playing, place == .here, waiting == .none else { return }
            os_log("%{public}s[%{public}ld], %{public}s: Spotify's sound stopped while it says Playing; waiting up to %.1f s", ((#file as NSString).lastPathComponent), #line, #function, SpotifyPlaybackPlace.outputWait)
            wait(for: .afterSilence)
        }
    }

    /// Spotify launched or quit: nothing is known about where it plays
    func reset() {
        timer?.invalidate()
        timer = nil
        waiting = .none
        place = .here
        lastState = .unknown
        lastHeard = nil
        output = nil
        noteOutput(readOutput())
    }

    /// Whether `before` was due to end by `now`, so that a new song is the next in the queue
    private static func wasDueToEnd(_ before: Heard, at now: Date) -> Bool {
        guard let duration = before.duration, duration > 0 else { return false }
        let elapsed = before.state == .playing ? now.timeIntervalSince(before.at) : 0
        let left = duration - (before.position ?? 0) - elapsed
        return left <= dueToEnd
    }

    /// Take a new reading of the sound, and when it started
    private func noteOutput(_ isRunning: Bool?) {
        if isRunning == true {
            if output != true {
                soundSince = clock.now()
            }
        } else {
            soundSince = nil
        }
        output = isRunning
    }

    /// Stop waiting and take `newPlace`.
    ///
    /// - Returns: true when the caller has something to pass on: a notification that was
    ///   held, or a change of place
    private func settle(_ newPlace: Place, because reason: String) -> Bool {
        let released = waiting == .afterPlaying || waiting == .afterNewSong
        timer?.invalidate()
        timer = nil
        waiting = .none
        let changed = newPlace != place
        place = newPlace
        if changed || released {
            os_log("%{public}s[%{public}ld], %{public}s: Spotify is playing %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, newPlace == .here ? "on this Mac" : "on another device", reason)
        }
        return changed || released
    }

    private func wait(for reason: Waiting) {
        timer?.invalidate()
        waiting = reason
        let seconds = reason == .afterNewSong ? SpotifyPlaybackPlace.confirmWait : SpotifyPlaybackPlace.outputWait
        timer = clock.schedule(after: seconds, repeats: false) { [weak self] in
            guard let self = self else { return }
            self.noteOutput(self.readOutput())
            let newPlace: Place = self.output == false ? .elsewhere : .here
            let why: String
            switch (self.waiting, newPlace) {
            case (.afterNewSong, .here): why = "its sound went on for \(seconds) s after the new song"
            case (.afterNewSong, .elsewhere): why = "its sound stopped within \(seconds) s of the new song"
            case (_, .here): why = "its sound is going out after \(seconds) s"
            case (_, .elsewhere): why = "no sound from it within \(seconds) s"
            }
            if self.settle(newPlace, because: why) {
                self.didDecide?()
            }
        }
    }

}
