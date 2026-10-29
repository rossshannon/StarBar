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
    /// The copy in Music, on the connection ratings are written through: a reference by
    /// persistent ID (`iTunesRadioStation.libraryTrack(for:)`), so a copy deleted since makes
    /// a write to it fail rather than land on another song
    let track: iTunesTrack
    /// The copy's stars and heart as they were read with it, a moment before the match was
    /// handed out, so showing a new match asks Music nothing more on the main thread. Nil in
    /// a match handed out again later, from memory or `knownMatch(for:)`: the rating can
    /// have changed by then, so anything shown later reads `track` again.
    var shown: Shown?

    struct Shown: Equatable {
        /// The user's own rating, 0 to 100, or nil when Music worked it out from the album's
        let rating: Int?
        let isFavorited: Bool

        /// What `track` says now. Two Apple Events, or more for an older Music.
        init(reading track: iTunesTrack) {
            self.init(rating: track.userRating, isFavorited: track.isFavorited)
        }

        init(rating: Int?, isFavorited: Bool) {
            self.rating = rating
            self.isFavorited = isFavorited
        }

        /// What was last read of the copy in the background, for when Music doesn't answer
        init(song: LibrarySong) {
            self.init(rating: song.isRatingComputed ? nil : song.rating, isFavorited: song.isFavorited)
        }
    }
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
    /// for its stars. Each property is an Apple Event, so only the album, which can rule a
    /// copy out (`SongMatcher.ranked(_:for:)`), and what would be shown (the rating and
    /// heart) are read unless `choosing`, when the length and plays that choose between
    /// copies are too, and the rating's kind only when there is a rating for it to describe.
    ///
    /// One property at a time, never the track's `properties` record, though the record is
    /// one event: it holds `location`, and measured 2026-10-29, every read of a track's
    /// `location`, alone or in the record, made Music announce a library change 2.8 s later
    /// and again 12 s after that. A library change sends StarBar to read the playing song's
    /// copy again, so the build that read the record read the library every 3 s for as long
    /// as the song played.
    func reading(_ track: iTunesTrack, choosing: Bool) -> LibrarySong? {
        // A read that failed gives an enumeration of no known kind, so the copy is left out
        guard track.mediaKind == .music else { return nil }
        var song = self
        song.album = track.album ?? ""
        song.rating = track.rating ?? 0
        song.isRatingComputed = song.rating > 0 && track.ratingKind == .computed
        song.isFavorited = track.isFavorited
        if choosing {
            // Scripting Bridge gives a number 0 when its Apple Event fails
            song.duration = track.duration.flatMap { $0 > 0 ? $0 : nil }
            song.playedCount = track.playedCount ?? 0
        }
        return song
    }

}

/// Answers "does the user have this Spotify song in Music?", once per song.
///
/// The matching is `SongMatcher`'s, over `MusicLibraryIndex`, which holds names only. The
/// copies it finds are read from Music again on the index's background connection
/// (`MusicLibraryIndex.readCopies`), each found by persistent ID and its name and artist
/// compared with the index's, because the index can be a library notification behind and a
/// rating written to the wrong song can't be undone, and what chooses between them and what
/// is shown read from each. Their albums leave out any copy that is a live or remixed
/// recording when the song playing isn't, or the other way round
/// (`SongMatcher.ranked(_:for:)`). The chosen copy's track is then a reference on the
/// station's own connection, which is the one that writes ratings, made without asking Music
/// anything: the copy was checked a moment before, and its stars and heart come with the
/// answer (`LibraryMatch.shown`), so nothing on the main thread waits on Music to show them.
/// Measured 2026-10-29, Music answering slowly took the stars 3.9 s to arrive where they
/// usually take 0.3 to 0.6 s, and the main thread had been held 2 s on reads it didn't answer.
///
/// Music that didn't answer is not taken for a song the user doesn't have. It is asked
/// again once, `retryDelay` later; failing that, nothing is remembered, so the next time
/// the song comes up Music is asked again.
///
/// Main thread only.
final class LibraryMatchFinder {

    static let shared = LibraryMatchFinder()

    /// The most copies of one song read from Music. Each copy is up to eight Apple Events, on
    /// the index's queue. The index holds no albums, ratings or lengths to choose by, so
    /// reading only some would leave the choice to their persistent IDs, and the copy on the
    /// album Spotify names, or the one the user rated, could be among those never read. So
    /// past this, only the copies whose titles mark every kind of recording Spotify's title and
    /// album do are read (`SongMatcher.titledAlike`: "One (Live)" of 13 copies of "One", for
    /// "One - Live" or for "One" on "Live 2003"), and when those are still too many, the song
    /// is no match. A copy titled plainly on a live album is then never read, though it may
    /// be the one on the album Spotify names.
    static let copiesRead = 12

    /// How long to wait before asking a Music that didn't answer again. Measured 2026-10-29,
    /// Music's first answer after seven idle minutes took over a second, and the next five
    /// came in 11 to 209 ms.
    static let retryDelay: TimeInterval = 2

    private let index: MusicLibraryIndex
    /// The chosen copy's track on the station's connection, or nil when Music isn't running
    /// or its library can't be found
    private let fetchTrack: (LibrarySong) -> iTunesTrack?
    private let clock: RatingReminderClock
    private let center: NotificationCenter

    /// The last answer, and which song it answered for
    private var answer: (identity: String, match: LibraryMatch?)?
    /// Music couldn't check `answer` when last asked, so it is shown but not given again:
    /// the next question about the song asks Music, or a song added since would stay "not in
    /// the library" until the next library change
    private var answerIsUnchecked = false
    /// The song being looked for, and everyone waiting to hear. An answer about any other
    /// song is dropped.
    private var asking: (identity: String, waiting: [(LibraryMatch?) -> Void])?
    /// Waiting to ask Music again
    private var retry: RatingReminderTimer?

    /// The parameters are for the tests
    init(index: MusicLibraryIndex = .shared,
         fetchTrack: @escaping (LibrarySong) -> iTunesTrack? = { iTunesRadioStation.shared.libraryTrack(for: $0) },
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
        if let answer = answer, answer.identity == identity, !index.needsRead, !answerIsUnchecked {
            return completion(answer.match)
        }
        retry?.invalidate()
        retry = nil
        asking = (identity, [completion])
        look(for: query, identity: identity, triesLeft: 1)
    }

    /// Whether the library has been read since StarBar started. The first read builds the
    /// matcher from nothing, which takes longer than any read after it.
    var hasReadLibrary: Bool {
        return index.hasRead
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

    /// The copy a match named has gone from the library, deleted in Music before the library
    /// notification came. The next question reads the library again, rather than hand back
    /// the copy that is gone.
    func copyIsGone() {
        index.markStale()
    }

    private func look(for query: SongQuery, identity: String, triesLeft: Int) {
        index.withMatcher { [weak self] matcher in
            guard let self = self, self.asking?.identity == identity else { return }
            guard let matcher = matcher else {
                // A library read that failed while Music runs says nothing about the song.
                // Measured 2026-10-29, the first read after a launch failed with -1701 in
                // 14 ms, the song it was for went unmatched to its end, and the next read,
                // 8 s later, found all 8,093 songs.
                guard self.index.isMusicRunning else { return self.finish(nil, for: identity) }
                return self.noAnswer(for: query, identity: identity, triesLeft: triesLeft)
            }
            let copies = matcher.copies(of: query)
            guard !copies.isEmpty else {
                os_log("%{public}s[%{public}ld], %{public}s: no library copy of %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album)
                return self.finish(nil, for: identity)
            }
            let reading: [LibrarySong]
            if copies.count <= LibraryMatchFinder.copiesRead {
                reading = copies
            } else {
                let marked = SongMatcher.titledAlike(copies, as: query)
                guard !marked.isEmpty, marked.count <= LibraryMatchFinder.copiesRead else {
                    os_log("%{public}s[%{public}ld], %{public}s: %{public}ld library copies of %{public}s, %{public}ld of them titled alike, more than the %{public}ld read; the one to choose could be among the rest, so no match", ((#file as NSString).lastPathComponent), #line, #function, copies.count, identity, marked.count, LibraryMatchFinder.copiesRead)
                    return self.finish(nil, for: identity)
                }
                os_log("%{public}s[%{public}ld], %{public}s: %{public}ld library copies of %{public}s; reading the %{public}ld titled alike", ((#file as NSString).lastPathComponent), #line, #function, copies.count, identity, marked.count)
                reading = marked
            }
            self.index.readCopies(reading, choosing: reading.count > 1) { [weak self] read in
                guard let self = self, self.asking?.identity == identity else { return }
                guard let read = read else {
                    return self.noAnswer(for: query, identity: identity, triesLeft: triesLeft)
                }
                let songs = read.compactMap { $0 }
                let ranked = SongMatcher.ranked(songs, for: query)
                for song in songs where !ranked.contains(song) {
                    os_log("%{public}s[%{public}ld], %{public}s: library song %{public}s, \u{201C}%{public}s\u{201D} on %{public}s, is a different recording from %{public}s, \u{201C}%{public}s\u{201D} on %{public}s, by its album", ((#file as NSString).lastPathComponent), #line, #function, song.persistentID, song.name, song.album, identity, query.name, query.album)
                }
                guard let song = ranked.first else {
                    os_log("%{public}s[%{public}ld], %{public}s: the index matched %{public}s to %{public}ld library tracks, none of them that recording and still there; no match", ((#file as NSString).lastPathComponent), #line, #function, identity, reading.count)
                    return self.finish(nil, for: identity)
                }
                guard let track = self.fetchTrack(song) else {
                    return self.noAnswer(for: query, identity: identity, triesLeft: triesLeft)
                }
                os_log("%{public}s[%{public}ld], %{public}s: %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s, is library song %{public}s, \u{201C}%{public}s\u{201D} by %{public}s on %{public}s (%{public}ld of %{public}ld copies read)", ((#file as NSString).lastPathComponent), #line, #function, identity, query.name, query.artist, query.album, song.persistentID, song.name, song.artist, song.album, ranked.count, reading.count)
                self.finish(LibraryMatch(identity: identity, query: query, song: song, track: track,
                                         shown: LibraryMatch.Shown(song: song)),
                            for: identity)
            }
        }
    }

    /// Music didn't answer: ask again a moment later, or give up without remembering
    /// anything, so the next time the song comes up Music is asked again
    private func noAnswer(for query: SongQuery, identity: String, triesLeft: Int) {
        // Music quit while it was being asked: nothing to wait for, and nothing on show can be
        // rated now
        guard index.isMusicRunning else { return finish(nil, for: identity) }
        guard triesLeft > 0 else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Music didn't answer about %{public}s again; not looking until it is asked about again", ((#file as NSString).lastPathComponent), #line, #function, identity)
            // Whatever was last known for this song stands
            return finish(knownMatch(for: identity), for: identity, remember: false)
        }
        os_log("%{public}s[%{public}ld], %{public}s: Music didn't answer about %{public}s; asking again in %{public}.0f s", ((#file as NSString).lastPathComponent), #line, #function, identity, LibraryMatchFinder.retryDelay)
        retry?.invalidate()
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
            answerIsUnchecked = false
        } else if answer?.identity == identity {
            answerIsUnchecked = true
        }
        waiting.forEach { $0(match) }
        center.post(name: .libraryMatchDidChange, object: self, userInfo: [SpotifyPlayer.identityKey: identity])
        // What was read is shown by now, and anything that asks later reads the track again
        if remember, var kept = match {
            kept.shown = nil
            answer = (identity, kept)
        }
    }

}
