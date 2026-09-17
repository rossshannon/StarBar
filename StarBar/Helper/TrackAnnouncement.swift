//
//  TrackAnnouncement.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Foundation
import Cocoa

/// What the announcement strip shows for one track. A plain value, so the Preview button,
/// the UI tests and the unit tests can show a strip without Music.
struct TrackAnnouncement: Equatable {

    /// Music's persistent ID as a 16-character hex string, or `name|artist|album` for a
    /// stream with no ID. Two announcements with the same identity are the same track.
    let identity: String
    let title: String
    let artist: String
    let album: String
    /// Music's rating, 0 to 100; 0 is unrated and shows as five dots
    let rating: Int
    /// Music's favourite flag, the heart after the stars
    let isFavorited: Bool
    /// Album artwork, or nil to show the placeholder
    let artwork: NSImage?

    init(identity: String, title: String, artist: String, album: String, rating: Int = 0, isFavorited: Bool = false, artwork: NSImage? = nil) {
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.rating = rating
        self.isFavorited = isFavorited
        self.artwork = artwork
    }

    /// What the Preferences Preview button shows
    static var preview: TrackAnnouncement {
        return TrackAnnouncement(
            identity: "preview",
            title: "Music Video",
            artist: "StarBar",
            album: "A strip like Growl's, for the song that just started",
            rating: 70,
            isFavorited: true,
            artwork: NSApp?.applicationIconImage
        )
    }

    /// What VoiceOver reads when the strip appears
    var accessibilityLabel: String {
        let playing = artist.isEmpty ? "Now playing: \(title)" : "Now playing: \(title) by \(artist)"
        return playing + ". " + RatingControl.accessibilityDescription(rating: rating, isFavorited: isFavorited)
    }

    static func == (lhs: TrackAnnouncement, rhs: TrackAnnouncement) -> Bool {
        return lhs.identity == rhs.identity
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.rating == rhs.rating
            && lhs.isFavorited == rhs.isFavorited
            && lhs.artwork === rhs.artwork
    }

}
