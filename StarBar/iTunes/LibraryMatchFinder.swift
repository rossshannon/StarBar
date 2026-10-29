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

/// What looking up a library song's track in Music came to
enum LibraryTrackLookup {
    case found(iTunesTrack)
    /// Gone from the library, or no longer the song the index had
    case gone
    /// Music isn't running or didn't answer in time, which says nothing about the song
    case unanswered
}

/// Answers "does the user have this Spotify song in Music?", once per song.
///
/// The matching is `SongMatcher`'s, over `MusicLibraryIndex`, which holds names only. The
/// copies it finds are read from Music again on the index's background connection
/// (`MusicLibraryIndex.readCopies`), each found by persistent ID and its name and artist
/// compared with the index's, because the index can be a library notification behind and a
/// rating written to the wrong song can't be undone, and what chooses between them read
/// from each. The chosen copy's track is then fetched through the station's own connection,
/// which is the one that writes ratings.
///
/// Music that didn't answer is not taken for a song the user doesn't have. It is asked
/// again once, `retryDelay` later; failing that, nothing is remembered, so the next time
/// the song comes up Music is asked again.
///
/// Main thread only.
final class LibraryMatchFinder {

    static let shared = LibraryMatchFinder()

    /// The most copies of one song read from Music. Each is about eight Apple Events; one
    /// song held more often than this is rare, and the copies past it are never chosen.
    static let copiesRead = 6

    /// How long to wait before asking a Music that didn't answer again. Measured 2026-10-29,
    /// Music's first answer after seven idle minutes took over a second, and the next five
    /// came in 11 to 209 ms.
    static let retryDelay: TimeInterval = 2

    private let index: MusicLibraryIndex
    private let fetchTrack: (LibrarySong) -> LibraryTrackLookup
    private let clock: RatingReminderClock
    private let center: NotificationCenter

    /// The last answer, and which song it answered for
    private var answer: (identity: String, match: LibraryMatch?)?
    /// The song being looked for, and everyone waiting to hear. An answer about any other
    /// song is dropped.
    private var asking: (identity: String, waiting: [(LibraryMatch?) -> Void])?
    /// Waiting to ask Music again
    private var retry: RatingReminderTimer?

    /// The parameters are for the tests
    init(index: MusicLibraryIndex = .shared,
         fetchTrack: @escaping (LibrarySong) -> LibraryTrackLookup = { iTunesRadioStation.shared.libraryTrack(for: $0) },
         clock: RatingReminderClock = RunLoopClock(),
         center: NotificationCenter = .default) {
        self.index = index
        self.fetchTrack = fetchTrack
        self.clock = clock
        self.center = center
    }

    /// The user's own copy of the Spotify song `info` describes, or nil when they have none,
    /// it isn't a song, or Music isn't running.
    ///
    /// `completion` runs on the main thread: before this returns when the answer is already
    /// known, later when Music has to be read first, and never when a question about another
    /// song overtakes this one, since nobody is showing this one any more. Asking again about
    /// the song already being looked for waits for the same answer. Each new answer is also
    /// posted as `.libraryMatchDidChange`, for the strip.
    func match(for info: SpotifyPlayInfo, completion: @escaping (LibraryMatch?) -> Void) {
        guard let identity = info.trackID, let query = info.songQuery else { return completion(nil) }
        if asking?.identity == identity {
            asking?.waiting.append(completion)
            return
        }
        if let answer = answer, answer.identity == identity, !index.needsRead {
            return completion(answer.match)
        }
        retry?.invalidate()
        retry = nil
        asking = (identity, [completion])
        look(for: query, identity: identity, triesLeft: 1)
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

    private func look(for query: SongQuery, identity: String, triesLeft: Int) {
        index.withMatcher { [weak self] matcher in
            guard let self = self, self.asking?.identity == identity else { return }
            guard let matcher = matcher else { return self.finish(nil, for: identity) }
            let copies = matcher.copies(of: query)
            guard !copies.isEmpty else {
                os_log("%{public}s[%{public}ld], %{public}s: no library copy of %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album)
                return self.finish(nil, for: identity)
            }
            if copies.count > LibraryMatchFinder.copiesRead {
                os_log("%{public}s[%{public}ld], %{public}s: %{public}ld library copies of %{public}s; reading the first %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, copies.count, identity, LibraryMatchFinder.copiesRead)
            }
            let reading = Array(copies.prefix(LibraryMatchFinder.copiesRead))
            self.index.readCopies(reading, choosing: copies.count > 1) { [weak self] read in
                guard let self = self, self.asking?.identity == identity else { return }
                guard let read = read else {
                    return self.noAnswer(for: query, identity: identity, triesLeft: triesLeft)
                }
                let ranked = SongMatcher.ranked(read.compactMap { $0 }, for: query)
                guard let song = ranked.first else {
                    os_log(.error, "%{public}s[%{public}ld], %{public}s: the index matched %{public}s to %{public}ld library tracks, none of them a song still there; no match", ((#file as NSString).lastPathComponent), #line, #function, identity, copies.count)
                    return self.finish(nil, for: identity)
                }
                switch self.fetchTrack(song) {
                case .found(let track):
                    os_log("%{public}s[%{public}ld], %{public}s: %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s, is library song %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s (%{public}ld of %{public}ld copies read)", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album, song.persistentID, song.name, song.artist, song.album, ranked.count, copies.count)
                    self.finish(LibraryMatch(identity: identity, query: query, song: song, track: track), for: identity)
                case .gone:
                    // Changed in the moment between the two reads
                    self.finish(nil, for: identity)
                case .unanswered:
                    self.noAnswer(for: query, identity: identity, triesLeft: triesLeft)
                }
            }
        }
    }

    /// Music didn't answer: ask again a moment later, or give up without remembering
    /// anything, so the next time the song comes up Music is asked again
    private func noAnswer(for query: SongQuery, identity: String, triesLeft: Int) {
        guard triesLeft > 0 else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Music didn't answer about %{public}s again; not looking until it is asked about again", ((#file as NSString).lastPathComponent), #line, #function, identity)
            // Whatever was last known for this song stands
            return finish(knownMatch(for: identity), for: identity, remember: false)
        }
        os_log("%{public}s[%{public}ld], %{public}s: Music didn't answer about %{public}s; asking again in %{public}.0f s", ((#file as NSString).lastPathComponent), #line, #function, identity, LibraryMatchFinder.retryDelay)
        retry = clock.schedule(after: LibraryMatchFinder.retryDelay, repeats: false) { [weak self] in
            guard let self = self, self.asking?.identity == identity else { return }
            self.retry = nil
            self.look(for: query, identity: identity, triesLeft: triesLeft - 1)
        }
    }

    private func finish(_ match: LibraryMatch?, for identity: String, remember: Bool = true) {
        let waiting = asking?.waiting ?? []
        asking = nil
        if remember {
            answer = (identity, match)
        }
        waiting.forEach { $0(match) }
        center.post(name: .libraryMatchDidChange, object: self, userInfo: [SpotifyPlayer.identityKey: identity])
    }

}
