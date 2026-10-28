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

    private var library: [LibrarySong] = []
    private var reads = 0
    private var fetched: [String] = []
    /// Persistent IDs the fake Music no longer has
    private var gone: Set<String> = []
    private var center: NotificationCenter!
    private var finder: LibraryMatchFinder!

    override func setUp() {
        super.setUp()
        library = [zombie, linger]
        reads = 0
        fetched = []
        gone = []
        center = NotificationCenter()
        let index = MusicLibraryIndex(readLibrary: { [unowned self] _ in
            DispatchQueue.main.sync { self.reads += 1 }
            return DispatchQueue.main.sync { self.library }
        }, musicPID: { 501 })
        index.observeLibraryChanges(in: center)
        finder = LibraryMatchFinder(index: index, fetchTrack: { [unowned self] song in
            self.fetched.append(song.persistentID)
            guard !self.gone.contains(song.persistentID) else { return nil }
            return FakeTrack(name: song.name, artist: song.artist, album: song.album,
                             persistentID: song.persistentID, rating: song.rating)
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

        XCTAssertEqual(match.song, zombie)
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
                                   albumArtist: "", album: "", duration: nil, rating: 0,
                                   isRatingComputed: false, playedCount: 0))
        center.post(name: .ITLibraryDidChange, object: nil)

        XCTAssertEqual(ask(spotify("Dreams", by: "The Cranberries"))?.song.persistentID, "00000000000000C3")
        XCTAssertEqual(reads, 2)
    }

    func testTheLastAnswerIsKeptUntilANewOneReplacesIt() {
        // So the strip doesn't drop the stars while the library is read again after a rating
        _ = ask(spotify("Zombie", by: "The Cranberries"))
        center.post(name: .ITLibraryDidChange, object: nil)

        XCTAssertEqual(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.song, zombie)
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
