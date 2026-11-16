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
/// its own: "Sweet Harmony" is 4:22 on the single and 15:18 on the album. The exception is a
/// copy whose title is the query's without a part of its name at the end, which has to be on
/// an album of the same name and at the same length (`ranked(_:for:)`). Only a title that
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

    /// The names a track's `Worked` comes from, and what a matcher built again finds it by
    private struct Names: Hashable {
        let name: String
        let artist: String
        let albumArtist: String

        init(_ song: LibrarySong) {
            name = song.name
            artist = song.artist
            albumArtist = song.albumArtist
        }
    }

    /// What `SongName` makes of a track's names
    private struct Worked {
        let core: String
        /// The track's own artists and its album artist, never a guest
        /// (`SongName.credited(_:)`'s `artists`)
        let artists: Set<String>
        /// Everyone the track credits, guests and anyone after the lead too
        /// (`SongName.credited(_:)`), for a "(with ...)" to be checked against
        let credits: Set<String>
        /// Who its title credits with "with" (`SongName.Title.withNames`)
        let withNames: Set<String>
        let versions: Set<String>
        /// The title without a part of its name at the end (`SongName.Title.shortCore`)
        let shortCore: String?

        /// `credited` is `SongName.credited(_:)`, or a lookup of what it has already answered
        init(_ names: Names, credited: (String) -> (artists: Set<String>, everyone: Set<String>)) {
            let title = SongName.title(names.name)
            var (artists, everyone) = credited(names.artist)
            // Most tracks name the same artist twice, and this runs for every track in the
            // library: about 420 ms of the first read measured on 2026-10-29
            if !names.albumArtist.isEmpty, names.albumArtist != names.artist {
                let albumArtist = credited(names.albumArtist)
                artists.formUnion(albumArtist.artists)
                everyone.formUnion(albumArtist.everyone)
            }
            core = title.core
            self.artists = artists
            credits = everyone.union(title.featured)
            withNames = Set(title.withNames)
            versions = title.versions
            shortCore = title.shortCore
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
        // Each credit is worked out once however many tracks carry it, since most artists
        // have many. `SongName.credited(_:)` is pure, so the answer can't differ.
        var credits: [String: (artists: Set<String>, everyone: Set<String>)] = [:]
        func credited(_ raw: String) -> (artists: Set<String>, everyone: Set<String>) {
            if let known = credits[raw] {
                return known
            }
            let found = SongName.credited(raw)
            credits[raw] = found
            return found
        }
        for song in library {
            let names = Names(song)
            let work = worked[names] ?? previous?.worked[names] ?? Worked(names, credited: credited)
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
    ///
    /// When the user has no copy titled as the query is, a copy titled with the query's short
    /// title can be one (`SongName.Title.shortCore`): their "I Wanna Dance With Somebody" for
    /// Apple's "I Wanna Dance with Somebody (Who Loves Me)". Only in that direction, only for
    /// a query with a length, and only a copy whose own title ends in no such part, so
    /// "Mantis (Battle)" never finds "Mantis (Explore)". Such a copy is a candidate only:
    /// `ranked(_:for:)` keeps it on an album of the same name at the same length.
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
        func found(_ entries: [Entry]) -> [LibrarySong] {
            return entries
                .filter {
                    $0.work.artists.contains(artist)
                        && SongName.kinds(of: $0.work.versions).isSubset(of: kinds)
                        && withNames.isSubset(of: $0.work.credits)
                        && $0.work.withNames.isSubset(of: credits)
                }
                .map { $0.song }
        }
        let byFullTitle = found(byTitle[title.core] ?? [])
        guard byFullTitle.isEmpty, let short = title.shortCore, query.duration != nil else { return byFullTitle }
        return found((byTitle[short] ?? []).filter { $0.work.shortCore == nil })
    }

    /// The copies whose own titles mark every kind of recording the query is, by its title and
    /// album together: "Clocks (Live)" for "Clocks - Live", or for plain "Clocks" on "Live
    /// 2003", but not plain "Clocks", which is only a candidate in case its album says it is
    /// live. When none does, those whose titles mark some of the kinds, and at least what
    /// the query's title marks: "Song (Acoustic)" for "Song - Acoustic" on "MTV Unplugged",
    /// which is acoustic and live. For when there are too many copies to read them all, since
    /// only reading a copy tells its album.
    static func titledAlike(_ copies: [LibrarySong], as query: SongQuery) -> [LibrarySong] {
        let kinds = SongName.versions(of: query.name, on: query.album)
        let titled = copies.map { (song: $0, kinds: SongName.kinds(of: SongName.title($0.name).versions)) }
        let alike = titled.filter { $0.kinds == kinds }.map { $0.song }
        guard alike.isEmpty else { return alike }
        let marked = SongName.kinds(of: SongName.title(query.name).versions)
        return titled.filter { !$0.kinds.isEmpty && marked.isSubset(of: $0.kinds) && $0.kinds.isSubset(of: kinds) }.map { $0.song }
    }

    /// Copies from `copies(of:)` whose album, length, rating and plays have since been read,
    /// the one to show and rate first, and without any whose album makes it a different
    /// recording from the song `query` names: one on "Live at the Fillmore West" when Spotify
    /// is playing the studio song, or the other way round, or another night's live recording
    /// (`SongName.isSameRecording`), or an "Intro" on another album.
    ///
    /// A copy found by the short title (`copies(of:)`, `isFoundByShortTitle(_:for:)`) is kept
    /// only on an album of the same name (`SongName.isSameAlbumName`), not a soundtrack, and
    /// within `shortTitleLengthGap` of the query's length; a copy with either length unknown
    /// is left out. **This is the one place a length rules a copy out.** Measured on
    /// 2026-11-16 across a 7,996-song library, 19 pairs of songs had one title that was the
    /// other with such a part on the end, among them soundtrack cues such as "The Last of Us"
    /// and "The Last of Us (Never Again)", a live recording, "(london performance)", and a
    /// cover. The gate leaves 3, each pair 0.1 s apart or less on one album: one song under
    /// two titles each, as far as the lengths say.
    ///
    /// The album's name has to be the same, not only the release: a deluxe edition's bonus
    /// stems and early takes are the master's length to within a second, and only the
    /// edition's name tells them from it (the review of 2026-11-16). Where the user's master is
    /// on the deluxe edition too, only the words of the part do (`SongName.isPartOfTheName`).
    /// And never on a soundtrack, where one cue can come in versions of one length: "Good
    /// Riddance" and "Good Riddance (Eurydice Solo)" on *Hades* are two recordings, 2:58 and
    /// 2:57.
    ///
    /// Every copy here was found the same way (`copies(of:)` never mixes full-title and
    /// short-title copies), so the order below doesn't have to put one kind first.
    static func ranked(_ copies: [LibrarySong], for query: SongQuery) -> [LibrarySong] {
        let album = SongName.album(query.album)
        let isGeneric = SongName.isGenericTitle(SongName.title(query.name).core)
        return copies.filter {
            SongName.isSameRecording(query.name, on: query.album, as: $0.name, on: $0.album)
                && (!isGeneric || SongName.isSameRelease(query.name, on: query.album, as: $0.name, on: $0.album))
                && (!isFoundByShortTitle($0, for: query) || isSameByShortTitle($0, as: query))
        }
            .map { (song: $0, album: SongName.album($0.album)) }
            .sorted { choose($0.song, $0.album, over: $1.song, $1.album, album: album, duration: query.duration) }
            .map { $0.song }
    }

    /// The most a copy found by its short title can differ in length from the query, in
    /// seconds. "I Wanna Dance With Somebody" was 289.4 s in the user's library and 291.4 s
    /// in Apple's catalog, measured 2026-11-16.
    static let shortTitleLengthGap: Double = 3

    /// Whether `copy` is one of the query's copies only by the query's short title
    /// (`copies(of:)`), so `ranked(_:for:)` needs its length to keep it
    static func isFoundByShortTitle(_ copy: LibrarySong, for query: SongQuery) -> Bool {
        guard let short = SongName.title(query.name).shortCore else { return false }
        return SongName.title(copy.name).core == short
    }

    /// A copy found by the short title on an album of the query's name that isn't a
    /// soundtrack, within `shortTitleLengthGap`
    private static func isSameByShortTitle(_ copy: LibrarySong, as query: SongQuery) -> Bool {
        guard let length = copy.duration, let wanted = query.duration else { return false }
        return abs(length - wanted) <= shortTitleLengthGap
            && SongName.isSameAlbumName(query.album, copy.album)
            && !SongName.isSoundtrackAlbum(query.album)
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
