//
//  LibraryMatchFinder.swift
//  StarBar
//
//  Finding the user's own Music copy of the song Spotify is playing.
//

import Foundation
import os

extension Notification.Name {
    /// `LibraryMatchFinder` has an answer for a song. `userInfo[SpotifyPlayer.identityKey]`
    /// is the song's Track ID. Posted on the main thread.
    static let libraryMatchDidChange = Notification.Name("StarBarLibraryMatchDidChange")
}

/// The user's own Music copy of a song another player is playing: what its stars show, and
/// where a rating chosen for it goes.
struct LibraryMatch {
    /// The other player's name for the song, such as a Spotify Track ID
    let identity: String
    /// The song as the other player named it
    let query: SongQuery
    /// The library song, as `MusicLibraryIndex` had it when the match was made
    let song: LibrarySong
    /// The live Music track, found again by persistent ID and checked to still be that song
    let track: iTunesTrack
}

extension SpotifyPlayInfo {

    /// What to look for in the user's library. Songs and local files only: an episode is in
    /// no music library, and an ad has no name worth matching.
    var songQuery: SongQuery? {
        guard content == .track || content == .local,
              let name = name, !name.isEmpty,
              let artist = artist, !artist.isEmpty else { return nil }
        return SongQuery(name: name, artist: artist, album: album ?? "",
                         duration: duration.map { Double($0) / 1000 })
    }

}

extension LibrarySong {

    /// This song with what Music says now about its live track, or nil when that track isn't
    /// a song: the index holds every kind of track, and a music video of the song is no place
    /// for its stars. Each property is an Apple Event, so the album alone is read unless
    /// `choosing`, when the length, rating and plays that choose between copies are too.
    func reading(_ track: iTunesTrack, choosing: Bool) -> LibrarySong? {
        // A read that failed gives an enumeration of no known kind, so the copy is left out
        guard track.mediaKind == .music else { return nil }
        var song = self
        song.album = track.album ?? ""
        if choosing {
            // Scripting Bridge gives a number 0 when its Apple Event fails
            song.duration = track.duration.flatMap { $0 > 0 ? $0 : nil }
            song.rating = track.rating ?? 0
            song.isRatingComputed = track.ratingKind == .computed
            song.playedCount = track.playedCount ?? 0
        }
        return song
    }

}

/// Answers "does the user have this Spotify song in Music?", once per song.
///
/// The matching is `SongMatcher`'s, over `MusicLibraryIndex`, which holds names only. Each
/// copy it finds is fetched again by persistent ID through the station's own connection to
/// Music, its name and artist compared with the index's, because the index can be a library
/// notification behind and a rating written to the wrong song can't be undone, and what
/// chooses between copies read from it.
///
/// Main thread only.
final class LibraryMatchFinder {

    static let shared = LibraryMatchFinder()

    /// The most copies of one song read from Music. Each is about eight Apple Events on the
    /// main thread; one song held more often than this is rare, and the copies past it are
    /// never chosen.
    static let copiesRead = 6

    /// A library song's live track, with `LibrarySong.reading(_:choosing:)` applied
    typealias FetchedCopy = (song: LibrarySong, track: iTunesTrack)

    private let index: MusicLibraryIndex
    private let fetchCopy: (LibrarySong, Bool) -> FetchedCopy?
    private let center: NotificationCenter

    /// The last answer, and which song it answered for
    private var answer: (identity: String, match: LibraryMatch?)?
    /// The song last asked about, so answers about one asked before it are dropped
    private var asking: String?

    /// The parameters are for the tests. `fetchCopy` is handed whether there are copies to
    /// choose between.
    init(index: MusicLibraryIndex = .shared,
         fetchCopy: @escaping (LibrarySong, Bool) -> FetchedCopy? = LibraryMatchFinder.fetchLiveCopy,
         center: NotificationCenter = .default) {
        self.index = index
        self.fetchCopy = fetchCopy
        self.center = center
    }

    /// The song's track in Music, read under the short timeout, or nil when it is gone, has
    /// changed or isn't a song
    static func fetchLiveCopy(_ song: LibrarySong, choosing: Bool) -> FetchedCopy? {
        return MenuBarRatingControl.withShortTimeout { _ -> FetchedCopy? in
            guard let track = iTunesRadioStation.shared.libraryTrack(for: song) else { return nil }
            guard let read = song.reading(track, choosing: choosing) else {
                os_log("%{public}s[%{public}ld], %{public}s: library track %{public}s, \u{201C}%{public}s\u{201D} by %{public}s, isn't a song", ((#file as NSString).lastPathComponent), #line, #function, song.persistentID, song.name, song.artist)
                return nil
            }
            return (song: read, track: track)
        } ?? nil
    }

    /// The user's own copy of the Spotify song `info` describes, or nil when they have none,
    /// it isn't a song, or Music isn't running.
    ///
    /// `completion` runs on the main thread: before this returns when the answer is already
    /// known, later when the library has to be read first, and never when a question about
    /// another song overtakes this one, since nobody is showing this one any more. Each new
    /// answer is also posted as `.libraryMatchDidChange`, for the strip.
    func match(for info: SpotifyPlayInfo, completion: @escaping (LibraryMatch?) -> Void) {
        guard let identity = info.trackID, let query = info.songQuery else { return completion(nil) }
        if let answer = answer, answer.identity == identity, !index.needsRead {
            return completion(answer.match)
        }
        asking = identity
        index.withMatcher { [weak self] matcher in
            guard let self = self, self.asking == identity else { return }
            let match = self.find(query, identity: identity, in: matcher)
            self.answer = (identity, match)
            completion(match)
            self.center.post(name: .libraryMatchDidChange, object: self, userInfo: [SpotifyPlayer.identityKey: identity])
        }
    }

    /// The last answer given for this song, asking Music nothing, or nil when there isn't
    /// one. Kept after a library change until a new answer replaces it: the copy it names was
    /// fetched by persistent ID and is still the right one to show unless the change removed
    /// it, and dropping it in the meantime would flicker the strip from stars to "Spotify"
    /// and back after every rating.
    func knownMatch(for identity: String?) -> LibraryMatch? {
        guard let identity = identity, let answer = answer, answer.identity == identity else { return nil }
        return answer.match
    }

    private func find(_ query: SongQuery, identity: String, in matcher: SongMatcher?) -> LibraryMatch? {
        guard let matcher = matcher else { return nil }
        let copies = matcher.copies(of: query)
        guard !copies.isEmpty else {
            os_log("%{public}s[%{public}ld], %{public}s: no library copy of %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album)
            return nil
        }
        if copies.count > LibraryMatchFinder.copiesRead {
            os_log("%{public}s[%{public}ld], %{public}s: %{public}ld library copies of %{public}s; reading the first %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, copies.count, identity, LibraryMatchFinder.copiesRead)
        }
        let fetched = copies.prefix(LibraryMatchFinder.copiesRead).compactMap { fetchCopy($0, copies.count > 1) }
        let ranked = SongMatcher.ranked(fetched.map { $0.song }, for: query)
        guard let song = ranked.first, let track = fetched.first(where: { $0.song.persistentID == song.persistentID })?.track else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: the index matched %{public}s to %{public}ld library tracks, none of them a song still there; no match", ((#file as NSString).lastPathComponent), #line, #function, identity, copies.count)
            return nil
        }
        os_log("%{public}s[%{public}ld], %{public}s: %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s, is library song %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s (%{public}ld of %{public}ld copies read)", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album, song.persistentID, song.name, song.artist, song.album, fetched.count, copies.count)
        return LibraryMatch(identity: identity, query: query, song: song, track: track)
    }

}
