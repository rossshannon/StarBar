//
//  MusicStarter.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-04.
//

import Cocoa
import ScriptingBridge
import os

extension Notification.Name {
    /// `MusicStarter.shared.status` changed. Main thread.
    static let musicStarterDidChange = Notification.Name("StarBarMusicStarterDidChange")
}

/// Starts Music playing when the player popover's play button is pressed with no song
/// loaded: the last library song StarBar saw it play (`LastMusicSong`), opening Music first in
/// the background when it isn't running. With no such song, the button brings Music forward
/// so the user can choose one.
///
/// A plain `play` would not do. Measured 2026-11-04: Music has no current song after a stop
/// and after almost every launch, even after quitting while paused on a song, and with none it
/// answers `play` and `playpause` without an error and plays nothing. That is what the button
/// used to send, through the station, which also sent nothing at all to a Music that wasn't
/// running, so as never to open it by accident; and the button flipped to Pause anyway. Here
/// the user has asked for Music, so opening it is the point.
///
/// Whether it worked is told by Music announcing a song, the notification that puts the song
/// in the popover, and then by the player state, read only while a start is under way:
/// Music answers `play` before the song has started (a local song was loaded and stopped
/// about a second later, and playing half a second after that). Nothing is polled. One
/// timer runs at a time, for when no song comes: `retryWait` after Music answers the first
/// `play`, and `songWait` after it answers the second.
///
/// **A play sent while Music opens can be lost**: in one cold launch of about seven after
/// quitting while paused (2026-11-04), Music answered the `play` and then put back the song
/// it had been paused on, paused where it had been, so nothing played. So when nothing is
/// playing `retryWait` after Music answered, the song is asked for once more (`retried`).
/// Not on seeing Music paused: a song it does play is announced paused at 0.0 first, a
/// moment before it plays. A `play` to a Music already running started the song every time
/// it was tried, but the lost play wasn't caught again to try the second one on.
final class MusicStarter {

    enum Status: Equatable {
        /// Nothing under way
        case idle
        /// Music wasn't running and is being opened
        case opening
        /// Music has been asked to play a song and hasn't been seen playing it yet
        case starting
        /// Music refused the song, or answered and no song came: the next press brings Music
        /// forward to choose something instead
        case couldNotPlay
    }

    /// How long after Music answers `play` a song may take to start before it is asked for
    /// once more. Measured 2026-11-04, a library song was playing 1.3 to 1.4 s after Music
    /// answered, running or just opened.
    static let retryWait: TimeInterval = 3

    /// How long after Music answers the second `play` the song may take to start before the
    /// popover says Music couldn't play it. A streamed song takes a moment to buffer.
    static let songWait: TimeInterval = 6

    static let shared = MusicStarter()

    private(set) var status: Status = .idle {
        didSet {
            guard status != oldValue else { return }
            os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: status))
            NotificationCenter.default.post(name: .musicStarterDidChange, object: self)
        }
    }

    /// Whether Music is running. No Apple Event.
    private let isRunning: () -> Bool
    /// Whether Music's last update had a song in it
    private let hasTrack: () -> Bool
    /// Whether Music says it is playing. Asked only while a start is under way.
    private let isPlaying: () -> Bool
    /// The song a press starts, and forgetting it once Music won't play it
    private let store: LastMusicSongStore
    /// Open Music without bringing it forward, then call back on the main thread with its
    /// process ID, or nil when it couldn't be opened
    private let launch: (@escaping (pid_t?) -> Void) -> Void
    /// Ask the Music with this process ID, or the one running when nil, to play the song,
    /// then call back on the main thread with whether it took the command
    private let play: (pid_t?, LastMusicSong, @escaping (Bool) -> Void) -> Void
    /// Open Music and bring it forward, so the user can choose something to play
    private let activate: () -> Void
    private let clock: RatingReminderClock
    private var songTimer: RatingReminderTimer?
    /// The song asked for by the press under way
    private var song: LastMusicSong?
    /// Whether this press has asked Music a second time, which it does at most once
    private var retried = false

    init(isRunning: @escaping () -> Bool = MusicStarter.musicIsRunning,
         hasTrack: @escaping () -> Bool = { iTunesPlayer.shared.currentTrack != nil },
         isPlaying: @escaping () -> Bool = { MusicStarter.playerState() == .playing },
         store: LastMusicSongStore = .shared,
         launch: @escaping (@escaping (pid_t?) -> Void) -> Void = MusicStarter.launchMusic,
         play: @escaping (pid_t?, LastMusicSong, @escaping (Bool) -> Void) -> Void = MusicStarter.askMusicToPlay,
         activate: @escaping () -> Void = MusicStarter.activateMusic,
         clock: RatingReminderClock = RunLoopClock(),
         center: NotificationCenter = .default) {
        self.isRunning = isRunning
        self.hasTrack = hasTrack
        self.isPlaying = isPlaying
        self.store = store
        self.launch = launch
        self.play = play
        self.activate = activate
        self.clock = clock
        // Asks Music nothing while there is nothing under way (`playerDidUpdate`)
        center.addObserver(self, selector: #selector(MusicStarter.iTunesPlayerDidUpdated(_:)), name: .iTunesPlayerDidUpdated, object: nil)
    }

    /// The song a press would start, for the popover to name
    var nextSong: LastMusicSong? {
        return store.song
    }

    /// The play button was pressed with no song loaded
    func start() {
        switch status {
        case .opening, .starting:
            // Already on its way: a second press would only send a second `play`
            return
        case .couldNotPlay where isRunning():
            // Asking again would come to the same thing. Music's own window is where a song
            // can be chosen.
            bringMusicForward()
            return
        case .idle, .couldNotPlay:
            break
        }
        guard let song = store.song else {
            bringMusicForward()
            return
        }
        guard isRunning() else {
            status = .opening
            launch { [weak self] pid in
                guard let self = self, self.status == .opening else { return }
                guard let pid = pid else {
                    os_log("%{public}s[%{public}ld], %{public}s: Music couldn't be opened", ((#file as NSString).lastPathComponent), #line, #function)
                    self.status = .idle
                    return
                }
                self.askToPlay(song, in: pid)
            }
            return
        }
        askToPlay(song, in: nil)
    }

    /// Back to nothing under way
    private func finish(_ next: Status = .idle) {
        songTimer?.invalidate()
        songTimer = nil
        song = nil
        status = next
    }

    private func bringMusicForward() {
        os_log("%{public}s[%{public}ld], %{public}s: nothing for StarBar to start; bringing Music forward to choose something", ((#file as NSString).lastPathComponent), #line, #function)
        status = .idle
        activate()
    }

    private func askToPlay(_ song: LastMusicSong, in pid: pid_t?) {
        self.song = song
        retried = false
        status = .starting
        send(song, to: pid)
    }

    private func send(_ song: LastMusicSong, to pid: pid_t?) {
        songTimer?.invalidate()
        songTimer = nil
        play(pid, song) { [weak self] accepted in
            guard let self = self, self.status == .starting, self.song == song else { return }
            guard accepted else {
                // Gone from the library, most likely: it can't be offered again
                os_log("%{public}s[%{public}ld], %{public}s: Music wouldn't play %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song.persistentID)
                self.store.forget(song)
                self.finish(self.isRunning() ? .couldNotPlay : .idle)
                return
            }
            let wait = self.retried ? MusicStarter.songWait : MusicStarter.retryWait
            self.songTimer = self.clock.schedule(after: wait, repeats: false) { [weak self] in
                self?.songWaitEnded()
            }
        }
    }

    /// Music answered a while ago and hasn't been seen playing
    private func songWaitEnded() {
        songTimer = nil
        guard status == .starting else { return }
        guard isRunning(), !isPlaying() else { return finish() }
        if !retried {
            askAgain(because: "no song is playing")
        } else if hasTrack() {
            // A song is loaded, and Play in the popover now plays or pauses it
            finish()
        } else {
            os_log("%{public}s[%{public}ld], %{public}s: Music played nothing after being asked twice", ((#file as NSString).lastPathComponent), #line, #function)
            finish(.couldNotPlay)
        }
    }

    private func askAgain(because reason: String) {
        guard let song = song else { return finish() }
        os_log("%{public}s[%{public}ld], %{public}s: asking Music again for %{public}s, because %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song.persistentID, reason)
        retried = true
        // Running by now, so by bundle ID
        send(song, to: nil)
    }

    @objc private func iTunesPlayerDidUpdated(_ notification: Notification) {
        playerDidUpdate()
    }

    /// Music announced a player update. A song playing means the start is done; Music
    /// quitting ends it too. Nothing is asked of Music while nothing is under way: this runs
    /// on every player update.
    func playerDidUpdate() {
        switch status {
        case .idle, .opening:
            // Music isn't running yet while it opens, and says nothing of a song until then
            return
        case .couldNotPlay:
            if hasTrack() || !isRunning() {
                finish()
            }
        case .starting:
            guard isRunning() else { return finish() }
            guard hasTrack() else { return }
            if isPlaying() {
                finish()
            }
        }
    }

}

extension MusicStarter {

    /// Music's bundle, for opening it
    static var musicURL: URL? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: OSVersionHelper.bundleIdentifier)
    }

    /// Music's player state on the station's connection, under the short timeout, or nil
    static func playerState() -> iTunesEPlS? {
        return MenuBarRatingControl.withShortTimeoutIfAnswered { $0.playerState }.flatMap { $0 }
    }

    static func musicIsRunning() -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: OSVersionHelper.bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    /// Open Music in the background: the popover stays open, which it wouldn't if Music came
    /// forward, and says what is happening until the song comes
    static func launchMusic(_ completion: @escaping (pid_t?) -> Void) {
        guard let url = musicURL else {
            completion(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            if let error = error {
                os_log("%{public}s[%{public}ld], %{public}s: opening Music failed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            }
            let pid = application?.processIdentifier
            DispatchQueue.main.async { completion(pid) }
        }
    }

    static func activateMusic() {
        guard let url = musicURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Where `play` is sent from: Music can take seconds to answer while it opens, and the
    /// main thread mustn't wait for it
    private static let queue = DispatchQueue(label: "com.rossshannon.starbar.music-starter", qos: .userInitiated)

    /// Counts the Apple Events that failed on one connection
    private final class FailureCounter: NSObject, SBApplicationDelegate {
        private(set) var failures = 0
        func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
            failures += 1
            let (eventClass, eventID) = iTunesRadioStation.classAndID(of: event)
            os_log("%{public}s[%{public}ld], %{public}s: AppleEvent %{public}s/%{public}s failed with error %{public}s", ((#file as NSString).lastPathComponent), #line, #function, eventClass, eventID, error.localizedDescription)
            return nil
        }
    }

    /// Send Music `play` for `song`, found in the library by persistent ID, from a background
    /// queue and on a connection of its own: the station's connection is the main thread's,
    /// and counts failed events there for its own reasons. Addressed by process ID when Music
    /// was just opened, so the event can't open a second copy, and otherwise by bundle ID.
    ///
    /// The track is a reference Music resolves when `play` arrives, so finding it costs no
    /// event of its own beyond finding the library, and a song deleted since fails the
    /// command rather than playing another.
    static func askMusicToPlay(_ pid: pid_t?, song: LastMusicSong, completion: @escaping (Bool) -> Void) {
        queue.async {
            let application = pid.flatMap { SBApplication(processIdentifier: $0) }
                ?? SBApplication(bundleIdentifier: OSVersionHelper.bundleIdentifier)
            let counter = FailureCounter()
            application?.delegate = counter
            // A Music still opening answers once it has loaded its library: 2.2 to 2.5 s after
            // `open` on 2026-11-04
            application?.timeout = 15 * 60  // ticks: 1/60 s each
            let started = Date()
            var accepted = false
            if let iTunes = application as? iTunesApplication,
               let source = iTunesRadioStation.librarySource(of: iTunes),
               let tracks = iTunesRadioStation.libraryPlaylist(of: source)?.tracks?(),
               let found = iTunesRadioStation.tracks(tracks, matching: NSPredicate(format: "persistentID == %@", song.persistentID)),
               let track = found.object(at: 0) as? iTunesTrack {
                track.playOnce?(false)
                accepted = counter.failures == 0
            }
            os_log("%{public}s[%{public}ld], %{public}s: asked Music to play %{public}s (%{public}s) in %.0f ms: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song.name, song.persistentID, Date().timeIntervalSince(started) * 1000, accepted ? "taken" : "refused")
            withExtendedLifetime(counter) {}
            DispatchQueue.main.async { completion(accepted) }
        }
    }

}
