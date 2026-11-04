//
//  LastMusicSong.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-04.
//

import Foundation
import os

/// The last song from the user's library that StarBar saw Music play, kept across launches,
/// for the player popover's play button to start when Music has nothing loaded.
///
/// Music needs one: measured 2026-11-04, it has no current song after a stop and after every
/// launch, even one after quitting while paused on a song, and in that state it answers
/// `play` and `playpause` without an error and plays nothing.
///
/// Only a song in the library is kept, by persistent ID: a database ID changes every time
/// Music launches (one song had four in four launches the same day), and an Apple Music
/// catalog track's IDs are ephemeral and outside the library, so a catalog song is kept as
/// the user's own copy of it, or not at all.
struct LastMusicSong: Codable, Equatable {
    /// The library track's persistent ID, 16 hex characters
    let persistentID: String
    /// For the popover to name the song before it plays
    let name: String
    let artist: String?

    /// "Analogue" by A-Ha, with real quotation marks
    var displayName: String {
        let title = "\u{201C}\(name.typographicPunctuation)\u{201D}"
        guard let artist = artist, !artist.isEmpty else { return title }
        return "\(title) by \(artist.typographicPunctuation)"
    }

    /// The song to remember from Music's announcement, or nil to keep the one remembered.
    ///
    /// - Parameters:
    ///   - isPlaying: whether the announcement says Music is playing: a song only loaded,
    ///     paused, isn't one the user listened to
    ///   - libraryPersistentID: the persistent ID of the playing song's library track, which
    ///     is the playing track itself unless it is an Apple Music catalog track, when it is
    ///     the user's copy, or nil when they have none
    static func remembering(isPlaying: Bool, libraryPersistentID: String?, name: String?, artist: String?) -> LastMusicSong? {
        guard isPlaying, let id = libraryPersistentID, !id.isEmpty,
              let name = name, !name.isEmpty else { return nil }
        return LastMusicSong(persistentID: id, name: name, artist: artist)
    }

}

/// Where `LastMusicSong` is kept: UserDefaults, written only when the song changes
final class LastMusicSongStore {

    static let defaultsKey = "lastMusicSong"

    static let shared = LastMusicSongStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var song: LastMusicSong? {
        guard let data = defaults.data(forKey: LastMusicSongStore.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LastMusicSong.self, from: data)
    }

    func remember(_ song: LastMusicSong) {
        guard song != self.song, let data = try? JSONEncoder().encode(song) else { return }
        defaults.set(data, forKey: LastMusicSongStore.defaultsKey)
    }

    /// The song can't be played any more (deleted from the library, most likely), so Play
    /// shouldn't offer it again
    func forget(_ song: LastMusicSong) {
        guard self.song == song else { return }
        defaults.removeObject(forKey: LastMusicSongStore.defaultsKey)
    }

}
