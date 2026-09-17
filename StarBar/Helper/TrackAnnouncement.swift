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
    /// Album artwork, or nil to show the placeholder
    let artwork: NSImage?

    init(identity: String, title: String, artist: String, album: String, artwork: NSImage? = nil) {
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
    }

    /// What the Preferences Preview button shows
    static var preview: TrackAnnouncement {
        return TrackAnnouncement(
            identity: "preview",
            title: "Music Video",
            artist: "StarBar",
            album: "A strip like Growl's, for the song that just started",
            artwork: NSApp?.applicationIconImage
        )
    }

    /// What VoiceOver reads when the strip appears
    var accessibilityLabel: String {
        return artist.isEmpty ? "Now playing: \(title)" : "Now playing: \(title) by \(artist)"
    }

    static func == (lhs: TrackAnnouncement, rhs: TrackAnnouncement) -> Bool {
        return lhs.identity == rhs.identity
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.artwork === rhs.artwork
    }

}
