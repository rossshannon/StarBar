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
    }

    /// How long Spotify may say Playing before its sound starts, before it counts as playing
    /// on another device. A guess, to be measured: Spotify posts its notification 0.6 to 1.1 s
    /// after the command (`docs/spotify.md`), and this Mac's sound may start either side of it.
    static let outputWait: TimeInterval = 2.0

    private(set) var place: Place = .here
    private(set) var waiting: Waiting = .none
    /// Whether Spotify's process is sending sound to an output on this Mac; nil when Core Audio
    /// can't say
    private(set) var output: Bool?
    private let readOutput: () -> Bool?
    /// What Spotify last said, so the sound stopping can be told from a pause
    private var lastState: SpotifyPlayInfo.State = .unknown
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
    /// - Returns: true when the notification can be passed on now, false when it waits for
    ///   the sound, and `didDecide` will say when it can
    func heard(_ state: SpotifyPlayInfo.State) -> Bool {
        lastState = state
        output = readOutput()
        guard state == .playing else {
            switch waiting {
            case .afterPlaying:
                // Playing, then something else before any sound came. On this Mac it would
                // have started, so this was another device.
                _ = settle(output == false ? .elsewhere : .here, because: "Spotify said Playing and then \(state) with no sound from it")
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
            _ = settle(.here, because: "Spotify says Playing and its sound is going out")
            return true
        case nil:
            _ = settle(.here, because: "Spotify says Playing and this Mac can't tell where")
            return true
        case false?:
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
        output = isRunning
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
            // that stops while Spotify says it is still playing needs a look.
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
        output = readOutput()
    }

    /// Stop waiting and take `newPlace`.
    ///
    /// - Returns: true when the caller has something to pass on: a notification that was
    ///   held, or a change of place
    private func settle(_ newPlace: Place, because reason: String) -> Bool {
        let released = waiting == .afterPlaying
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
        timer = clock.schedule(after: SpotifyPlaybackPlace.outputWait, repeats: false) { [weak self] in
            guard let self = self else { return }
            self.output = self.readOutput()
            let newPlace: Place = self.output == false ? .elsewhere : .here
            if self.settle(newPlace, because: "no sound from it within \(SpotifyPlaybackPlace.outputWait) s") {
                self.didDecide?()
            }
        }
    }

}
