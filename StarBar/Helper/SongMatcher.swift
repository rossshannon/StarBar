//
//  SongMatcher.swift
//  StarBar
//
//  Finding a song another player is playing among the user's own Music library. Pure rule,
//  no Apple Events: see `SongMatcherTests`.
//

import Foundation

/// One track of the user's Music library, as it was when the library was read
struct LibrarySong: Equatable {
    /// Music's persistent ID, the hexadecimal string Scripting Bridge reads. What the track is
    /// fetched by before anything is shown or written.
    let persistentID: String
    let name: String
    let artist: String
    let albumArtist: String
    let album: String
    /// Seconds, or nil when Music had none
    let duration: Double?
    /// 0 to 100. Only used to choose between copies: what is shown is read from Music again.
    let rating: Int
    /// True when Music worked the rating out from the album's rather than the user setting it
    let isRatingComputed: Bool
    let playedCount: Int

    /// The user chose this track's rating themselves
    var isRatedByUser: Bool {
        return rating > 0 && !isRatingComputed
    }
}

/// What another player says is playing
struct SongQuery: Equatable {
    let name: String
    /// One name: Spotify's notification carries the main artist only, and anyone featured in
    /// the title
    let artist: String
    let album: String
    /// Seconds, or nil
    let duration: Double?
}

/// The user's Music library, keyed for finding the song another player is playing.
///
/// Two tracks are the same song when their titles agree once edition words are dropped, they
/// share an artist, and they mark the same kind of recording: a live or remixed version is a
/// different song from the studio one. `SongName` holds the rules.
///
/// Album and duration never decide whether it is the same song: "Move On Up" is 2:46 as the
/// single edit and 8:49 on the album. They only choose between copies when the user has the
/// song more than once -- 442 songs in the library measured on 2026-10-28, 103 of them with
/// copies rated differently -- so the same copy is chosen every time the song comes round.
///
/// A wrong match puts the user's rating on a song they didn't mean, in a library Music keeps
/// no history of. So the rules lean strict: a song that isn't found is shown as it was before
/// StarBar looked, and nothing is lost.
struct SongMatcher {

    private struct Entry {
        let song: LibrarySong
        /// Everyone credited on the track: its artists, its album artist, anyone featured
        let artists: Set<String>
        let versions: Set<String>
        let album: String
    }

    private let byTitle: [String: [Entry]]

    /// How many tracks it was built from
    let count: Int

    init(library: [LibrarySong]) {
        var byTitle: [String: [Entry]] = [:]
        for song in library {
            let title = SongName.title(song.name)
            guard !title.core.isEmpty else { continue }
            var artists = SongName.artists(song.artist).union(title.featured)
            if !song.albumArtist.isEmpty {
                artists.formUnion(SongName.artists(song.albumArtist))
            }
            byTitle[title.core, default: []].append(Entry(song: song, artists: artists,
                                                          versions: title.versions,
                                                          album: SongName.album(song.album)))
        }
        self.byTitle = byTitle
        count = library.count
    }

    /// Every copy of the song the user has, the one to show and rate first. Empty when they
    /// don't have it.
    func copies(of query: SongQuery) -> [LibrarySong] {
        let title = SongName.title(query.name)
        let artist = SongName.artist(query.artist)
        guard !title.core.isEmpty, !artist.isEmpty else { return [] }

        // The query's artist is compared whole and never split, and the library keeps a band
        // named like a list whole (`SongName.artists(_:)`), so "Earth" can't find "Earth,
        // Wind & Fire"
        let credited = Set([artist]).union(title.featured)
        let album = SongName.album(query.album)
        return (byTitle[title.core] ?? [])
            .filter { !$0.artists.isDisjoint(with: credited) && $0.versions == title.versions }
            .sorted { SongMatcher.choose($0, over: $1, album: album, duration: query.duration) }
            .map { $0.song }
    }

    /// The copy to show and rate, or nil when the user doesn't have the song
    func match(for query: SongQuery) -> LibrarySong? {
        return copies(of: query).first
    }

    /// Which of two copies comes first: the one on the album the query names, then one the
    /// user rated themselves, then the nearest in length, then the one played most. The
    /// persistent ID settles a tie, so the order never depends on the library's.
    private static func choose(_ a: Entry, over b: Entry, album: String, duration: Double?) -> Bool {
        let albumA = closeness(of: a.album, to: album), albumB = closeness(of: b.album, to: album)
        if albumA != albumB {
            return albumA < albumB
        }
        if a.song.isRatedByUser != b.song.isRatedByUser {
            return a.song.isRatedByUser
        }
        let lengthA = distance(a.song.duration, duration), lengthB = distance(b.song.duration, duration)
        if lengthA != lengthB {
            return lengthA < lengthB
        }
        if a.song.playedCount != b.song.playedCount {
            return a.song.playedCount > b.song.playedCount
        }
        return a.song.persistentID < b.song.persistentID
    }

    /// 0 for the same album, 1 when one name holds all the other's words ("abba gold" and
    /// "abba gold greatest hits"), 2 otherwise
    static func closeness(of album: String, to other: String) -> Int {
        guard !album.isEmpty, !other.isEmpty else { return 2 }
        if album == other {
            return 0
        }
        let words = Set(album.split(separator: " ")), otherWords = Set(other.split(separator: " "))
        return words.isSubset(of: otherWords) || otherWords.isSubset(of: words) ? 1 : 2
    }

    /// How far a copy's length is from the query's: 0 for all when the query has none, so it
    /// decides nothing, and furthest for a copy with none
    private static func distance(_ length: Double?, _ wanted: Double?) -> Double {
        guard let wanted = wanted else { return 0 }
        guard let length = length else { return .infinity }
        return abs(length - wanted)
    }

}
