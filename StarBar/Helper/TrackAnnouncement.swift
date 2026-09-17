//
//  TrackAnnouncement.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Foundation
import Cocoa

/// The strip's background, chosen in Preferences
enum TrackAnnouncementStyle: String, CaseIterable {
    /// Growl's flat black at 60 percent
    case classic
    /// A blur of whatever is behind the strip, under a lighter black wash
    case blur
    /// Dark Liquid Glass on macOS 26 and later (built with its SDK); the blur before that
    case glass

    /// The default, and what an unknown stored value falls back to
    static let `default`: TrackAnnouncementStyle = .classic

    init(storedValue: String?) {
        self = storedValue.flatMap(TrackAnnouncementStyle.init(rawValue:)) ?? .default
    }

    /// The Preferences pop-up's wording
    var title: String {
        switch self {
        case .classic: return "Classic (black)"
        case .blur: return "Blur"
        case .glass: return "Liquid Glass"
        }
    }
}

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

    /// The same announcement with a new rating or heart. Nil means "leave as it was";
    /// unrated is 0 and the heart off is false, so both are still passed as themselves.
    init(copying other: TrackAnnouncement, rating: Int? = nil, isFavorited: Bool? = nil) {
        self.init(
            identity: other.identity,
            title: other.title,
            artist: other.artist,
            album: other.album,
            rating: rating ?? other.rating,
            isFavorited: isFavorited ?? other.isFavorited,
            artwork: other.artwork
        )
    }

    /// What the Preferences Preview button shows when Music has no track to show instead
    static var preview: TrackAnnouncement {
        return TrackAnnouncement(
            identity: "preview",
            title: "Music Video",
            artist: "StarBar",
            album: "A strip like Growl's, for the song that just started",
            rating: 70,
            isFavorited: true,
            artwork: previewArtwork
        )
    }

    /// The app icon, cropped to its shape. A macOS icon's canvas has transparent margins
    /// around the rounded square, so drawn as it is it looks smaller than album artwork.
    static var previewArtwork: NSImage? {
        guard let icon = NSApp?.applicationIconImage, icon.size.width > 0 else { return nil }
        let margin: CGFloat = 0.1
        let source = NSRect(
            x: icon.size.width * margin,
            y: icon.size.height * margin,
            width: icon.size.width * (1 - 2 * margin),
            height: icon.size.height * (1 - 2 * margin)
        )
        return NSImage(size: source.size, flipped: false) { rect in
            icon.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
            return true
        }
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
