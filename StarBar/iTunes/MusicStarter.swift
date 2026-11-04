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
/// loaded, opening Music first when it isn't running.
///
/// Before this, the button sent Music `playpause`, which does nothing with no song loaded,
/// and nothing at all reached a Music that wasn't running, since the station only talks to a
/// running Music so as never to open it by accident. The button still flipped to Pause, so
/// the popover said something was playing when nothing was. Here the user has asked for
/// Music, so opening it is the point.
///
/// Whether it worked is told by Music announcing a song, the same notification that puts the
/// song in the popover, not by reading the player state back: Music's reply to `play` comes
/// before a streamed song has started, and a read then says stopped. Nothing is polled. One
/// timer runs per press, `songWait` after Music answered, to say so if no song came.
final class MusicStarter {

    enum Status: Equatable {
        /// Nothing under way
        case idle
        /// Music wasn't running and is being opened
        case opening
        /// Music has been asked to play and hasn't announced a song yet
        case starting
        /// Music answered and no song came: there is nothing for it to play, as far as can be
        /// told, so the user has to choose something in Music
        case nothingToPlay
    }

    /// How long after Music answers `play` a song may take to be announced before the popover
    /// says Music has nothing to play. A streamed song takes a moment to buffer.
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
    /// Open Music without bringing it forward, then call back on the main thread with its
    /// process ID, or nil when it couldn't be opened
    private let launch: (@escaping (pid_t?) -> Void) -> Void
    /// Ask the Music with this process ID to play, then call back on the main thread once it
    /// has answered or the event failed
    private let play: (pid_t?, @escaping () -> Void) -> Void
    /// Bring Music forward, so the user can choose something to play
    private let activate: () -> Void
    private let clock: RatingReminderClock
    private var songTimer: RatingReminderTimer?

    init(isRunning: @escaping () -> Bool = MusicStarter.musicIsRunning,
         hasTrack: @escaping () -> Bool = { iTunesPlayer.shared.currentTrack != nil },
         launch: @escaping (@escaping (pid_t?) -> Void) -> Void = MusicStarter.launchMusic,
         play: @escaping (pid_t?, @escaping () -> Void) -> Void = MusicStarter.askMusicToPlay,
         activate: @escaping () -> Void = MusicStarter.activateMusic,
         clock: RatingReminderClock = RunLoopClock(),
         center: NotificationCenter = .default) {
        self.isRunning = isRunning
        self.hasTrack = hasTrack
        self.launch = launch
        self.play = play
        self.activate = activate
        self.clock = clock
        // Asks Music nothing while there is nothing under way (`playerDidUpdate`)
        center.addObserver(self, selector: #selector(MusicStarter.iTunesPlayerDidUpdated(_:)), name: .iTunesPlayerDidUpdated, object: nil)
    }

    /// The play button was pressed with no song loaded
    func start() {
        switch status {
        case .opening, .starting:
            // Already on its way: a second press would only send a second `play`
            return
        case .nothingToPlay where isRunning():
            // Asking again would come to the same thing. Music's own window is where a song
            // can be chosen.
            status = .idle
            activate()
            return
        case .idle, .nothingToPlay:
            break
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
                self.askToPlay(pid)
            }
            return
        }
        askToPlay(nil)
    }

    private func askToPlay(_ pid: pid_t?) {
        status = .starting
        play(pid) { [weak self] in
            guard let self = self, self.status == .starting else { return }
            self.songTimer?.invalidate()
            self.songTimer = self.clock.schedule(after: MusicStarter.songWait, repeats: false) { [weak self] in
                guard let self = self else { return }
                self.songTimer = nil
                guard self.status == .starting else { return }
                if self.hasTrack() || !self.isRunning() {
                    self.status = .idle
                } else {
                    os_log("%{public}s[%{public}ld], %{public}s: Music announced no song after being asked to play", ((#file as NSString).lastPathComponent), #line, #function)
                    self.status = .nothingToPlay
                }
            }
        }
    }

    @objc private func iTunesPlayerDidUpdated(_ notification: Notification) {
        playerDidUpdate()
    }

    /// Music announced a player update. A song in it means Music is playing, or has a song
    /// to play, and whatever this was doing is done; so does Music quitting, once it had
    /// been opened. Nothing is asked of Music while nothing is under way: this runs on every
    /// player update.
    func playerDidUpdate() {
        guard status != .idle else { return }
        // Music isn't running yet while it opens, and says nothing of a song until then
        guard status != .opening else { return }
        guard hasTrack() || !isRunning() else { return }
        songTimer?.invalidate()
        songTimer = nil
        status = .idle
    }

}

extension MusicStarter {

    /// Music's bundle, for opening it
    static var musicURL: URL? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: OSVersionHelper.bundleIdentifier)
    }

    static func musicIsRunning() -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: OSVersionHelper.bundleIdentifier)
            .filter { !$0.isTerminated }.isEmpty
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

    /// Where `play` is sent from: Music can take seconds to answer while it opens, and the
    /// main thread mustn't wait for it
    private static let queue = DispatchQueue(label: "com.rossshannon.starbar.music-starter", qos: .userInitiated)

    /// Send Music `play` from a background queue, on a connection of its own: the station's
    /// connection is the main thread's, and it counts failed events there for other reasons.
    /// Addressed by process ID when Music was just opened, so the event can't open a second
    /// copy, and otherwise by bundle ID to the Music already running.
    static func askMusicToPlay(_ pid: pid_t?, completion: @escaping () -> Void) {
        queue.async {
            let application = pid.flatMap { SBApplication(processIdentifier: $0) }
                ?? SBApplication(bundleIdentifier: OSVersionHelper.bundleIdentifier)
            // A Music still opening answers once it has loaded its library
            application?.timeout = 15 * 60  // ticks: 1/60 s each
            let started = Date()
            (application as? iTunesApplication)?.playOnce?(false)
            os_log("%{public}s[%{public}ld], %{public}s: Music answered play in %.0f ms", ((#file as NSString).lastPathComponent), #line, #function, Date().timeIntervalSince(started) * 1000)
            DispatchQueue.main.async(execute: completion)
        }
    }

    static func activateMusic() {
        guard let url = musicURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

}
