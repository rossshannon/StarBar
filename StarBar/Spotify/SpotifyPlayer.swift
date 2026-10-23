//
//  SpotifyPlayer.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-10-21.
//

import Cocoa
import ScriptingBridge
import os

extension Notification.Name {
    /// Spotify played, paused, stopped, changed song, launched or quit. Main thread.
    static let spotifyPlayerDidUpdate = Notification.Name("StarBarSpotifyPlayerDidUpdate")
    /// A sleeve arrived for a Spotify song. `userInfo[SpotifyPlayer.identityKey]` is its
    /// Track ID. Main thread.
    static let spotifyArtworkDidLoad = Notification.Name("StarBarSpotifyArtworkDidLoad")
}

/// What Spotify is playing, for the strip and the menu bar.
///
/// Spotify posts `com.spotify.client.PlaybackStateChanged` on every play, pause, stop and
/// song change, with the song's name, artist, album and Track ID. That notification alone
/// drives everything here: no Apple Event is needed to know a song started. The only Apple
/// Events are for the artwork URL (the notification has none) and for the song already
/// playing at launch, and they:
/// - run on a background queue, because Spotify's AppleScript can be slow and the menu bar
///   must not wait for it;
/// - go to Spotify's process ID, after `NSRunningApplication` says it is running, so a
///   Spotify that has quit is never launched again by StarBar. An `SBApplication` made from a
///   bundle ID would relaunch it;
/// - go through Scripting Bridge by key (`value(forKey: "artworkUrl")`) rather than a vendored
///   header: three properties don't justify one, and the names come from Spotify's sdef;
/// - read one property at a time, because `properties of current track` fails while
///   Spotify's `starred` raises error -10000.
///
/// Rating and favourites don't exist here: Spotify's AppleScript can't set Liked Songs.
///
/// State is read and written on the main thread only.
final class SpotifyPlayer {

    static let bundleIdentifier = "com.spotify.client"
    static let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")
    static let identityKey = "identity"

    static let shared = SpotifyPlayer()

    /// Spotify's last notification, or what was read at launch. Nil when Spotify isn't running.
    private(set) var latest: SpotifyPlayInfo?
    /// Called on the main thread with the song found playing at launch, before the update
    /// that reports it, so the strip records it as seen rather than announcing it
    var didSeed: ((SpotifyPlayInfo) -> Void)?

    private let artworkLoader = SpotifyArtworkLoader()
    /// Sleeves for the last few songs, by Track ID
    private var artwork: [(identity: String, image: NSImage)] = []
    private let queue = DispatchQueue(label: "com.rossshannon.starbar.spotify", qos: .userInitiated)
    /// Whether this launch has asked for permission to control Spotify yet
    private var hasAskedPermission = false

    /// Same test as `iTunesRadioStation`'s: tests are hosted in the app, and a real Spotify
    /// changing songs during a run must not reach them
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private init() {}

    /// Subscribe to Spotify's notifications and read the song already playing, if StarBar
    /// already has permission to ask. Never under tests or UI tests.
    func start() {
        guard !SpotifyPlayer.isRunningTests, !MenuBarRatingControl.isUITesting else { return }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(SpotifyPlayer.playbackStateChanged(_:)), name: SpotifyPlayer.notificationName, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(SpotifyPlayer.applicationDidLaunch(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(SpotifyPlayer.applicationDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        seed()
    }

    /// Spotify's process, when it is running. No Apple Event.
    var runningApplication: NSRunningApplication? {
        return NSRunningApplication.runningApplications(withBundleIdentifier: SpotifyPlayer.bundleIdentifier).first { !$0.isTerminated }
    }

    var isRunning: Bool {
        return runningApplication != nil
    }

    /// The sleeve for a song, if it has arrived. No Apple Event, no network.
    func artwork(for identity: String) -> NSImage? {
        return artwork.first { $0.identity == identity }?.image
    }

    /// Bring Spotify to the front. Does nothing when Spotify isn't running, so a click on a
    /// menu bar left showing after Spotify quit doesn't launch it again.
    ///
    /// Not `NSWorkspace.open` on the song's `spotify:` URI, which would show the song itself:
    /// measured 2026-10-21, opening a URI drives playback instead, and not consistently. A
    /// different song played straight away when Spotify was paused and did nothing when it was
    /// playing, the song already playing paused or restarted, and Spotify never came to the
    /// front. The sdef has no command that only reveals a song.
    func activate() {
        guard let application = runningApplication else {
            os_log("%{public}s[%{public}ld], %{public}s: Spotify isn't running; not opening it", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }
        application.activate(options: [])
    }

}

// MARK: - Notifications

extension SpotifyPlayer {

    @objc private func playbackStateChanged(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.playbackStateChanged(notification) }
            return
        }
        let userInfo = notification.userInfo ?? [:]
        // The whole payload, so the first sandboxed run proves the userInfo arrives at all
        os_log("%{public}s[%{public}ld], %{public}s: Spotify payload %{public}s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: userInfo))
        let info = SpotifyPlayInfo(userInfo: userInfo)
        if info.state == .unknown, let previous = latest {
            // A payload that says nothing about the player changes nothing
            os_log(.debug, "%{public}s[%{public}ld], %{public}s: Spotify payload with no player state; keeping %{public}s", ((#file as NSString).lastPathComponent), #line, #function, previous.trackID ?? "nil")
            return
        }
        latest = info
        NotificationCenter.default.post(name: .spotifyPlayerDidUpdate, object: nil)
        if info.isAnnounceable, info.hasArtwork, info.state != .stopped, let trackID = info.trackID, artwork(for: trackID) == nil {
            loadArtwork(for: trackID)
        }
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard SpotifyPlayer.isSpotify(notification) else { return }
        // Spotify posts its own notification when it starts playing; this is for the
        // arbiter, which only follows a player it knows is running
        NotificationCenter.default.post(name: .spotifyPlayerDidUpdate, object: nil)
    }

    @objc private func applicationDidTerminate(_ notification: Notification) {
        guard SpotifyPlayer.isSpotify(notification) else { return }
        os_log("%{public}s[%{public}ld], %{public}s: Spotify quit, clearing its player", ((#file as NSString).lastPathComponent), #line, #function)
        latest = nil
        NotificationCenter.default.post(name: .spotifyPlayerDidUpdate, object: nil)
    }

    private static func isSpotify(_ notification: Notification) -> Bool {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return application?.bundleIdentifier == bundleIdentifier
    }

}

// MARK: - Apple Events

extension SpotifyPlayer {

    /// What one background read of Spotify found
    private struct Reading {
        var trackID: String?
        var name: String?
        var artist: String?
        var album: String?
        var artworkURL: String?
        var state: SpotifyPlayInfo.State = .unknown
    }

    /// Read the song already playing at launch, but only when StarBar may already control
    /// Spotify: asking at launch would put a permission prompt in front of someone who may
    /// never play anything in Spotify. Without it, a song paused at launch may announce once
    /// when it is resumed.
    private func seed() {
        guard let pid = runningApplication?.processIdentifier else { return }
        queue.async { [weak self] in
            guard SpotifyPlayer.permission(ask: false) == noErr else {
                os_log("%{public}s[%{public}ld], %{public}s: no permission to control Spotify yet; not reading it at launch", ((#file as NSString).lastPathComponent), #line, #function)
                return
            }
            guard let reading = SpotifyPlayer.read(pid: pid, includingSong: true) else { return }
            DispatchQueue.main.async {
                guard let self = self, self.latest == nil, reading.state != .unknown else { return }
                let info = SpotifyPlayInfo(trackID: reading.trackID, name: reading.name, artist: reading.artist, album: reading.album, state: reading.state)
                os_log("%{public}s[%{public}ld], %{public}s: Spotify has %{public}s at launch", ((#file as NSString).lastPathComponent), #line, #function, info.trackID ?? "nothing")
                self.latest = info
                self.didSeed?(info)
                NotificationCenter.default.post(name: .spotifyPlayerDidUpdate, object: nil)
                if let trackID = info.trackID, info.isAnnounceable, let url = reading.artworkURL.flatMap(URL.init(string:)) {
                    self.download(url, for: trackID)
                }
            }
        }
    }

    /// Ask Spotify for the artwork URL of `trackID`, then download it. The first time, this
    /// is what asks the user for permission to control Spotify.
    private func loadArtwork(for trackID: String) {
        guard let pid = runningApplication?.processIdentifier else { return }
        let ask = !hasAskedPermission
        hasAskedPermission = true
        queue.async { [weak self] in
            let status = SpotifyPlayer.permission(ask: ask)
            guard status == noErr else {
                os_log("%{public}s[%{public}ld], %{public}s: may not control Spotify (%{public}d); showing its songs without artwork", ((#file as NSString).lastPathComponent), #line, #function, status)
                return
            }
            guard let reading = SpotifyPlayer.read(pid: pid, includingSong: false) else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Spotify may have moved on, most often while the permission prompt waited for
                // an answer. The read is then for the song playing now, so it is kept as long
                // as that is the song the notifications last named: that song's own
                // notification came before permission did, so nothing else will fetch it.
                guard let readID = reading.trackID, readID == trackID || readID == self.latest?.trackID,
                      let url = reading.artworkURL.flatMap(URL.init(string:)) else {
                    os_log(.debug, "%{public}s[%{public}ld], %{public}s: no artwork URL for %{public}s (Spotify has %{public}s)", ((#file as NSString).lastPathComponent), #line, #function, trackID, reading.trackID ?? "nil")
                    return
                }
                guard self.artwork(for: readID) == nil else { return }
                self.download(url, for: readID)
            }
        }
    }

    private func download(_ url: URL, for trackID: String) {
        artworkLoader.load(url) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.artwork.removeAll { $0.identity == trackID }
            self.artwork.append((trackID, image))
            if self.artwork.count > SpotifyArtworkLoader.cacheSize {
                self.artwork.removeFirst(self.artwork.count - SpotifyArtworkLoader.cacheSize)
            }
            NotificationCenter.default.post(name: .spotifyArtworkDidLoad, object: nil, userInfo: [SpotifyPlayer.identityKey: trackID])
        }
    }

    /// Whether StarBar may send Spotify Apple Events. With `ask`, shows the system's prompt
    /// if the user hasn't answered it yet, and waits for the answer. Background queue only.
    private static func permission(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
    }

    /// One read of Spotify's player, addressed to its process, under a one-second timeout
    /// per Apple Event. Nil when Spotify can't be reached or raised. Background queue only.
    private static func read(pid: pid_t, includingSong: Bool) -> Reading? {
        guard let application = SBApplication(processIdentifier: pid) else { return nil }
        application.timeout = 60  // ticks: 1/60 s each
        do {
            return try ExceptionCatcher.catchException {
                var reading = Reading()
                guard let track = application.value(forKey: "currentTrack") as? SBObject else { return reading }
                reading.trackID = track.value(forKey: "id") as? String
                reading.artworkURL = track.value(forKey: "artworkUrl") as? String
                if includingSong {
                    reading.name = track.value(forKey: "name") as? String
                    reading.artist = track.value(forKey: "artist") as? String
                    reading.album = track.value(forKey: "album") as? String
                    reading.state = SpotifyPlayer.state(application.value(forKey: "playerState"))
                }
                return reading
            } as? Reading
        } catch {
            os_log("%{public}s[%{public}ld], %{public}s: reading Spotify failed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            return nil
        }
    }

    /// Spotify's `player state` enumeration: 'kPSP' playing, 'kPSp' paused, 'kPSS' stopped,
    /// the same four-character codes as Music's
    private static func state(_ value: Any?) -> SpotifyPlayInfo.State {
        let code: UInt32?
        if let number = value as? NSNumber {
            code = number.uint32Value
        } else if let descriptor = value as? NSAppleEventDescriptor {
            code = descriptor.enumCodeValue
        } else {
            code = nil
        }
        switch code {
        case 0x6b505350: return .playing   // 'kPSP'
        case 0x6b505370: return .paused    // 'kPSp'
        case 0x6b505353: return .stopped   // 'kPSS'
        default: return .unknown
        }
    }

}
