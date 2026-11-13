//
//  Scrobble.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation

/// One play that counts, as Last.fm is told about it
struct Scrobble: Codable, Equatable {

    /// What Last.fm is told about a song, for "now playing" and for a scrobble alike
    struct Track: Codable, Equatable {
        var title: String
        var artist: String
        var album: String?
        /// Only when it differs from `artist`
        var albumArtist: String?
        var trackNumber: Int?
        /// Seconds, or nil when the player gave none
        var duration: TimeInterval?

        init(title: String, artist: String, album: String? = nil, albumArtist: String? = nil, trackNumber: Int? = nil, duration: TimeInterval? = nil) {
            self.title = title
            self.artist = artist
            self.album = album
            self.albumArtist = albumArtist
            self.trackNumber = trackNumber
            self.duration = duration
        }

        /// Last.fm takes nothing without a title and an artist
        var canBeSent: Bool {
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var track: Track
    /// When the song started playing
    var startedAt: Date
    /// The `PlayerKind` raw value of the player it was heard in. Kept for the log; Last.fm
    /// isn't told.
    var source: String

    init(track: Track, startedAt: Date, source: String) {
        self.track = track
        self.startedAt = startedAt
        self.source = source
    }

    /// What Last.fm wants for `timestamp`: whole seconds since 1970, UTC
    var timestamp: Int {
        return Int(startedAt.timeIntervalSince1970)
    }

}
