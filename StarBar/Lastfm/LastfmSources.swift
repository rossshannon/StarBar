//
//  LastfmSources.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation
import os

/// What one player says it is doing, in `PlayTracker`'s terms
struct PlayerObservation: Equatable {
    var state: PlayTracker.PlayerState
    /// Nil when the player named no song
    var song: PlayTracker.Song?
    /// Seconds into the song, when the player said (Spotify's notification does)
    var position: TimeInterval?

    init(state: PlayTracker.PlayerState, song: PlayTracker.Song?, position: TimeInterval? = nil) {
        self.state = state
        self.song = song
        self.position = position
    }
}

/// What asking one player found
enum PlayerReport: Equatable {
    /// The player isn't running, or StarBar has heard nothing from it. Its play is forgotten.
    case gone
    /// The player's last word says nothing about what it is doing (a payload with no player
    /// state): change nothing
    case nothingNew
    case observed(PlayerObservation)
}

extension PlayInfo {

    /// Music's notification as the scrobbler sees it. No Apple Events.
    ///
    /// Nil for a payload with no Player State, which changes nothing. "Playing" and "Paused"
    /// are themselves; anything else Music sent ("Stopped") decodes as `.unknown` and is a
    /// stop. A payload that names no song (no persistent ID and no name) has no `song`; one
    /// with an ID and no name is a song that can't be scrobbled, so a play before it still ends.
    ///
    /// The identity is the strip's (`TrackAnnouncementController.PlayerSnapshot`): the
    /// persistent ID as 16 hex digits, or `name|artist|album` when Music sent no ID, so that
    /// `LastfmSources.musicPosition(matching:)` can compare it with a live read. The length
    /// is `totalTime`, which is milliseconds; a zero or missing one is no length. The album
    /// artist is kept only when it isn't the artist. A track number of 0 is none.
    /// `isScrobblable` is `Scrobble.Track.canBeSent`: a radio stream, which has a name and no
    /// artist, is never scrobbled.
    var lastfmObservation: PlayerObservation? {
        let state: PlayTracker.PlayerState
        switch playerState {
        case .none:
            return nil
        case .some(.playing):
            state = .playing
        case .some(.paused):
            state = .paused
        case .some(.unknown):
            // Music's "Stopped" decodes as unknown
            state = .stopped
        }
        // The strip's own snapshot, so the identity can never drift from the one
        // `AppDelegate.readCurrentTrackIdentity(matching:)` answers in the shape of
        guard let identity = TrackAnnouncementController.PlayerSnapshot(playInfo: self).identity else {
            return PlayerObservation(state: state, song: nil)
        }
        let artist = self.artist ?? ""
        let track = Scrobble.Track(
            title: name ?? "",
            artist: artist,
            album: LastfmSources.nonEmpty(album),
            albumArtist: LastfmSources.albumArtist(albumArtist, artist: artist),
            trackNumber: LastfmSources.trackNumber(trackNumber),
            duration: totalTime.flatMap { milliseconds -> TimeInterval? in milliseconds > 0 ? TimeInterval(milliseconds) / 1000 : nil }
        )
        let song = PlayTracker.Song(identity: identity, track: track, isScrobblable: track.canBeSent)
        return PlayerObservation(state: state, song: song)
    }

}

extension SpotifyPlayInfo {

    /// Spotify's notification as the scrobbler sees it.
    ///
    /// Nil when the state is `.unknown`. The identity is the Track ID; a payload with none
    /// has no `song`. Only a song (`.track`) or a local file (`.local`) with a title and an
    /// artist is scrobblable: an episode is a podcast or an audiobook, which Last.fm's own
    /// Spotify link doesn't scrobble either, and anything else may be an ad. The length is
    /// `duration`, which is milliseconds.
    var lastfmObservation: PlayerObservation? {
        let observed: PlayTracker.PlayerState
        switch state {
        case .playing: observed = .playing
        case .paused: observed = .paused
        case .stopped: observed = .stopped
        case .unknown: return nil
        }
        guard let identity = trackID else {
            return PlayerObservation(state: observed, song: nil, position: position)
        }
        let track = Scrobble.Track(
            title: name ?? "",
            artist: artist ?? "",
            album: LastfmSources.nonEmpty(album),
            duration: duration.flatMap { milliseconds -> TimeInterval? in milliseconds > 0 ? TimeInterval(milliseconds) / 1000 : nil }
        )
        let isSong = content == .track || content == .local
        let song = PlayTracker.Song(identity: identity, track: track, isScrobblable: isSong && track.canBeSent)
        return PlayerObservation(state: observed, song: song, position: position)
    }

}

/// The scrobbler's reads of the two players. Main thread only. Each answers nil, or "didn't
/// answer", in UI-test mode, which never touches Music.
enum LastfmSources {

    /// What Music is doing: from its last notification, which costs nothing, or, before the
    /// first one (Music posts nothing when StarBar opens), from one read of the playing track
    /// and the player state under the short timeout, as
    /// `AppDelegate.readAnnouncementSnapshot()` does. That read takes the name, artist, album
    /// and persistent ID from the `PlayingTrack` record, which the menu bar has already read,
    /// and asks Music only for the rest. `.gone` when Music isn't running; `.nothingNew` when
    /// it didn't answer, which includes any one Apple Event of the read failing
    /// (`MenuBarRatingControl.withShortTimeoutIfAnswered`): a timed-out read of whether there
    /// is a track says there is none, and taken for an answer it would end a play.
    static func music() -> PlayerReport {
        guard !MenuBarRatingControl.isUITesting, iTunesRadioStation.shared.iTunes != nil else { return .gone }
        if let playInfo = iTunesRadioStation.shared.latestPlayInfo {
            return playInfo.lastfmObservation.map(PlayerReport.observed) ?? .nothingNew
        }
        let report = MenuBarRatingControl.withShortTimeoutIfAnswered { iTunes -> PlayerReport in
            let player = iTunesPlayer.shared
            guard player.currentTrack != nil else {
                return .observed(PlayerObservation(state: .stopped, song: nil))
            }
            // The record is made when Music's track is first read; without one there is
            // nothing cached to name the song by
            guard let playing = player.playing else { return .nothingNew }
            do {
                return try ExceptionCatcher.catchException {
                    LastfmSources.launchReport(playing: playing, playerState: iTunes.playerState)
                } as? PlayerReport ?? .nothingNew
            } catch {
                os_log(.error, "%{public}s[%{public}ld], %{public}s: reading Music at launch failed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
                return .nothingNew
            }
        }
        return report ?? .nothingNew
    }

    /// What Music is doing, from the playing song's record and the player state. The name,
    /// artist, album and persistent ID are the record's, read once already; the album
    /// artist, length and track number are an Apple Event each. Call inside
    /// `MenuBarRatingControl.withShortTimeout`, and inside `ExceptionCatcher`, since a read
    /// can raise.
    private static func launchReport(playing: PlayingTrack, playerState: iTunesEPlS?) -> PlayerReport {
        let state: PlayTracker.PlayerState
        switch playerState {
        case .some(.playing), .some(.fastForwarding), .some(.rewinding):
            state = .playing
        case .some(.paused):
            state = .paused
        case .some(.stopped):
            state = .stopped
        case .none:
            return .nothingNew
        }
        let identity: String?
        if let id = playing.persistentID?.uppercased(), TrackAnnouncementController.PlayerSnapshot.isPersistentID(id) {
            identity = id
        } else {
            identity = TrackAnnouncementController.PlayerSnapshot.identity(name: playing.name, artist: playing.artist, album: playing.album)
        }
        guard let songIdentity = identity else {
            return .observed(PlayerObservation(state: state, song: nil))
        }
        let artist = playing.artist ?? ""
        let track = Scrobble.Track(
            title: playing.name ?? "",
            artist: artist,
            album: nonEmpty(playing.album),
            albumArtist: albumArtist(playing.track.albumArtist, artist: artist),
            trackNumber: trackNumber(playing.track.trackNumber),
            duration: playing.track.duration.flatMap { seconds -> TimeInterval? in seconds > 0 ? seconds : nil }
        )
        let song = PlayTracker.Song(identity: songIdentity, track: track, isScrobblable: track.canBeSent)
        return .observed(PlayerObservation(state: state, song: song))
    }

    /// What Spotify is doing, from its last notification or the read made at launch
    /// (`SpotifyPlayer.shared.latest`), asking Spotify nothing. `.gone` when there is none,
    /// which is also what Spotify quitting leaves.
    static func spotify() -> PlayerReport {
        guard !MenuBarRatingControl.isUITesting, let info = SpotifyPlayer.shared.latest else { return .gone }
        return info.lastfmObservation.map(PlayerReport.observed) ?? .nothingNew
    }

    /// One read of Music, for `PlayTracker.Effect.checkPosition`: the player's position,
    /// whether it is playing, and whether its song is still `identity`
    /// (`AppDelegate.readCurrentTrackIdentity(matching:)`), all under the short timeout.
    ///
    /// A number Scripting Bridge couldn't read comes back as 0, not nil, so a position of 0
    /// is no answer, as it is for the strip's restart watch. `.unanswered` when Music isn't
    /// running: nothing here may open it.
    static func musicPosition(matching identity: String) -> PlayTracker.PositionReading {
        guard !MenuBarRatingControl.isUITesting, iTunesRadioStation.shared.iTunes != nil else { return .unanswered }
        let position: Double? = MenuBarRatingControl.withShortTimeout { $0.playerPosition } ?? nil
        // A failed read of the state answers some value rather than nil, so only one Music
        // answered counts
        let playerState: iTunesEPlS? = MenuBarRatingControl.withShortTimeoutIfAnswered { $0.playerState } ?? nil
        let liveIdentity = AppDelegate.readCurrentTrackIdentity(matching: identity)
        let isPlaying = playerState.map { state -> Bool in
            switch state {
            case .playing, .fastForwarding, .rewinding: return true
            case .paused, .stopped: return false
            }
        }
        return PlayTracker.PositionReading(
            position: position.flatMap { seconds -> TimeInterval? in seconds > 0 ? seconds : nil },
            isPlaying: isPlaying,
            isSameSong: liveIdentity.map { $0 == identity }
        )
    }

    /// Whether the song `identity`, playing in `kind`, has its heart set in StarBar's terms,
    /// for loving a favourite on Last.fm as it scrobbles. Nil when that isn't known, which
    /// loves nothing.
    ///
    /// Music: the heart of the track the heart belongs to (`PlayingTrack.favoriteTrack`),
    /// read once under the short timeout and only if Music answered
    /// (`MenuBarRatingControl.ifAnswered`), and only when the playing song is still
    /// `identity`, since a late scrobble can arrive after the next song has started.
    /// Spotify: the heart of the user's copy in Music when one is matched
    /// (`LibraryMatchFinder.shared.knownMatch(for:)`, which asks Music nothing), else the
    /// like, when signed in to Spotify (`SpotifyAccount.shared.isLiked`).
    static func isFavorited(_ kind: PlayerKind, identity: String) -> Bool? {
        guard !MenuBarRatingControl.isUITesting else { return nil }
        switch kind {
        case .music:
            guard iTunesRadioStation.shared.iTunes != nil,
                  AppDelegate.readCurrentTrackIdentity(matching: identity) == identity else { return nil }
            // The same read the menu bar makes: the user's copy's heart when they have one
            return MenuBarRatingControl.withShortTimeoutIfAnswered { _ -> Bool? in
                iTunesPlayer.shared.playing?.favoriteTrack.isFavorited
            } ?? nil
        case .spotify:
            if let match = LibraryMatchFinder.shared.knownMatch(for: identity) {
                return match.song.isFavorited
            }
            return SpotifyAccount.shared.isLiked(identity)
        }
    }

    // MARK: - Names as Last.fm takes them

    /// Nil for a missing or empty name. Nothing is trimmed: Last.fm corrects names itself.
    static func nonEmpty(_ text: String?) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        return text
    }

    /// The album artist only when it says something the artist doesn't
    static func albumArtist(_ albumArtist: String?, artist: String) -> String? {
        guard let albumArtist = nonEmpty(albumArtist), albumArtist != artist else { return nil }
        return albumArtist
    }

    /// A track number of 0 or less is none
    static func trackNumber(_ number: Int?) -> Int? {
        guard let number = number, number > 0 else { return nil }
        return number
    }

}
