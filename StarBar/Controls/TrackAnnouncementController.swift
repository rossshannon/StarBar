//
//  TrackAnnouncementController.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Foundation
import Cocoa
import os

/// Shows the announcement strip when a new track starts playing, like Growl's "Music Video"
/// display used to.
///
/// `AppDelegate` calls `playerDidUpdate()` after each player update. The controller keeps the
/// identity of the last track it saw, even while the setting is off, so only a change of track
/// announces: pause, resume, seeking and rating edits never do. A new track while a strip is
/// showing replaces it; nothing is queued.
final class TrackAnnouncementController: NSObject {

    /// What the announcement needs to know about the player
    struct PlayerSnapshot {

        enum State {
            case playing
            case paused
            /// Music stopped or quit. Clears the last track, so the next play announces.
            case stopped
            /// The payload said nothing about the player (a `sourceSaved` notification, for
            /// instance). Changes nothing.
            case unknown
        }

        /// Music's persistent ID as a 16-character hex string, `name|artist|album` for a
        /// stream with no ID, or nil when there is nothing to identify the track by
        let identity: String?
        let state: State
        let title: String
        let artist: String
        let album: String
        /// False when Music says the track has no artwork, so the loader is skipped
        let hasArtwork: Bool
    }

    /// What the artwork loader found
    enum ArtworkLoad {
        case loaded(NSImage?)
        /// Music has already moved on to another track; a notification for it is on its way
        case trackChanged
    }

    /// The one controller, created by `AppDelegate`, for Preferences and the menus
    static var shared: TrackAnnouncementController?

    static let holdDuration = TrackAnnouncementLayout.holdDuration
    static let slideDuration = TrackAnnouncementLayout.slideDuration

    /// Reads the player now, or returns nil when Music isn't running
    private let readPlayer: () -> PlayerSnapshot?
    /// Loads the artwork for the track with this identity
    private let loadArtwork: (String) -> ArtworkLoad
    private let presenter: TrackAnnouncementPresenter
    private let clock: RatingReminderClock
    private let accessibility: () -> (reduceMotion: Bool, reduceTransparency: Bool)

    private(set) var isEnabled: Bool
    /// Identity of the last track seen playing (or there at launch), announced or not
    private var lastIdentity: String?
    /// The last snapshot that identified a track, for menu validation and on-demand showing
    /// without another read of the player
    private var lastSnapshot: PlayerSnapshot?
    private var hideTimer: RatingReminderTimer?

    init(
        readPlayer: @escaping () -> PlayerSnapshot?,
        loadArtwork: @escaping (String) -> ArtworkLoad,
        presenter: TrackAnnouncementPresenter,
        clock: RatingReminderClock = RunLoopClock(),
        accessibility: @escaping () -> (reduceMotion: Bool, reduceTransparency: Bool) = {
            (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
             NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        },
        isEnabled: Bool
    ) {
        self.readPlayer = readPlayer
        self.loadArtwork = loadArtwork
        self.presenter = presenter
        self.clock = clock
        self.accessibility = accessibility
        self.isEnabled = isEnabled
        super.init()
    }

    deinit {
        hideTimer?.invalidate()
    }

}

extension TrackAnnouncementController {

    /// The player changed: a new track, play or pause, a rating. Announces when a different
    /// track is playing.
    ///
    /// - Parameter seedOnly: true at launch, to record the track already playing without
    ///   announcing it
    func playerDidUpdate(seedOnly: Bool = false) {
        guard let snapshot = readPlayer() else {
            lastIdentity = nil
            lastSnapshot = nil
            return
        }
        // A payload that says nothing about the player, or nothing about the track
        // (sourceSaved sends one), must not reset the last track, or the next real
        // notification would announce it again
        guard snapshot.state != .unknown else { return }
        if snapshot.state == .stopped {
            lastIdentity = nil
            lastSnapshot = nil
            return
        }
        guard let identity = snapshot.identity else { return }
        lastSnapshot = snapshot
        let isNewTrack = identity != lastIdentity
        // A track counts as seen once it has played (or was there at launch). One the user
        // skipped to while paused is still new when they press play; a resumed one is not.
        if snapshot.state == .playing || seedOnly {
            lastIdentity = identity
        }
        guard isNewTrack, snapshot.state == .playing, isEnabled, !seedOnly else { return }
        announce(snapshot, identity: identity)
    }

    /// True when there is a track to show on demand. Answers from the last update, so menu
    /// validation never sends an Apple Event.
    var canShowCurrentTrack: Bool {
        guard let snapshot = lastSnapshot, snapshot.identity != nil else { return false }
        return !snapshot.title.isEmpty
    }

    /// Show the current track now, whatever the setting and whether or not it is playing.
    /// Reads the player afresh; falls back to the last update when the read has no track.
    func showCurrentTrack() {
        let fresh = readPlayer()
        let snapshot = (fresh?.identity != nil ? fresh : nil) ?? lastSnapshot
        guard let snapshot = snapshot, let identity = snapshot.identity, !snapshot.title.isEmpty else {
            os_log(.debug, "%{public}s[%{public}ld], %{public}s: no current track to show", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }
        announce(snapshot, identity: identity)
    }

    /// Show the sample strip, for the Preferences Preview button
    func preview() {
        present(TrackAnnouncement.preview)
    }

    /// The Preferences checkbox changed
    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    @objc func showCurrentTrackMenuItemPressed(_ sender: Any?) {
        showCurrentTrack()
    }

    private func announce(_ snapshot: PlayerSnapshot, identity: String) {
        var artwork: NSImage?
        if snapshot.hasArtwork {
            switch loadArtwork(identity) {
            case .loaded(let image):
                artwork = image
            case .trackChanged:
                os_log(.debug, "%{public}s[%{public}ld], %{public}s: track changed before its artwork loaded; waiting for the next update", ((#file as NSString).lastPathComponent), #line, #function)
                return
            }
        }
        let announcement = TrackAnnouncement(
            identity: identity,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            artwork: artwork
        )
        os_log("%{public}s[%{public}ld], %{public}s: announcing %{public}s", ((#file as NSString).lastPathComponent), #line, #function, announcement.accessibilityLabel)
        present(announcement)
    }

    /// Show the strip and start (or restart) the hold timer
    private func present(_ announcement: TrackAnnouncement) {
        let preferences = accessibility()
        presenter.show(announcement, reduceMotion: preferences.reduceMotion, reduceTransparency: preferences.reduceTransparency)
        hideTimer?.invalidate()
        let hold = TrackAnnouncementController.holdDuration + TrackAnnouncementController.slideDuration
        hideTimer = clock.schedule(after: hold, repeats: false) { [weak self] in
            self?.hideTimer = nil
            self?.presenter.hide()
        }
    }

}

// MARK: - Menu validation

extension TrackAnnouncementController: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(TrackAnnouncementController.showCurrentTrackMenuItemPressed(_:)) else { return true }
        return canShowCurrentTrack
    }

}

// MARK: - Snapshots from Music

extension TrackAnnouncementController.PlayerSnapshot {

    /// Music's persistent ID, as the Scripting Bridge reports it: 16 uppercase hex digits of
    /// the same 64 bits the `playerInfo` notification carries as a signed integer
    static func identity(persistentID: Int) -> String {
        return String(format: "%016llX", UInt64(bitPattern: Int64(persistentID)))
    }

    /// True when `identity` is a persistent ID rather than a stream's `name|artist|album`
    static func isPersistentID(_ identity: String) -> Bool {
        return identity.count == 16 && identity.allSatisfy { $0.isHexDigit }
    }

    /// Whether the track Music has now is the one an announcement is for
    enum LiveTrackMatch: Equatable {
        /// Same track: attach its artwork
        case same
        /// Music has moved on; a notification for the new track is on its way
        case changed
        /// Music could not say which track it has (a timed-out read): show no artwork
        case unknown
    }

    /// Compare an announcement's identity with the live track's Scripting Bridge fields.
    /// `livePersistentID` is nil or empty when the read failed or the track is a stream.
    static func liveTrackMatch(identity: String, livePersistentID: String?, liveName: String?, liveArtist: String?, liveAlbum: String?) -> LiveTrackMatch {
        if isPersistentID(identity) {
            guard let liveID = livePersistentID, !liveID.isEmpty else { return .unknown }
            return liveID.uppercased() == identity ? .same : .changed
        }
        // A stream: match on the same name|artist|album the identity was built from
        guard let liveIdentity = TrackAnnouncementController.PlayerSnapshot.identity(name: liveName, artist: liveArtist, album: liveAlbum) else { return .unknown }
        return liveIdentity == identity ? .same : .changed
    }

    /// Music's Scripting Bridge player state as an announcement state
    static func state(for playerState: iTunesEPlS?) -> State {
        switch playerState {
        case .playing, .fastForwarding, .rewinding:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return .stopped
        case .none:
            return .unknown
        }
    }

    /// Identity for a track with no persistent ID (a stream), or nil when there is no name
    static func identity(name: String?, artist: String?, album: String?) -> String? {
        guard let name = name, !name.isEmpty else { return nil }
        return [name, artist ?? "", album ?? ""].joined(separator: "|")
    }

    /// From the `playerInfo` notification payload: no Apple Events
    init(playInfo: PlayInfo) {
        let name = playInfo.name ?? ""
        if let persistentID = playInfo.persistentID {
            identity = TrackAnnouncementController.PlayerSnapshot.identity(persistentID: persistentID)
        } else {
            identity = TrackAnnouncementController.PlayerSnapshot.identity(name: playInfo.name, artist: playInfo.artist, album: playInfo.album)
        }
        switch playInfo.playerState {
        case .playing:
            state = .playing
        case .paused:
            state = .paused
        case .unknown:
            // Music's "Stopped" decodes as unknown
            state = .stopped
        case .none:
            // No Player State key at all: this payload says nothing about the player
            state = .unknown
        }
        title = name
        artist = playInfo.artist ?? ""
        album = playInfo.album ?? ""
        hasArtwork = playInfo.artworkCount != 0
    }

    /// From the Scripting Bridge, for the launch gap before Music's first notification.
    /// Each property read is an Apple Event; call inside `MenuBarRatingControl.withShortTimeout`.
    init(track: iTunesTrack, playerState: iTunesEPlS?) {
        let name = track.name ?? ""
        let artist = track.artist ?? ""
        let album = track.album ?? ""
        if let persistentID = track.persistentID, !persistentID.isEmpty {
            identity = persistentID.uppercased()
        } else {
            identity = TrackAnnouncementController.PlayerSnapshot.identity(name: name, artist: artist, album: album)
        }
        state = TrackAnnouncementController.PlayerSnapshot.state(for: playerState)
        title = name
        self.artist = artist
        self.album = album
        hasArtwork = true
    }

}

// MARK: - Presenter

/// The strip itself. `TrackAnnouncementPanel` on screen; a fake in tests.
protocol TrackAnnouncementPresenter: AnyObject {
    /// Show this announcement, replacing whatever is showing
    func show(_ announcement: TrackAnnouncement, reduceMotion: Bool, reduceTransparency: Bool)
    func hide()
}
