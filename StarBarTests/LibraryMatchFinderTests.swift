//
//  LibraryMatchFinderTests.swift
//  StarBarTests
//
//  Finding the user's own Music copy of a Spotify song, with a fake library and fake
//  tracks. No Music and no Spotify.
//

import XCTest
@testable import StarBar

final class LibraryMatchFinderTests: XCTestCase {

    private let zombie = LibrarySong(persistentID: "00000000000000A1", name: "Zombie", artist: "The Cranberries",
                                     albumArtist: "", album: "No Need to Argue", duration: 306, rating: 80,
                                     isRatingComputed: false, playedCount: 12)
    private let linger = LibrarySong(persistentID: "00000000000000B2", name: "Linger", artist: "The Cranberries",
                                     albumArtist: "", album: "Everybody Else Is Doing It", duration: 274, rating: 60,
                                     isRatingComputed: false, playedCount: 3)

    /// The fake Music's tracks. The index reads only their names; the rest is read from the
    /// fake track a copy is fetched as, the way the finder reads it from Music.
    private var library: [LibrarySong] = []
    /// Persistent IDs of the tracks that are music videos
    private var musicVideos: Set<String> = []
    private var reads = 0
    private var fetched: [String] = []
    /// Whether each fetch was told there were copies to choose between
    private var choosing: [Bool] = []
    /// Persistent IDs the fake Music no longer has
    private var gone: Set<String> = []
    private var center: NotificationCenter!
    private var finder: LibraryMatchFinder!

    override func setUp() {
        super.setUp()
        library = [zombie, linger]
        musicVideos = []
        reads = 0
        fetched = []
        choosing = []
        gone = []
        center = NotificationCenter()
        let index = MusicLibraryIndex(readLibrary: { [unowned self] _ in
            DispatchQueue.main.sync { self.reads += 1 }
            return DispatchQueue.main.sync {
                self.library.map { LibrarySong(persistentID: $0.persistentID, name: $0.name, artist: $0.artist,
                                               albumArtist: $0.albumArtist) }
            }
        }, musicPID: { 501 })
        index.observeLibraryChanges(in: center)
        finder = LibraryMatchFinder(index: index, fetchCopy: { [unowned self] song, choosing in
            self.fetched.append(song.persistentID)
            self.choosing.append(choosing)
            guard !self.gone.contains(song.persistentID),
                  let music = self.library.first(where: { $0.persistentID == song.persistentID }) else { return nil }
            let track = FakeTrack(name: music.name, artist: music.artist, album: music.album,
                                  persistentID: music.persistentID, duration: music.duration ?? 0,
                                  rating: music.rating, ratingKind: music.isRatingComputed ? .computed : .user,
                                  mediaKind: self.musicVideos.contains(music.persistentID) ? .musicVideo : .music,
                                  playedCount: music.playedCount)
            return song.reading(track, choosing: choosing).map { (song: $0, track: track as iTunesTrack) }
        }, center: center)
    }

    private func spotify(_ name: String, by artist: String, on album: String = "",
                         id: String = "spotify:track:4uLU6hMCjMI75M1A2tKUQC", seconds: Int? = nil) -> SpotifyPlayInfo {
        return SpotifyPlayInfo(trackID: id, name: name, artist: artist, album: album, state: .playing,
                               duration: seconds.map { $0 * 1000 })
    }

    /// The answer `match(for:)` gives, waiting for the library read if there is one
    private func ask(_ info: SpotifyPlayInfo) -> LibraryMatch? {
        let answered = expectation(description: "answered")
        var result: LibraryMatch?
        finder.match(for: info) {
            result = $0
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        return result
    }

    // MARK: - What is looked for

    func testASongsQueryCarriesItsLengthInSeconds() {
        let query = spotify("Zombie", by: "The Cranberries", on: "No Need To Argue", seconds: 306).songQuery

        XCTAssertEqual(query, SongQuery(name: "Zombie", artist: "The Cranberries", album: "No Need To Argue", duration: 306))
    }

    func testALocalFileIsLookedFor() {
        // A file from the user's own disk is the likeliest of all to be in their library
        XCTAssertNotNil(spotify("Zombie", by: "The Cranberries", id: "spotify:local:Cranberries:Argue:Zombie:306").songQuery)
    }

    func testAnEpisodeOrAnAdIsNot() {
        XCTAssertNil(spotify("Zombie", by: "The Cranberries", id: "spotify:episode:0Q86acNRm6V9GYx55SXKwf").songQuery)
        XCTAssertNil(spotify("Zombie", by: "The Cranberries", id: "spotify:ad:000000012c603a6600000020316a17a1").songQuery)
    }

    func testANameOrArtistMissingMeansNothingToLookFor() {
        XCTAssertNil(spotify("", by: "The Cranberries").songQuery)
        XCTAssertNil(spotify("Zombie", by: "").songQuery)
    }

    // MARK: - Answers

    func testASongTheUserHasIsFoundAndFetchedByItsPersistentID() throws {
        let match = try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries", seconds: 306)))

        XCTAssertEqual(match.song.persistentID, zombie.persistentID)
        XCTAssertEqual(match.song.album, "No Need to Argue", "read from Music for the log")
        XCTAssertEqual(match.identity, "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual((match.track as? FakeTrack)?.persistentID, zombie.persistentID)
        XCTAssertEqual(fetched, [zombie.persistentID])
    }

    func testASongTheUserDoesNotHaveIsNotFound() {
        XCTAssertNil(ask(spotify("Dreams", by: "The Cranberries")))
        XCTAssertEqual(fetched, [], "nothing to fetch")
    }

    func testAnEpisodeIsAnsweredAtOnceWithoutReadingTheLibrary() {
        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries", id: "spotify:episode:0Q86acNRm6V9GYx55SXKwf")))
        XCTAssertEqual(reads, 0)
    }

    func testATrackThatIsGoneOrChangedIsNoMatch() {
        // The index can be a notification behind; the fetch is what checks
        gone = [zombie.persistentID]

        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
    }

    func testTheSameSongIsAnsweredFromMemory() {
        _ = ask(spotify("Zombie", by: "The Cranberries"))
        _ = ask(spotify("Zombie", by: "The Cranberries"))

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(fetched.count, 1, "and Music isn't asked for the track again")
        XCTAssertNotNil(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
        XCTAssertNil(finder.knownMatch(for: "spotify:track:somethingElse"))
    }

    func testALibraryChangeMeansAskingAgain() {
        // A song added in Music while it plays in Spotify: the next ask finds it
        XCTAssertNil(ask(spotify("Dreams", by: "The Cranberries")))
        library.append(LibrarySong(persistentID: "00000000000000C3", name: "Dreams", artist: "The Cranberries",
                                   albumArtist: ""))
        center.post(name: .ITLibraryDidChange, object: nil)

        XCTAssertEqual(ask(spotify("Dreams", by: "The Cranberries"))?.song.persistentID, "00000000000000C3")
        XCTAssertEqual(reads, 2)
    }

    func testTheLastAnswerIsKeptUntilANewOneReplacesIt() {
        // So the strip doesn't drop the stars while the library is read again after a rating
        _ = ask(spotify("Zombie", by: "The Cranberries"))
        center.post(name: .ITLibraryDidChange, object: nil)

        XCTAssertEqual(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.song.persistentID, zombie.persistentID)
    }

    func testEachNewAnswerIsPostedForTheStrip() {
        var posted: [String] = []
        let observer = center.addObserver(forName: .libraryMatchDidChange, object: finder, queue: nil) {
            posted.append($0.userInfo?[SpotifyPlayer.identityKey] as? String ?? "?")
        }
        defer { center.removeObserver(observer) }

        _ = ask(spotify("Zombie", by: "The Cranberries"))
        _ = ask(spotify("Zombie", by: "The Cranberries"))

        XCTAssertEqual(posted, ["spotify:track:4uLU6hMCjMI75M1A2tKUQC"], "once: the second answer came from memory")
    }

    func testTwoAsksAboutOneSongBothHearBack() {
        // The menu bar and anything else asking about the song now playing
        let both = expectation(description: "both answered")
        both.expectedFulfillmentCount = 2
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { _ in both.fulfill() }
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { _ in both.fulfill() }

        wait(for: [both], timeout: 5)
    }

    // MARK: - Choosing between copies

    /// Another copy of Zombie, on a best-of
    private let zombieOnStars = LibrarySong(persistentID: "00000000000000D4", name: "Zombie", artist: "The Cranberries",
                                            albumArtist: "", album: "Stars: The Best of 1992-2002", duration: 306,
                                            rating: 0, isRatingComputed: false, playedCount: 40)

    func testOneCopyReadsOnlyWhatShowsIt() {
        _ = ask(spotify("Zombie", by: "The Cranberries"))

        XCTAssertEqual(choosing, [false], "no length, rating or plays: there is nothing to choose between")
    }

    func testTheAlbumSpotifyNamesChoosesTheCopy() throws {
        // The index has no albums, so this is only right if the finder read them. The best-of
        // copy sorts after the album copy by persistent ID, so the index's order alone would
        // pick the wrong one.
        library = [zombie, zombieOnStars]

        let match = try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries", on: "Stars: The Best Of 1992-2002")))

        XCTAssertEqual(match.song.persistentID, zombieOnStars.persistentID)
        XCTAssertEqual((match.track as? FakeTrack)?.persistentID, zombieOnStars.persistentID, "the track goes with the song")
        XCTAssertEqual(choosing, [true, true])
    }

    func testARatingTheUserChoseChoosesTheCopyWhenTheAlbumDoesNot() throws {
        // Sorts before the rated copy by persistent ID, so only the rating read from Music
        // puts the rated one first
        let unrated = LibrarySong(persistentID: "0000000000000001", name: "Zombie", artist: "The Cranberries",
                                  albumArtist: "", album: "Stars: The Best of 1992-2002", duration: 306,
                                  rating: 0, isRatingComputed: false, playedCount: 40)
        library = [unrated, zombie]

        let match = try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries", on: "Greatest Hits")))

        XCTAssertEqual(match.song.persistentID, zombie.persistentID, "rated 4 stars; the best-of copy has no rating")
        XCTAssertEqual(match.song.rating, 80)
    }

    func testAMusicVideoOfTheSongIsNotACopy() throws {
        // The index keeps every kind of track; a video has no place for the song's stars
        let video = LibrarySong(persistentID: "00000000000000A0", name: "Zombie", artist: "The Cranberries",
                                albumArtist: "", album: "", duration: 306, rating: 100, isRatingComputed: false,
                                playedCount: 99)
        library = [video, zombie]
        musicVideos = [video.persistentID]

        XCTAssertEqual(ask(spotify("Zombie", by: "The Cranberries"))?.song.persistentID, zombie.persistentID)

        library = [video]
        center.post(name: .ITLibraryDidChange, object: nil)
        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries", id: "spotify:track:again")), "a video alone is no match")
    }

    func testACopyThatIsGoneLeavesTheOthers() {
        library = [zombie, zombieOnStars]
        gone = [zombieOnStars.persistentID]

        XCTAssertEqual(ask(spotify("Zombie", by: "The Cranberries", on: "Stars: The Best Of 1992-2002"))?.song.persistentID,
                       zombie.persistentID)
    }

    func testOnlyTheFirstFewCopiesAreRead() {
        // Each copy is Apple Events on the main thread
        library = (0..<10).map {
            LibrarySong(persistentID: String(format: "%016X", $0), name: "Zombie", artist: "The Cranberries", albumArtist: "")
        }

        XCTAssertNotNil(ask(spotify("Zombie", by: "The Cranberries")))
        XCTAssertEqual(fetched.count, LibraryMatchFinder.copiesRead)
    }

    // MARK: - Reading a copy

    func testReadingACopyToChooseBetweenTakesWhatChooses() throws {
        let track = FakeTrack(name: "Zombie", artist: "The Cranberries", album: "No Need to Argue", duration: 306.5,
                              rating: 60, ratingKind: .computed, playedCount: 7)
        let song = LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries", albumArtist: "")

        XCTAssertEqual(song.reading(track, choosing: true),
                       LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries", albumArtist: "",
                                   album: "No Need to Argue", duration: 306.5, rating: 60, isRatingComputed: true,
                                   playedCount: 7))
        XCTAssertEqual(song.reading(track, choosing: false),
                       LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries", albumArtist: "",
                                   album: "No Need to Argue"))
    }

    func testALengthOfNothingIsNoLength() {
        // What a failed Apple Event gives for a number
        let track = FakeTrack(duration: 0)
        let song = LibrarySong(persistentID: "A1", name: "Song", artist: "Artist", albumArtist: "")

        XCTAssertNil(song.reading(track, choosing: true)?.duration)
    }

    func testATrackThatIsNotASongIsNoCopy() {
        let song = LibrarySong(persistentID: "A1", name: "Song", artist: "Artist", albumArtist: "")

        XCTAssertNil(song.reading(FakeTrack(mediaKind: .musicVideo), choosing: false))
        XCTAssertNil(song.reading(FakeTrack(mediaKind: .podcast), choosing: true))
    }

    // MARK: - Overtaken

    func testAQuestionOvertakenByAnotherIsNeverAnswered() {
        // Spotify moved on while the library was being read: only the song now playing gets
        // an answer, so nothing can show the old song's stars for the new one
        var answers: [String?] = []
        let answered = expectation(description: "answered")
        finder.match(for: spotify("Zombie", by: "The Cranberries", id: "spotify:track:first")) {
            answers.append($0?.song.name)
        }
        finder.match(for: spotify("Linger", by: "The Cranberries", id: "spotify:track:second")) {
            answers.append($0?.song.name)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)

        XCTAssertEqual(answers, ["Linger"])
    }

}
