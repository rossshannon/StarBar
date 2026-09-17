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
///
/// Called from the main thread only, like the rest of the menu bar.
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
        /// False when Music says the track has no artwork, so the artwork read is skipped
        let hasArtwork: Bool
        /// Music's rating, 0 to 100, when the source carried it
        let rating: Int?
        /// Music's favourite flag, when the source carried it
        let isFavorited: Bool?

        init(identity: String?, state: State, title: String, artist: String, album: String, hasArtwork: Bool, rating: Int? = nil, isFavorited: Bool? = nil) {
            self.identity = identity
            self.state = state
            self.title = title
            self.artist = artist
            self.album = album
            self.hasArtwork = hasArtwork
            self.rating = rating
            self.isFavorited = isFavorited
        }
    }

    /// What Music says about the announced track right now
    struct LiveTrack {
        var artwork: NSImage? = nil
        /// 0 to 100; nil when it could not be read
        var rating: Int? = nil
        var isFavorited: Bool? = nil
    }

    /// What the live-track loader found
    enum LiveTrackLoad {
        case loaded(LiveTrack)
        /// Music has already moved on to another track; a notification for it is on its way
        case trackChanged
    }

    /// The one controller, created by `AppDelegate`, for Preferences and the menus
    static var shared: TrackAnnouncementController?

    static let holdDuration = TrackAnnouncementLayout.holdDuration
    static let slideDuration = TrackAnnouncementLayout.slideDuration
    /// How long a rating chosen in StarBar wins over Music's reads: the save delay, plus
    /// time for the Apple Event
    static let pendingRatingLifetime = iTunesRadioStation.ratingSaveDelay + 1.0

    /// Reads the player now, or returns nil when Music isn't running
    private let readPlayer: () -> PlayerSnapshot?
    /// Reads the live track's rating, favourite flag and, when asked, artwork, for the track
    /// with this identity
    private let loadLiveTrack: (_ identity: String, _ wantsArtwork: Bool) -> LiveTrackLoad
    /// Reads the identity of the track Music has now, or nil when it can't say. One Apple
    /// Event, so a rating can be matched to its track without a full live read.
    private let readCurrentIdentity: () -> String?
    private let presenter: TrackAnnouncementPresenter
    private let clock: RatingReminderClock
    private let accessibility: () -> (reduceMotion: Bool, reduceTransparency: Bool)

    private(set) var isEnabled: Bool
    /// Identity of the last track seen playing (or there at launch), announced or not
    private var lastIdentity: String?
    /// The last snapshot that identified a track, for menu validation and on-demand showing
    /// without another read of the player
    private var lastSnapshot: PlayerSnapshot?
    /// What the strip is showing while the hold timer runs
    private var currentAnnouncement: TrackAnnouncement?
    private var hideTimer: RatingReminderTimer?
    /// A rating the user just chose in StarBar. Music usually has it at once, but a rating
    /// that arrives in the shadow of another can wait up to `iTunesRadioStation.ratingSaveDelay`,
    /// so until this expires it wins over Music's reads.
    private var pendingRating: (identity: String, rating: Int, expires: Date)?

    init(
        readPlayer: @escaping () -> PlayerSnapshot?,
        loadLiveTrack: @escaping (_ identity: String, _ wantsArtwork: Bool) -> LiveTrackLoad,
        readCurrentIdentity: @escaping () -> String?,
        presenter: TrackAnnouncementPresenter,
        clock: RatingReminderClock = RunLoopClock(),
        accessibility: @escaping () -> (reduceMotion: Bool, reduceTransparency: Bool) = {
            (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
             NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        },
        isEnabled: Bool
    ) {
        self.readPlayer = readPlayer
        self.loadLiveTrack = loadLiveTrack
        self.readCurrentIdentity = readCurrentIdentity
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
        guard snapshot.state != .unknown else {
            // Music sends sourceSaved when the song is rated in Music itself: show the change.
            // The payload says nothing dependable about which track it is for, so only
            // Music's live read is believed, and the strip keeps its own words.
            if let current = currentAnnouncement, hideTimer != nil,
               snapshot.identity == nil || snapshot.identity == current.identity {
                refreshFromMusic(current)
            }
            return
        }
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
        if !isNewTrack, let current = currentAnnouncement, current.identity == identity, hideTimer != nil {
            // The song on the strip changed (a rating, the heart): show the new state
            refresh(current, from: snapshot, identity: identity)
            return
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
    /// Returns false when there is no track to show, or the track changed while its details
    /// were loading and the announcement was dropped.
    @discardableResult
    func showCurrentTrack() -> Bool {
        let fresh = readPlayer()
        let snapshot = (fresh?.identity != nil ? fresh : nil) ?? lastSnapshot
        guard let snapshot = snapshot, let identity = snapshot.identity, !snapshot.title.isEmpty else {
            os_log(.debug, "%{public}s[%{public}ld], %{public}s: no current track to show", ((#file as NSString).lastPathComponent), #line, #function)
            return false
        }
        return announce(snapshot, identity: identity)
    }

    /// The Preferences Preview button: the current track when Music has one, so the preview
    /// is the real thing, else the sample strip. A track change under the first read gets
    /// one more read, which sees the new track, before the sample.
    func preview() {
        if showCurrentTrack() || showCurrentTrack() { return }
        present(TrackAnnouncement.preview)
    }

    /// The Preferences checkbox changed
    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    @objc func showCurrentTrackMenuItemPressed(_ sender: Any?) {
        showCurrentTrack()
    }

    /// The user chose a rating for the current track in StarBar. Shows it on the strip now,
    /// without asking Music, which may not have the rating for up to `ratingSaveDelay`.
    ///
    /// - Parameter rating: 0 to 100
    func userDidRate(_ rating: Int) {
        guard let identity = ratedTrackIdentity() else { return }
        pendingRating = (identity, rating, clock.now().addingTimeInterval(TrackAnnouncementController.pendingRatingLifetime))
        updateStrip(identity: identity) { TrackAnnouncement(copying: $0, rating: rating) }
    }

    /// The user toggled the current track's heart in StarBar. Shows it on the strip now.
    ///
    /// The heart needs no counterpart to `pendingRating`: `iTunesTrack.updateFavorited(_:)`
    /// writes to Music at once, so Music's next read already has it.
    func userDidFavorite(_ isFavorited: Bool) {
        guard let identity = ratedTrackIdentity() else { return }
        updateStrip(identity: identity) { TrackAnnouncement(copying: $0, isFavorited: isFavorited) }
    }

    /// The track a rating chosen in StarBar belongs to: the one Music is playing.
    ///
    /// While the strip is up, Music is asked which track that is (one Apple Event), so a
    /// rating chosen in the gap between Music changing track and its notification arriving
    /// never lands on the song the strip is showing. With no strip up there is nothing to
    /// draw, so the last update's track is good enough and nothing is asked.
    private func ratedTrackIdentity() -> String? {
        guard let current = currentAnnouncement, hideTimer != nil else { return lastSnapshot?.identity }
        // A read Music can't answer leaves the strip as the best guess, as elsewhere here
        guard let live = readCurrentIdentity(), live != current.identity else { return current.identity }
        os_log(.debug, "%{public}s[%{public}ld], %{public}s: the rating is for %{public}s, which the strip isn't showing", ((#file as NSString).lastPathComponent), #line, #function, live)
        return nil
    }

    /// Redraw the strip if it is up and showing the track with this identity
    private func updateStrip(identity: String, _ change: (TrackAnnouncement) -> TrackAnnouncement) {
        guard let current = currentAnnouncement, hideTimer != nil, current.identity == identity else { return }
        let updated = change(current)
        guard updated != current else { return }
        os_log("%{public}s[%{public}ld], %{public}s: strip now shows rating %{public}ld, favourite %{public}s", ((#file as NSString).lastPathComponent), #line, #function, updated.rating, String(updated.isFavorited))
        currentAnnouncement = updated
        presenter.refresh(updated)
    }

    /// The rating to show: the user's own rating while Music has yet to save it, otherwise
    /// Music's, and then the notification's.
    ///
    /// Music is believed again as soon as it reports the saved rating, so a change made in
    /// Music straight afterwards isn't held back for the rest of the wait.
    private func rating(for identity: String, live: Int?, payload: Int?) -> Int? {
        expirePendingRating()
        let known = live ?? payload
        guard let pending = pendingRating, pending.identity == identity else { return known }
        guard known != pending.rating else {
            // Music has the rating now
            pendingRating = nil
            return known
        }
        return pending.rating
    }

    /// Forget the user's rating once Music has had time to save it
    private func expirePendingRating() {
        guard let pending = pendingRating, clock.now() >= pending.expires else { return }
        pendingRating = nil
    }

    /// Returns false when the announcement was dropped because the track changed under it
    @discardableResult
    private func announce(_ snapshot: PlayerSnapshot, identity: String) -> Bool {
        guard let live = loadLive(identity: identity, wantsArtwork: snapshot.hasArtwork) else { return false }
        let announcement = TrackAnnouncement(
            identity: identity,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            rating: rating(for: identity, live: live.rating, payload: snapshot.rating) ?? 0,
            isFavorited: live.isFavorited ?? snapshot.isFavorited ?? false,
            artwork: live.artwork
        )
        os_log("%{public}s[%{public}ld], %{public}s: announcing %{public}s", ((#file as NSString).lastPathComponent), #line, #function, announcement.accessibilityLabel)
        present(announcement)
        return true
    }

    /// The song on the strip changed while the strip is up: redraw its rating and heart,
    /// keeping the artwork and the hold timer
    private func refresh(_ current: TrackAnnouncement, from snapshot: PlayerSnapshot, identity: String) {
        guard let live = loadLive(identity: identity, wantsArtwork: false) else { return }
        let updated = TrackAnnouncement(
            identity: identity,
            title: snapshot.title.isEmpty ? current.title : snapshot.title,
            artist: snapshot.artist.isEmpty ? current.artist : snapshot.artist,
            album: snapshot.album.isEmpty ? current.album : snapshot.album,
            rating: rating(for: identity, live: live.rating, payload: snapshot.rating) ?? current.rating,
            isFavorited: live.isFavorited ?? snapshot.isFavorited ?? current.isFavorited,
            artwork: current.artwork
        )
        guard updated != current else { return }
        currentAnnouncement = updated
        presenter.refresh(updated)
    }

    /// Redraw the strip's rating and heart from Music alone, for a notification that says
    /// nothing dependable about the track it is for
    private func refreshFromMusic(_ current: TrackAnnouncement) {
        guard let live = loadLive(identity: current.identity, wantsArtwork: false) else { return }
        let updated = TrackAnnouncement(
            copying: current,
            rating: rating(for: current.identity, live: live.rating, payload: nil) ?? current.rating,
            isFavorited: live.isFavorited ?? current.isFavorited
        )
        guard updated != current else { return }
        currentAnnouncement = updated
        presenter.refresh(updated)
    }

    /// Music's live view of the track, or nil when Music has moved on to another track
    private func loadLive(identity: String, wantsArtwork: Bool) -> LiveTrack? {
        switch loadLiveTrack(identity, wantsArtwork) {
        case .loaded(let live):
            return live
        case .trackChanged:
            os_log(.debug, "%{public}s[%{public}ld], %{public}s: track changed before its details loaded; waiting for the next update", ((#file as NSString).lastPathComponent), #line, #function)
            return nil
        }
    }

    /// Show the strip and start (or restart) the hold timer
    private func present(_ announcement: TrackAnnouncement) {
        let preferences = accessibility()
        currentAnnouncement = announcement
        presenter.show(announcement, reduceMotion: preferences.reduceMotion, reduceTransparency: preferences.reduceTransparency)
        hideTimer?.invalidate()
        let hold = TrackAnnouncementController.holdDuration + TrackAnnouncementController.slideDuration
        hideTimer = clock.schedule(after: hold, repeats: false) { [weak self] in
            self?.hideTimer = nil
            self?.currentAnnouncement = nil
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
        rating = playInfo.notComputedRating
        // The notification says nothing about the heart; the live read fills it in
        isFavorited = nil
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
        rating = track.userRating
        isFavorited = track.isFavorited
    }

}

// MARK: - Presenter

/// The strip itself. `TrackAnnouncementPanel` on screen; a fake in tests.
protocol TrackAnnouncementPresenter: AnyObject {
    /// Show this announcement, replacing whatever is showing
    func show(_ announcement: TrackAnnouncement, reduceMotion: Bool, reduceTransparency: Bool)
    /// Redraw the strip with this announcement if it is up; do nothing if it is hidden
    func refresh(_ announcement: TrackAnnouncement)
    func hide()
}
