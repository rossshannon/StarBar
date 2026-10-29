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

    /// The fake Music's tracks. The index reads only their names; the rest is read from a
    /// fake track for each copy, the way the index reads its copies from Music.
    private var library: [LibrarySong] = []
    /// Persistent IDs of the tracks that are music videos
    private var musicVideos: Set<String> = []
    private var reads = 0
    /// Persistent IDs of the copies read, in order
    private var copiesRead: [String] = []
    /// Whether each read of copies was told there were copies to choose between
    private var choosing: [Bool] = []
    /// Persistent IDs of the tracks fetched through the station
    private var fetched: [String] = []
    /// Persistent IDs the fake Music no longer has
    private var gone: Set<String> = []
    /// Persistent IDs gone by the time the chosen copy is fetched
    private var goneAtFetch: Set<String> = []
    /// How many reads of copies, and how many fetches, Music won't answer
    private var silentReads = 0
    private var silentFetches = 0
    private var clock: FakeClock!
    private var center: NotificationCenter!
    private var finder: LibraryMatchFinder!

    override func setUp() {
        super.setUp()
        library = [zombie, linger]
        musicVideos = []
        reads = 0
        copiesRead = []
        choosing = []
        fetched = []
        gone = []
        goneAtFetch = []
        silentReads = 0
        silentFetches = 0
        clock = FakeClock()
        center = NotificationCenter()
        let index = MusicLibraryIndex(readLibrary: { [unowned self] _ in
            DispatchQueue.main.sync { self.reads += 1 }
            return DispatchQueue.main.sync {
                self.library.map { LibrarySong(persistentID: $0.persistentID, name: $0.name, artist: $0.artist,
                                               albumArtist: $0.albumArtist) }
            }
        }, readCopies: { [unowned self] _, songs, choosing in
            DispatchQueue.main.sync { self.readCopies(songs, choosing: choosing) }
        }, musicPID: { 501 })
        index.observeLibraryChanges(in: center)
        finder = LibraryMatchFinder(index: index, fetchTrack: { [unowned self] song in
            self.fetched.append(song.persistentID)
            if self.silentFetches > 0 {
                self.silentFetches -= 1
                return .unanswered
            }
            guard !self.goneAtFetch.contains(song.persistentID), let track = self.track(song.persistentID) else { return .gone }
            return .found(track)
        }, clock: clock, center: center)
    }

    /// The fake Music's track for a persistent ID, or nil when it has none
    private func track(_ persistentID: String) -> FakeTrack? {
        guard !gone.contains(persistentID), let music = library.first(where: { $0.persistentID == persistentID }) else { return nil }
        return FakeTrack(name: music.name, artist: music.artist, album: music.album,
                         persistentID: music.persistentID, duration: music.duration ?? 0,
                         rating: music.rating, ratingKind: music.isRatingComputed ? .computed : .user,
                         mediaKind: musicVideos.contains(music.persistentID) ? .musicVideo : .music,
                         playedCount: music.playedCount)
    }

    private func readCopies(_ songs: [LibrarySong], choosing: Bool) -> [LibrarySong?]? {
        copiesRead += songs.map { $0.persistentID }
        self.choosing.append(choosing)
        if silentReads > 0 {
            silentReads -= 1
            return nil
        }
        return songs.map { song in track(song.persistentID).flatMap { song.reading($0, choosing: choosing) } }
    }

    /// Run the main run loop until `condition` holds, for the answers that come back from
    /// the index's queue
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
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
        XCTAssertEqual(copiesRead, [zombie.persistentID])
        XCTAssertEqual(fetched, [zombie.persistentID])
    }

    func testASongTheUserDoesNotHaveIsNotFound() {
        XCTAssertNil(ask(spotify("Dreams", by: "The Cranberries")))
        XCTAssertEqual(copiesRead, [], "nothing to read")
        XCTAssertEqual(fetched, [])
    }

    func testAnEpisodeIsAnsweredAtOnceWithoutReadingTheLibrary() {
        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries", id: "spotify:episode:0Q86acNRm6V9GYx55SXKwf")))
        XCTAssertEqual(reads, 0)
    }

    func testATrackThatIsGoneOrChangedIsNoMatch() {
        // The index can be a notification behind; reading the copies is what checks
        gone = [zombie.persistentID]

        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
        XCTAssertEqual(fetched, [], "nothing left to fetch")
    }

    func testATrackGoneByTheTimeItIsFetchedIsNoMatch() {
        goneAtFetch = [zombie.persistentID]

        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
        XCTAssertEqual(fetched.count, 1, "an answer, so remembered")
    }

    func testTheSameSongIsAnsweredFromMemory() {
        _ = ask(spotify("Zombie", by: "The Cranberries"))
        _ = ask(spotify("Zombie", by: "The Cranberries"))

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(copiesRead.count, 1, "and Music isn't asked about the copy again")
        XCTAssertEqual(fetched.count, 1)
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
        XCTAssertEqual(choosing, [true])
        XCTAssertEqual(fetched, [zombieOnStars.persistentID], "only the chosen copy is fetched")
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
        XCTAssertEqual(copiesRead.count, LibraryMatchFinder.copiesRead)
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

    // MARK: - Music that doesn't answer

    func testMusicThatDidNotAnswerIsAskedAgainNotTakenForNoCopy() throws {
        // Measured 2026-10-29: after seven idle minutes Music took over the short timeout to
        // answer, and a song the user had just seen the stars of was dropped as gone
        silentFetches = 1
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        waitUntil { clock.pendingOneShot != nil }

        XCTAssertEqual(answers.count, 0, "no answer yet, rather than \"not in the library\"")
        XCTAssertNil(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
        XCTAssertEqual(clock.pendingOneShot?.seconds, LibraryMatchFinder.retryDelay)

        clock.fireAllOneShots()
        waitUntil { answers.count == 1 }

        XCTAssertEqual(try XCTUnwrap(answers.first)?.song.persistentID, zombie.persistentID)
        XCTAssertEqual(fetched.count, 2)
    }

    func testMusicThatDidNotAnswerTheReadIsAskedAgainToo() {
        silentReads = 1
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        waitUntil { clock.pendingOneShot != nil }
        XCTAssertEqual(fetched, [], "nothing to fetch from a read Music didn't answer")

        clock.fireAllOneShots()
        waitUntil { answers.count == 1 }

        XCTAssertEqual(answers.first??.song.persistentID, zombie.persistentID)
    }

    func testSilenceTwiceIsNotRemembered() {
        silentReads = 2
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        waitUntil { clock.pendingOneShot != nil }
        clock.fireAllOneShots()
        waitUntil { answers.count == 1 }

        XCTAssertNil(answers.first ?? nil)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "asked again once, not forever")
        XCTAssertNil(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC"))
        XCTAssertEqual(ask(spotify("Zombie", by: "The Cranberries"))?.song.persistentID, zombie.persistentID,
                       "the next time the song comes up, Music is asked again")
    }

    func testSilenceKeepsWhatWasKnownForTheSong() {
        // A library change, then a Music too slow to say whether the copy is still there:
        // the stars already on show stay
        _ = ask(spotify("Zombie", by: "The Cranberries"))
        center.post(name: .ITLibraryDidChange, object: nil)
        silentFetches = 2
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        waitUntil { clock.pendingOneShot != nil }
        clock.fireAllOneShots()
        waitUntil { answers.count == 1 }

        XCTAssertEqual(answers.first??.song.persistentID, zombie.persistentID)
    }

    func testAskingAgainWhileWaitingWaitsForTheSameAnswer() {
        // Spotify sends a notification for every pause and play
        silentFetches = 1
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        waitUntil { clock.pendingOneShot != nil }
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        clock.fireAllOneShots()
        waitUntil { answers.count == 2 }

        XCTAssertEqual(fetched.count, 2, "one first try and one second, not one per ask")
    }

    func testAnotherSongCallsOffAskingAgain() {
        silentFetches = 1
        var zombieAnswers = 0
        finder.match(for: spotify("Zombie", by: "The Cranberries", id: "spotify:track:first")) { _ in zombieAnswers += 1 }
        waitUntil { clock.pendingOneShot != nil }

        XCTAssertEqual(ask(spotify("Linger", by: "The Cranberries", id: "spotify:track:second"))?.song.persistentID,
                       linger.persistentID)
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
        XCTAssertEqual(zombieAnswers, 0, "nobody is showing that song any more")
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
