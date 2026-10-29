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
                                     isRatingComputed: false, playedCount: 12, isFavorited: true)
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
    /// How many library reads, reads of copies and fetches Music won't answer
    private var silentLibraryReads = 0
    private var silentReads = 0
    private var silentFetches = 0
    private var musicIsRunning = true
    /// Music quits while the copies are being read, which then fails
    private var quitsWhileReadingCopies = false
    /// Runs as the copies are read, while the finder waits for them
    private var whileReadingCopies: (() -> Void)?
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
        silentLibraryReads = 0
        silentReads = 0
        silentFetches = 0
        musicIsRunning = true
        quitsWhileReadingCopies = false
        whileReadingCopies = nil
        clock = FakeClock()
        center = NotificationCenter()
        let index = MusicLibraryIndex(readLibrary: { [unowned self] _ in
            return DispatchQueue.main.sync { () -> [LibrarySong]? in
                self.reads += 1
                if self.silentLibraryReads > 0 {
                    self.silentLibraryReads -= 1
                    return nil
                }
                return self.library.map { LibrarySong(persistentID: $0.persistentID, name: $0.name, artist: $0.artist,
                                                      albumArtist: $0.albumArtist) }
            }
        }, readCopies: { [unowned self] _, songs, choosing in
            DispatchQueue.main.sync { self.readCopies(songs, choosing: choosing) }
        }, musicPID: { [unowned self] in self.musicIsRunning ? 501 : nil })
        index.observeLibraryChanges(in: center)
        finder = LibraryMatchFinder(index: index, fetchTrack: { [unowned self] song in
            self.fetched.append(song.persistentID)
            // Nil only when the station can't reach Music's library: the real one makes a
            // reference that asks Music nothing
            if self.silentFetches > 0 {
                self.silentFetches -= 1
                return nil
            }
            return self.track(song.persistentID)
        }, clock: clock, center: center)
    }

    /// The fake Music's track for a persistent ID, or nil when it has none
    private func track(_ persistentID: String) -> FakeTrack? {
        guard !gone.contains(persistentID), let music = library.first(where: { $0.persistentID == persistentID }) else { return nil }
        return FakeTrack(name: music.name, artist: music.artist, album: music.album,
                         persistentID: music.persistentID, duration: music.duration ?? 0,
                         rating: music.rating, ratingKind: music.isRatingComputed ? .computed : .user,
                         favorited: music.isFavorited,
                         mediaKind: musicVideos.contains(music.persistentID) ? .musicVideo : .music,
                         playedCount: music.playedCount)
    }

    private func readCopies(_ songs: [LibrarySong], choosing: Bool) -> [LibrarySong?]? {
        copiesRead += songs.map { $0.persistentID }
        self.choosing.append(choosing)
        let running = whileReadingCopies
        whileReadingCopies = nil
        running?()
        if quitsWhileReadingCopies {
            musicIsRunning = false
            return nil
        }
        if silentReads > 0 {
            silentReads -= 1
            return nil
        }
        // Music's search takes the name and artist with the persistent ID
        return songs.map { song in
            track(song.persistentID).flatMap { $0.name == song.name && $0.artist == song.artist ? $0 : nil }
                .flatMap { song.reading($0, choosing: choosing) }
        }
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

    func testACopyRenamedSinceTheIndexWasReadIsNoMatch() {
        // The index can be a library notification behind, and a renamed track may be another
        // song by now
        _ = ask(spotify("Linger", by: "The Cranberries", id: "spotify:track:warm"))
        library = [LibrarySong(persistentID: zombie.persistentID, name: "Ode to My Family", artist: "The Cranberries",
                               albumArtist: ""), linger]

        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
        XCTAssertEqual(fetched, [linger.persistentID], "nothing fetched for the renamed track")
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

    func testACopyDeletedBeforeTheNotificationIsLookedForAgain() {
        // Deleted in Music while its stars are on show: the menu bar finds the copy gone
        // before Music announces the change, and the next answer can't be the same copy
        XCTAssertNotNil(ask(spotify("Zombie", by: "The Cranberries")))
        library = [linger]

        finder.copyIsGone()

        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
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

    // MARK: - What a new match shows

    func testANewMatchBringsTheStarsAndHeartReadWithIt() throws {
        // So nothing on the main thread waits on Music to show them. Measured 2026-10-29,
        // a slow Music held the stars back 3.9 s, two of them on the main thread.
        let match = try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries")))

        XCTAssertEqual(match.shown, LibraryMatch.Shown(rating: 80, isFavorited: true))
    }

    func testARatingMusicWorkedOutIsNotShownAsTheUsers() throws {
        library = [LibrarySong(persistentID: "00000000000000A1", name: "Zombie", artist: "The Cranberries",
                               albumArtist: "", album: "No Need to Argue", rating: 60, isRatingComputed: true)]

        XCTAssertEqual(try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries"))).shown,
                       LibraryMatch.Shown(rating: nil, isFavorited: false))
    }

    func testWhatWasReadIsForgottenOnceShown() throws {
        // A rating changed in Music after the match was made would otherwise never show
        _ = ask(spotify("Zombie", by: "The Cranberries"))

        XCTAssertNil(try XCTUnwrap(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")).shown)
        XCTAssertNil(try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries"))).shown, "an answer from memory")
    }

    func testTheStripHearsAboutANewMatchWithWhatWasRead() {
        // The strip reads `knownMatch` when the answer is posted
        var shown: LibraryMatch.Shown?
        let observer = center.addObserver(forName: .libraryMatchDidChange, object: finder, queue: nil) { [unowned self] _ in
            shown = self.finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")?.shown
        }
        defer { center.removeObserver(observer) }

        _ = ask(spotify("Zombie", by: "The Cranberries"))

        XCTAssertEqual(shown, LibraryMatch.Shown(rating: 80, isFavorited: true))
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

        XCTAssertEqual(choosing, [false], "no plays: there is nothing to choose between")
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

    func testACopyOnALiveAlbumIsLeftOutOnceItsAlbumIsRead() throws {
        // The index has names only, so this is a copy until its album is read. Rated higher
        // and played more, it would otherwise be the one chosen.
        let live = LibrarySong(persistentID: "00000000000000E5", name: "Zombie", artist: "The Cranberries",
                               albumArtist: "", album: "MTV Unplugged", duration: 260, rating: 100,
                               isRatingComputed: false, playedCount: 50)
        library = [live, zombie]

        let match = try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries")))

        XCTAssertEqual(match.song.persistentID, zombie.persistentID)
        XCTAssertEqual(Set(copiesRead), [live.persistentID, zombie.persistentID])
        XCTAssertEqual(fetched, [zombie.persistentID], "the live copy is never fetched")

        library = [live]
        center.post(name: .ITLibraryDidChange, object: nil)
        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries", id: "spotify:track:again")), "a live recording alone is no match")
        XCTAssertEqual(ask(spotify("Zombie", by: "The Cranberries", on: "MTV Unplugged", id: "spotify:track:unplugged"))?
            .song.persistentID, live.persistentID, "but it is the live song's copy")
    }

    func testACopyThatIsGoneLeavesTheOthers() {
        library = [zombie, zombieOnStars]
        gone = [zombieOnStars.persistentID]

        XCTAssertEqual(ask(spotify("Zombie", by: "The Cranberries", on: "Stars: The Best Of 1992-2002"))?.song.persistentID,
                       zombie.persistentID)
    }

    func testEveryCopyIsReadSoTheRightOneCanBeChosen() throws {
        // The index can't order copies by album, so the one on the album Spotify names can
        // come last by persistent ID
        let others = (0..<LibraryMatchFinder.copiesRead - 1).map {
            LibrarySong(persistentID: String(format: "%016X", $0), name: "Zombie", artist: "The Cranberries",
                        albumArtist: "", album: "Compilation \($0)")
        }
        let onTheAlbum = LibrarySong(persistentID: "FFFFFFFFFFFFFFFF", name: "Zombie", artist: "The Cranberries",
                                     albumArtist: "", album: "No Need to Argue")
        library = others + [onTheAlbum]

        let match = try XCTUnwrap(ask(spotify("Zombie", by: "The Cranberries", on: "No Need to Argue")))

        XCTAssertEqual(match.song.persistentID, onTheAlbum.persistentID)
        XCTAssertEqual(copiesRead.count, LibraryMatchFinder.copiesRead)
    }

    func testASongHeldMoreOftenThanIsReadIsNoMatch() {
        // Reading only some would leave the choice to persistent IDs
        library = (0...LibraryMatchFinder.copiesRead).map {
            LibrarySong(persistentID: String(format: "%016X", $0), name: "Zombie", artist: "The Cranberries", albumArtist: "")
        }

        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
        XCTAssertEqual(copiesRead, [], "nothing read")
    }

    func testPastTheLimitOnlyTheCopiesTitledAlikeAreRead() throws {
        // A live song among more studio copies than are read: plain ones could only be live by
        // their albums, and the copy whose title says so is the likely one (the second review)
        let studio = (0...LibraryMatchFinder.copiesRead).map {
            LibrarySong(persistentID: String(format: "%016X", $0), name: "Zombie", artist: "The Cranberries",
                        albumArtist: "", album: "Compilation \($0)")
        }
        let live = LibrarySong(persistentID: "FFFFFFFFFFFFFFFF", name: "Zombie (Live)", artist: "The Cranberries",
                               albumArtist: "", album: "Live in Paris")
        library = studio + [live]

        let match = try XCTUnwrap(ask(spotify("Zombie - Live", by: "The Cranberries", on: "Live in Paris")))

        XCTAssertEqual(match.song.persistentID, live.persistentID)
        XCTAssertEqual(copiesRead, [live.persistentID])
    }

    func testPastTheLimitALiveAlbumsSongFindsTheCopyTitledLive() throws {
        // Spotify's title says nothing, its album says it is live: compared title to title,
        // all the studio copies were titled alike, too many to read (the third review)
        let studio = (0...LibraryMatchFinder.copiesRead).map {
            LibrarySong(persistentID: String(format: "%016X", $0), name: "Clocks", artist: "Coldplay",
                        albumArtist: "", album: "Compilation \($0)")
        }
        let live = LibrarySong(persistentID: "FFFFFFFFFFFFFFFF", name: "Clocks (Live)", artist: "Coldplay",
                               albumArtist: "", album: "Live 2003")
        library = studio + [live]

        let match = try XCTUnwrap(ask(spotify("Clocks", by: "Coldplay", on: "Live 2003")))

        XCTAssertEqual(match.song.persistentID, live.persistentID)
        XCTAssertEqual(copiesRead, [live.persistentID])
    }

    // MARK: - What the user chooses

    func testWhatTheUserChoosesForTheCopyIsRemembered() throws {
        // What is remembered is shown when Music doesn't answer: the strip showed the rating
        // read with the match where the menu bar showed the one just chosen (the third review)
        let identity = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
        _ = ask(spotify("Zombie", by: "The Cranberries"))

        finder.userDidRate(zombie.persistentID, rating: 100)
        finder.userDidFavorite(zombie.persistentID, isFavorited: false)

        let song = try XCTUnwrap(finder.knownMatch(for: identity)).song
        XCTAssertEqual(song.rating, 100)
        XCTAssertFalse(song.isFavorited)
        XCTAssertEqual(LibraryMatch.Shown(song: song), LibraryMatch.Shown(rating: 100, isFavorited: false))
    }

    func testAChoiceForAnotherCopyChangesNothing() throws {
        let identity = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
        _ = ask(spotify("Zombie", by: "The Cranberries"))

        finder.userDidRate(linger.persistentID, rating: 20)

        XCTAssertEqual(try XCTUnwrap(finder.knownMatch(for: identity)).song.rating, zombie.rating)
    }

    func testARatingTheUserChoosesIsTheirsNotMusics() throws {
        library = [LibrarySong(persistentID: "C3", name: "Zombie", artist: "The Cranberries", albumArtist: "",
                               rating: 60, isRatingComputed: true)]
        _ = ask(spotify("Zombie", by: "The Cranberries"))
        XCTAssertNil(LibraryMatch.Shown(song: try XCTUnwrap(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")).song).rating,
                     "worked out from the album's, so not shown as the user's")

        finder.userDidRate("C3", rating: 80)

        XCTAssertEqual(LibraryMatch.Shown(song: try XCTUnwrap(finder.knownMatch(for: "spotify:track:4uLU6hMCjMI75M1A2tKUQC")).song).rating, 80)
    }

    func testTheLibraryHasBeenReadOnceAskedAbout() {
        // The first read builds the matcher from nothing, so the menu bar waits longer for it
        XCTAssertFalse(finder.hasReadLibrary)
        _ = ask(spotify("Zombie", by: "The Cranberries"))
        XCTAssertTrue(finder.hasReadLibrary)
    }

    // MARK: - Reading a copy

    func testReadingACopyToChooseBetweenTakesWhatChooses() throws {
        let track = FakeTrack(name: "Zombie", artist: "The Cranberries", album: "No Need to Argue", duration: 306.5,
                              rating: 60, ratingKind: .computed, favorited: true, playedCount: 7)
        let song = LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries", albumArtist: "")

        XCTAssertEqual(song.reading(track, choosing: true),
                       LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries", albumArtist: "",
                                   album: "No Need to Argue", duration: 306.5, rating: 60, isRatingComputed: true,
                                   playedCount: 7, isFavorited: true))
        XCTAssertEqual(song.reading(track, choosing: false),
                       LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries", albumArtist: "",
                                   album: "No Need to Argue", rating: 60, isRatingComputed: true,
                                   isFavorited: true),
                       "what is shown and what can rule the copy out, but not the length or plays")
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

    func testTheRatingsKindIsAskedOnlyWhenThereIsARating() {
        // Each property is an Apple Event, and most of a library is unrated
        let song = LibrarySong(persistentID: "A1", name: "Song", artist: "Artist", albumArtist: "")
        let unrated = FakeTrack(rating: 0, ratingKind: .computed)
        let rated = FakeTrack(rating: 80, ratingKind: .computed)

        XCTAssertEqual(song.reading(unrated, choosing: false)?.isRatingComputed, false)
        XCTAssertEqual(unrated.ratingKindReads, 0)
        XCTAssertEqual(song.reading(rated, choosing: false)?.isRatingComputed, true)
        XCTAssertEqual(rated.ratingKindReads, 1)
    }

    // MARK: - Music that doesn't answer

    func testAReadDuringWhichAnEventFailedIsNoAnswer() {
        // Scripting Bridge answers a failed read with nil, 0 or false: 0 stars for a rated copy
        var failures = 0

        XCTAssertEqual(MenuBarRatingControl.ifAnswered(failures: { failures }) { 80 }, 80)
        XCTAssertNil(MenuBarRatingControl.ifAnswered(failures: { failures }) { () -> Int? in
            failures += 1
            return 0
        })
        XCTAssertNil(MenuBarRatingControl.ifAnswered(failures: { failures }) { () -> Int? in nil })
    }

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

    func testALibraryReadThatFailedIsAskedAgain() {
        // Measured 2026-10-29: the first read after a launch failed with -1701 in 14 ms, and
        // the song it was for showed Spotify's heart to its end, though it was in the library
        silentLibraryReads = 1
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        waitUntil { clock.pendingOneShot != nil }

        XCTAssertEqual(answers.count, 0, "no answer yet, rather than \"not in the library\"")
        XCTAssertEqual(copiesRead, [], "no index to find copies in")

        clock.fireAllOneShots()
        waitUntil { answers.count == 1 }

        XCTAssertEqual(answers.first??.song.persistentID, zombie.persistentID)
        XCTAssertEqual(reads, 2)
    }

    func testNoMusicIsAnsweredAtOnce() {
        // Nothing to wait for: the strip and the menu bar show Spotify's song straight away
        musicIsRunning = false

        XCTAssertNil(ask(spotify("Zombie", by: "The Cranberries")))
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "not asked again")
        XCTAssertEqual(reads, 0)
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

    func testAnAnswerMusicCouldNotCheckIsNotGivenAgain() {
        // Not in the library, then added in Music, then Music too slow twice to say so: the
        // old "not in the library" can't stand until the next library change
        let dreams = LibrarySong(persistentID: "00000000000000C3", name: "Dreams", artist: "The Cranberries", albumArtist: "")
        XCTAssertNil(ask(spotify("Dreams", by: "The Cranberries")))
        library.append(dreams)
        center.post(name: .ITLibraryDidChange, object: nil)
        silentReads = 2
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Dreams", by: "The Cranberries")) { answers.append($0) }
        waitUntil { clock.pendingOneShot != nil }
        clock.fireAllOneShots()
        waitUntil { answers.count == 1 }

        XCTAssertEqual(ask(spotify("Dreams", by: "The Cranberries"))?.song.persistentID, dreams.persistentID)
    }

    func testMusicQuittingWhileAskedIsAnsweredAtOnce() {
        // Nothing to wait for, and asking again would only find no Music
        quitsWhileReadingCopies = true
        var answers: [LibraryMatch?] = []
        finder.match(for: spotify("Zombie", by: "The Cranberries")) { answers.append($0) }
        waitUntil { answers.count == 1 }

        XCTAssertNil(answers.first ?? nil)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "not asked again")
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

    func testAQuestionOvertakenWhileItsCopiesAreReadIsNeverAnswered() {
        // The same, with Spotify moving on after the library was read and while the old
        // song's copies were: their answer must not reach the new song's question
        _ = ask(spotify("Linger", by: "The Cranberries", id: "spotify:track:warm"))
        var answers: [String?] = []
        let answered = expectation(description: "answered")
        whileReadingCopies = { [unowned self] in
            self.finder.match(for: self.spotify("Linger", by: "The Cranberries", id: "spotify:track:second")) {
                answers.append($0?.song.name)
                answered.fulfill()
            }
        }
        finder.match(for: spotify("Zombie", by: "The Cranberries", id: "spotify:track:first")) {
            answers.append($0?.song.name)
        }
        wait(for: [answered], timeout: 5)
        waitUntil { copiesRead.count == 3 }

        XCTAssertEqual(answers, ["Linger"])
    }

}
