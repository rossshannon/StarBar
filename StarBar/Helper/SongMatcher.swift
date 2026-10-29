//
//  SongMatcher.swift
//  StarBar
//
//  Finding a song another player is playing among the user's own Music library. Pure rule,
//  no Apple Events: see `SongMatcherTests`.
//

import Foundation

/// One track of the user's Music library.
///
/// `MusicLibraryIndex` reads the persistent ID and the names, which are what finding a song
/// takes. The rest chooses between copies or is shown for the one chosen, and
/// `LibraryMatchFinder` reads it from Music for the few copies a song has; until then it
/// holds these defaults.
struct LibrarySong: Equatable {
    /// Music's persistent ID, the hexadecimal string Scripting Bridge reads. What the track is
    /// fetched by before anything is shown or written.
    let persistentID: String
    let name: String
    let artist: String
    let albumArtist: String
    var album: String = ""
    /// Seconds, or nil when Music had none
    var duration: Double? = nil
    /// 0 to 100
    var rating: Int = 0
    /// True when Music worked the rating out from the album's rather than the user setting it
    var isRatingComputed: Bool = false
    var playedCount: Int = 0
    var isFavorited: Bool = false

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
/// Two tracks are the same song when their titles agree once edition words are dropped, the
/// copy credits Spotify's artist as one of its own, and they mark the same kind of recording:
/// a live or remixed version is a different song from the studio one. `SongName` holds the
/// rules. The kind of recording comes from the album's name as well as the title's, but the
/// index holds no albums, so that part waits for `ranked(_:for:)`, once the copies' albums
/// have been read.
///
/// Album and length choose between copies when the user has the song more than once -- 442
/// songs in the library measured on 2026-10-28, 103 of them with copies rated differently --
/// so the same copy is chosen every time the song comes round. Neither rules a copy out on
/// its own: "Sweet Harmony" is 4:22 on the single and 15:18 on the album. Only a title that
/// names no song, such as "Intro" or "Interlude", has to be on the same release, since every
/// album can have one (`SongName.isGenericTitle`).
///
/// A wrong match puts the user's rating on a song they didn't mean, in a library Music keeps
/// no history of. So the rules lean strict: a song that isn't found is shown as it was before
/// StarBar looked, and nothing is lost.
struct SongMatcher {

    private struct Entry {
        let song: LibrarySong
        let work: Worked
    }

    /// A track's names, which are all an entry is worked out from
    private struct Names: Hashable {
        let name: String
        let artist: String
        let albumArtist: String
        let album: String

        init(_ song: LibrarySong) {
            name = song.name
            artist = song.artist
            albumArtist = song.albumArtist
            album = song.album
        }
    }

    /// What `SongName` makes of a track's names
    private struct Worked {
        let core: String
        /// The track's own artists and its album artist, never a guest (`SongName.artists(_:)`)
        let artists: Set<String>
        /// Everyone the track credits, guests too, for a "(with ...)" to be checked against
        let credits: Set<String>
        /// Who its title credits with "with" (`SongName.Title.withNames`)
        let withNames: Set<String>
        let versions: Set<String>
        let album: String

        init(_ names: Names) {
            let title = SongName.title(names.name)
            var artists = SongName.artists(names.artist)
            var guests = SongName.guests(names.artist)
            // Most tracks name the same artist twice, and this runs for every track in the
            // library: about 420 ms of the first read measured on 2026-10-29
            if !names.albumArtist.isEmpty, names.albumArtist != names.artist {
                artists.formUnion(SongName.artists(names.albumArtist))
                guests.formUnion(SongName.guests(names.albumArtist))
            }
            core = title.core
            self.artists = artists
            credits = artists.union(guests).union(title.featured)
            withNames = Set(title.withNames)
            versions = title.versions
            album = SongName.album(names.album)
        }
    }

    private let byTitle: [String: [Entry]]
    /// Each track's names as worked out, for the next matcher to reuse
    private let worked: [Names: Worked]

    /// How many tracks it was built from
    let count: Int

    /// `previous` is the matcher built from the library before it changed. Working out a
    /// track's names is most of the build, 1.2 to 1.6 s for 8,092 tracks measured on
    /// 2026-10-29 against 0.6 s to read them, and a library change leaves nearly every name
    /// as it was, so a track whose names are unchanged takes what `previous` worked out.
    init(library: [LibrarySong], reusing previous: SongMatcher? = nil) {
        var byTitle: [String: [Entry]] = [:]
        var worked: [Names: Worked] = [:]
        worked.reserveCapacity(library.count)
        for song in library {
            let names = Names(song)
            let work = worked[names] ?? previous?.worked[names] ?? Worked(names)
            worked[names] = work
            guard !work.core.isEmpty else { continue }
            byTitle[work.core, default: []].append(Entry(song: song, work: work))
        }
        self.byTitle = byTitle
        self.worked = worked
        count = library.count
    }

    /// Every copy of the song the user might have, going by the names alone, in no particular
    /// order: `ranked(_:for:)` orders them once what chooses between them has been read.
    /// Empty when they don't have it.
    ///
    /// A copy's title can say less than the query's: "Idioteque" on "I Might Be Wrong: Live
    /// Recordings" is the live song Spotify calls "Idioteque - Live", so a copy is kept
    /// whenever the kinds of recording its title marks, the query's title or album marks too.
    /// `ranked(_:for:)` then holds each copy to the query once its album has been read, and
    /// leaves out one that is a different recording after all.
    ///
    /// Someone a title credits with "with" has to be credited on the other side too: "Stay
    /// (with Justin Bieber)" is the "Stay" by The Kid LAROI & Justin Bieber, but "Yesterday
    /// (With Strings)" is not the Beatles' "Yesterday".
    func copies(of query: SongQuery) -> [LibrarySong] {
        let title = SongName.title(query.name)
        let artist = SongName.artist(query.artist)
        guard !title.core.isEmpty, !artist.isEmpty else { return [] }

        // Spotify's artist is compared whole and never split, and the library keeps a band
        // named like a list whole, so "Earth" can't find "Earth, Wind & Fire". Anyone featured
        // in Spotify's title is left out too: on their own they would find their own song of
        // the same name.
        let kinds = SongName.versions(of: query.name, on: query.album)
        let credits = Set([artist]).union(title.featured)
        let withNames = Set(title.withNames)
        return (byTitle[title.core] ?? [])
            .filter {
                $0.work.artists.contains(artist)
                    && SongName.kinds(of: $0.work.versions).isSubset(of: kinds)
                    && withNames.isSubset(of: $0.work.credits)
                    && $0.work.withNames.isSubset(of: credits)
            }
            .map { $0.song }
    }

    /// Whether a copy's title marks the same kinds of recording as the query's: "One (Live)"
    /// for "One - Live", but not plain "One", which is only a candidate in case its album says
    /// it is live
    static func titleMarksTheSame(_ copy: LibrarySong, as query: SongQuery) -> Bool {
        return SongName.kinds(of: SongName.title(copy.name).versions) == SongName.kinds(of: SongName.title(query.name).versions)
    }

    /// Copies from `copies(of:)` whose album, length, rating and plays have since been read,
    /// the one to show and rate first, and without any whose album makes it a different
    /// recording from the song `query` names: one on "Live at the Fillmore West" when Spotify
    /// is playing the studio song, or the other way round, or another night's live recording
    /// (`SongName.isSameRecording`), or an "Intro" on another album.
    static func ranked(_ copies: [LibrarySong], for query: SongQuery) -> [LibrarySong] {
        let album = SongName.album(query.album)
        let isGeneric = SongName.isGenericTitle(SongName.title(query.name).core)
        return copies.filter {
            SongName.isSameRecording(query.name, on: query.album, as: $0.name, on: $0.album)
                && (!isGeneric || SongName.isSameRelease(query.album, $0.album))
        }
            .map { (song: $0, album: SongName.album($0.album)) }
            .sorted { choose($0.song, $0.album, over: $1.song, $1.album, album: album, duration: query.duration) }
            .map { $0.song }
    }

    /// The copy to show and rate, or nil when the user doesn't have the song: what
    /// `LibraryMatchFinder` chooses, for a library whose albums are already known
    func match(for query: SongQuery) -> LibrarySong? {
        return SongMatcher.ranked(copies(of: query), for: query).first
    }

    /// Which of two copies comes first: the one on the album the query names, then one the
    /// user rated themselves, then the nearest in length, then the one played most. The
    /// persistent ID settles a tie, so the order never depends on the library's.
    private static func choose(_ a: LibrarySong, _ albumA: String, over b: LibrarySong, _ albumB: String,
                               album: String, duration: Double?) -> Bool {
        let closeA = closeness(of: albumA, to: album), closeB = closeness(of: albumB, to: album)
        if closeA != closeB {
            return closeA < closeB
        }
        if a.isRatedByUser != b.isRatedByUser {
            return a.isRatedByUser
        }
        let lengthA = distance(a.duration, duration), lengthB = distance(b.duration, duration)
        if lengthA != lengthB {
            return lengthA < lengthB
        }
        if a.playedCount != b.playedCount {
            return a.playedCount > b.playedCount
        }
        return a.persistentID < b.persistentID
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
