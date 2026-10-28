//
//  LibraryMatchFinder.swift
//  StarBar
//
//  Finding the user's own Music copy of the song Spotify is playing.
//

import Foundation
import os

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

/// Answers "does the user have this Spotify song in Music?", once per song.
///
/// The matching is `SongMatcher`'s, over `MusicLibraryIndex`. The track it finds is fetched
/// again by persistent ID through the station's own connection to Music, and its name and
/// artist compared with the index's, because the index can be a library notification behind
/// and a rating written to the wrong song can't be undone.
///
/// Main thread only.
final class LibraryMatchFinder {

    static let shared = LibraryMatchFinder()

    private let index: MusicLibraryIndex
    private let fetchTrack: (LibrarySong) -> iTunesTrack?

    /// The last answer, and which song it answered for
    private var answer: (identity: String, match: LibraryMatch?)?
    /// Counts questions, so the answer to one that a newer one overtook is dropped
    private var questions = 0

    /// The parameters are for the tests
    init(index: MusicLibraryIndex = .shared,
         fetchTrack: @escaping (LibrarySong) -> iTunesTrack? = { iTunesRadioStation.shared.libraryTrack(for: $0) }) {
        self.index = index
        self.fetchTrack = fetchTrack
    }

    /// The user's own copy of the Spotify song `info` describes, or nil when they have none,
    /// it isn't a song, or Music isn't running.
    ///
    /// `completion` runs on the main thread: before this returns when the answer is already
    /// known, later when the library has to be read first, and never when a question about
    /// another song overtakes this one, since nobody is showing this one any more.
    func match(for info: SpotifyPlayInfo, completion: @escaping (LibraryMatch?) -> Void) {
        guard let identity = info.trackID, let query = info.songQuery else { return completion(nil) }
        if let answer = answer, answer.identity == identity, !index.needsRead {
            return completion(answer.match)
        }
        questions += 1
        let question = questions
        index.withMatcher { [weak self] matcher in
            guard let self = self, question == self.questions else { return }
            let match = self.find(query, identity: identity, in: matcher)
            self.answer = (identity, match)
            completion(match)
        }
    }

    /// The answer already given for this song, asking Music nothing. Nil when there isn't
    /// one, or when the library has changed since it was given.
    func knownMatch(for identity: String?) -> LibraryMatch? {
        guard let identity = identity, let answer = answer, answer.identity == identity,
              !index.needsRead else { return nil }
        return answer.match
    }

    private func find(_ query: SongQuery, identity: String, in matcher: SongMatcher?) -> LibraryMatch? {
        guard let matcher = matcher else { return nil }
        let copies = matcher.copies(of: query)
        guard let song = copies.first else {
            os_log("%{public}s[%{public}ld], %{public}s: no library copy of %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album)
            return nil
        }
        guard let track = fetchTrack(song) else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: the index matched %{public}s to library song %{public}s, which is gone or has changed; no match", ((#file as NSString).lastPathComponent), #line, #function, identity, song.persistentID)
            return nil
        }
        os_log("%{public}s[%{public}ld], %{public}s: %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s, is library song %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s (%{public}ld copies)", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album, song.persistentID, song.name, song.artist, song.album, copies.count)
        return LibraryMatch(identity: identity, query: query, song: song, track: track)
    }

}
