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
///
/// **A Music that has just opened may not take an Apple Event at all**: in two cold presses of
/// seven on 2026-11-05, Scripting Bridge logged "couldn't resolve" about 150 ms after the
/// launch and the `play` never went out, which the first build took for Music refusing the
/// song, and so forgot a song that was in the library all along. So only Music saying the song
/// isn't there (`PlayAnswer.songNotFound`) forgets it; anything else is `notReady`, and the
/// `play` is sent again every `notReadyWait`, up to `notReadyTries` times.
final class MusicStarter {

    /// What came of asking Music to play a song
    enum PlayAnswer: Equatable {
        /// Music took the `play`
        case taken
        /// Music answered that there is no such track: gone from the library, most likely
        case songNotFound
        /// The `play` didn't reach Music, or Music failed it for some other reason
        case notReady
    }

    enum Status: Equatable {
        /// Nothing under way
        case idle
        /// Music wasn't running and is being opened
        case opening
        /// Music has been asked to play a song and hasn't been seen playing it yet
        case starting
        /// Music has no such song, never took the `play`, or took it and no song came: the next
        /// press brings Music forward to choose something instead
        case couldNotPlay
    }

    /// How long after Music answers `play` a song may take to start before it is asked for
    /// once more. Measured 2026-11-04, a library song was playing 1.3 to 1.4 s after Music
    /// answered, running or just opened.
    static let retryWait: TimeInterval = 3

    /// How long after Music answers the second `play` the song may take to start before the
    /// popover says Music couldn't play it. A streamed song takes a moment to buffer.
    static let songWait: TimeInterval = 6

    /// How long to wait before sending a `play` again that didn't reach Music, and how many
    /// times to send it in all. Measured 2026-11-05, the two that didn't came 130 to 180 ms
    /// after Music was launched, and every cold `play` that did was answered 2.1 to 2.8 s
    /// after it was sent, so three seconds of tries covers a Music still opening.
    static let notReadyWait: TimeInterval = 0.5
    static let notReadyTries = 6

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
    /// Whether the process with this ID is still there. No Apple Event.
    private let isAlive: (pid_t) -> Bool
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
    /// then call back on the main thread with what came of it
    private let play: (pid_t?, LastMusicSong, @escaping (PlayAnswer) -> Void) -> Void
    /// Open Music and bring it forward, so the user can choose something to play
    private let activate: () -> Void
    private let clock: RatingReminderClock
    private var songTimer: RatingReminderTimer?
    /// The song asked for by the press under way
    private var song: LastMusicSong?
    /// The Music this press opened, which every `play` for it is sent to, or nil for the one
    /// that was running
    private var pid: pid_t?
    /// Whether this press has asked Music a second time, which it does at most once
    private var retried = false
    /// How many `play`s for this press didn't reach Music
    private var notReadyCount = 0

    init(isRunning: @escaping () -> Bool = MusicStarter.musicIsRunning,
         isAlive: @escaping (pid_t) -> Bool = MusicStarter.processIsAlive,
         hasTrack: @escaping () -> Bool = { iTunesPlayer.shared.currentTrack != nil },
         isPlaying: @escaping () -> Bool = { MusicStarter.playerState() == .playing },
         store: LastMusicSongStore = .shared,
         launch: @escaping (@escaping (pid_t?) -> Void) -> Void = MusicStarter.launchMusic,
         play: @escaping (pid_t?, LastMusicSong, @escaping (PlayAnswer) -> Void) -> Void = MusicStarter.askMusicToPlay,
         activate: @escaping () -> Void = MusicStarter.activateMusic,
         clock: RatingReminderClock = RunLoopClock(),
         center: NotificationCenter = .default) {
        self.isRunning = isRunning
        self.isAlive = isAlive
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

    /// Whether the Music this press is for is running: the one it opened, by process ID, or
    /// else whichever is. `NSRunningApplication` lists a Music just opened only some seconds
    /// later (2.5 s on 2026-11-05), which ended a press as though Music had quit in the moment
    /// its first `play` went unanswered.
    private func musicRunning() -> Bool {
        guard let pid = pid else { return isRunning() }
        return isAlive(pid)
    }

    /// Back to nothing under way
    private func finish(_ next: Status = .idle) {
        songTimer?.invalidate()
        songTimer = nil
        song = nil
        pid = nil
        status = next
    }

    private func bringMusicForward() {
        os_log("%{public}s[%{public}ld], %{public}s: nothing for StarBar to start; bringing Music forward to choose something", ((#file as NSString).lastPathComponent), #line, #function)
        status = .idle
        activate()
    }

    private func askToPlay(_ song: LastMusicSong, in pid: pid_t?) {
        self.song = song
        self.pid = pid
        retried = false
        notReadyCount = 0
        status = .starting
        send(song)
    }

    private func send(_ song: LastMusicSong) {
        songTimer?.invalidate()
        songTimer = nil
        play(pid, song) { [weak self] answer in
            guard let self = self, self.status == .starting, self.song == song else { return }
            switch answer {
            case .songNotFound:
                // Gone from the library, most likely: it can't be offered again
                os_log("%{public}s[%{public}ld], %{public}s: Music has no song %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song.persistentID)
                self.store.forget(song)
                self.finish(self.musicRunning() ? .couldNotPlay : .idle)
            case .notReady:
                self.notReady(song)
            case .taken:
                let wait = self.retried ? MusicStarter.songWait : MusicStarter.retryWait
                self.songTimer = self.clock.schedule(after: wait, repeats: false) { [weak self] in
                    self?.songWaitEnded()
                }
            }
        }
    }

    /// The `play` didn't reach Music: send it again shortly, as long as Music is running and
    /// there are tries left. The song is kept whatever happens, since Music never said it
    /// wasn't there.
    private func notReady(_ song: LastMusicSong) {
        guard musicRunning() else { return finish() }
        notReadyCount += 1
        guard notReadyCount < MusicStarter.notReadyTries else {
            os_log("%{public}s[%{public}ld], %{public}s: Music didn't take the play %{public}ld times", ((#file as NSString).lastPathComponent), #line, #function, notReadyCount)
            return finish(.couldNotPlay)
        }
        songTimer = clock.schedule(after: MusicStarter.notReadyWait, repeats: false) { [weak self] in
            guard let self = self else { return }
            self.songTimer = nil
            guard self.status == .starting, self.song == song else { return }
            guard self.musicRunning() else { return self.finish() }
            self.send(song)
        }
    }

    /// Music answered a while ago and hasn't been seen playing
    private func songWaitEnded() {
        songTimer = nil
        guard status == .starting else { return }
        guard musicRunning(), !isPlaying() else { return finish() }
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
        send(song)
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
            if hasTrack() || !musicRunning() {
                finish()
            }
        case .starting:
            guard musicRunning() else { return finish() }
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

    /// Whether the process is there. A signal 0 sends nothing; `EPERM` means it is there and
    /// StarBar may not signal it, which the sandbox may say.
    static func processIsAlive(_ pid: pid_t) -> Bool {
        return kill(pid, 0) == 0 || errno == EPERM
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

    /// Counts the Apple Events that failed on one connection, and keeps the last one's code
    private final class FailureCounter: NSObject, SBApplicationDelegate {
        private(set) var failures = 0
        private(set) var lastCode: Int?
        func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
            failures += 1
            lastCode = (error as NSError).code
            let (eventClass, eventID) = iTunesRadioStation.classAndID(of: event)
            os_log("%{public}s[%{public}ld], %{public}s: AppleEvent %{public}s/%{public}s failed with error %{public}ld, %{public}s", ((#file as NSString).lastPathComponent), #line, #function, eventClass, eventID, (error as NSError).code, error.localizedDescription)
            return nil
        }
    }

    /// The codes Music answers a `play` for a track that isn't there with: errAENoSuchObject
    /// and errAEIllegalIndex
    static let noSuchTrackCodes: Set<Int> = [-1728, -1719]

    /// What a `play` came to, from what the connection saw
    ///
    /// - Parameters:
    ///   - sent: whether the `play` went out at all, which it doesn't when Music's library
    ///     can't be found
    ///   - failed: whether the `play` itself failed
    ///   - code: the failure's code
    static func answer(sent: Bool, failed: Bool, code: Int?) -> PlayAnswer {
        guard sent else { return .notReady }
        guard failed else { return .taken }
        return code.map { MusicStarter.noSuchTrackCodes.contains($0) } == true ? .songNotFound : .notReady
    }

    /// Send Music `play` for `song`, found in the library by persistent ID, from a background
    /// queue and on a connection of its own: the station's connection is the main thread's,
    /// and counts failed events there for its own reasons. Addressed by process ID when Music
    /// was just opened, so the event can't open a second copy, and otherwise by bundle ID.
    ///
    /// The track is a reference Music resolves when `play` arrives, so finding it costs no
    /// event of its own beyond finding the library, and a song deleted since fails the
    /// command rather than playing another.
    static func askMusicToPlay(_ pid: pid_t?, song: LastMusicSong, completion: @escaping (PlayAnswer) -> Void) {
        queue.async {
            let application = pid.flatMap { SBApplication(processIdentifier: $0) }
                ?? SBApplication(bundleIdentifier: OSVersionHelper.bundleIdentifier)
            let counter = FailureCounter()
            application?.delegate = counter
            // A Music still opening answers once it has loaded its library: 2.2 to 2.5 s after
            // `open` on 2026-11-04
            application?.timeout = 15 * 60  // ticks: 1/60 s each
            let started = Date()
            var sent = false
            var failed = false
            if let iTunes = application as? iTunesApplication,
               let source = iTunesRadioStation.librarySource(of: iTunes),
               let tracks = iTunesRadioStation.libraryPlaylist(of: source)?.tracks?(),
               let found = iTunesRadioStation.tracks(tracks, matching: NSPredicate(format: "persistentID == %@", song.persistentID)),
               let track = found.object(at: 0) as? iTunesTrack {
                let failuresBefore = counter.failures
                track.playOnce?(false)
                sent = true
                failed = counter.failures > failuresBefore
            }
            let answer = MusicStarter.answer(sent: sent, failed: failed, code: counter.lastCode)
            os_log("%{public}s[%{public}ld], %{public}s: asked Music to play %{public}s (%{public}s) in %.0f ms: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song.name, song.persistentID, Date().timeIntervalSince(started) * 1000, String(describing: answer))
            withExtendedLifetime(counter) {}
            DispatchQueue.main.async { completion(answer) }
        }
    }

}
