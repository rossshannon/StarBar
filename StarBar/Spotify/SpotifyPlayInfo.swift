//
//  SpotifyPlayInfo.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-10-21.
//

import Foundation

/// What Spotify's `com.spotify.client.PlaybackStateChanged` notification says.
///
/// The notification is undocumented. Measured 2026-10-21 with Spotify 1.3.5 on macOS 27
/// (`docs/spotify.md`), every payload had the same 13 keys, among them Name, Artist, Album,
/// Track ID (a `spotify:` URI), Player State ("Playing" or "Paused"), Has Artwork (a Bool),
/// Duration (an Int, milliseconds) and Playback Position (a Double, seconds). It carries no
/// artwork itself.
///
/// It posts on play, pause, resume and a change of song, about a second after the command.
/// It posts **nothing** on a seek, or when a song goes back to its start (Previous more than
/// about three seconds in), so it can't tell the strip that a song restarted.
struct SpotifyPlayInfo: Equatable {

    enum State: Equatable {
        case playing
        case paused
        /// An explicit "Stopped". Measured 2026-10-21, Spotify sent one with no other key when
        /// it quit, and another a few seconds after it launched. Other projects report one
        /// with no Track ID just before Spotify plays something new, like Music's bare Stopped
        /// between songs.
        case stopped
        /// No Player State, or one this code doesn't know: changes nothing
        case unknown
    }

    /// What the Track ID says is playing
    enum Content: Equatable {
        case track
        /// A podcast or audiobook episode
        case episode
        /// A file from the user's own disk, added to Spotify
        case local
        /// Anything else, ads included, and no ID at all. Never announced.
        case other
    }

    /// A `spotify:` URI, such as `spotify:track:4uLU6hMCjMI75M1A2tKUQC`, or nil
    let trackID: String?
    let name: String?
    let artist: String?
    let album: String?
    let state: State
    /// Milliseconds
    let duration: Int?
    /// False when Spotify says the song has no artwork. True when it didn't say.
    let hasArtwork: Bool

    init(trackID: String?, name: String?, artist: String?, album: String?, state: State, duration: Int? = nil, hasArtwork: Bool = true) {
        self.trackID = trackID.flatMap { $0.isEmpty ? nil : $0 }
        self.name = name
        self.artist = artist
        self.album = album
        self.state = state
        self.duration = duration
        self.hasArtwork = hasArtwork
    }

    /// From the notification's userInfo. Unknown keys are ignored and a missing one is nil.
    init(userInfo: [AnyHashable: Any]) {
        func string(_ key: String) -> String? {
            return userInfo[key] as? String
        }
        let state: State
        switch string("Player State") {
        case "Playing": state = .playing
        case "Paused": state = .paused
        case "Stopped": state = .stopped
        default: state = .unknown
        }
        self.init(
            trackID: string("Track ID"),
            name: string("Name"),
            artist: string("Artist"),
            album: string("Album"),
            state: state,
            duration: (userInfo["Duration"] as? NSNumber)?.intValue,
            hasArtwork: (userInfo["Has Artwork"] as? NSNumber)?.boolValue ?? true
        )
    }

    var content: Content {
        guard let trackID = trackID else { return .other }
        if trackID.hasPrefix("spotify:track:") { return .track }
        if trackID.hasPrefix("spotify:episode:") { return .episode }
        if trackID.hasPrefix("spotify:local:") { return .local }
        return .other
    }

    /// True for what the strip may show: songs, episodes and local files. An allow-list
    /// rather than a block-list of ads, because no ad payload has been captured: an ad in a
    /// shape nobody has seen then stays silent instead of sliding up a strip.
    var isAnnounceable: Bool {
        return content != .other
    }

}

extension SpotifyPlayInfo {

    /// As the strip sees it. Something that can't be announced (an ad) has no identity, so
    /// the strip and the menu bar keep what they were showing.
    var snapshot: TrackAnnouncementController.PlayerSnapshot {
        let snapshotState: TrackAnnouncementController.PlayerSnapshot.State
        switch state {
        case .playing: snapshotState = .playing
        case .paused: snapshotState = .paused
        case .stopped: snapshotState = .stopped
        case .unknown: snapshotState = .unknown
        }
        // An episode has no artist: measured 2026-10-21, Artist was empty and Album held the
        // show's name. So the show goes on the artist line, and the album line is left empty.
        let isEpisode = content == .episode && (self.artist ?? "").isEmpty
        let artist = isEpisode ? (self.album ?? "") : (self.artist ?? "")
        let album = isEpisode ? "" : (self.album ?? "")
        return TrackAnnouncementController.PlayerSnapshot(
            identity: isAnnounceable ? trackID : nil,
            state: snapshotState,
            title: name ?? "",
            artist: artist,
            album: album,
            hasArtwork: hasArtwork && content != .local,
            source: .spotify
        )
    }

}
