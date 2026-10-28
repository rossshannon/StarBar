//
//  MusicLibraryIndexTests.swift
//  StarBarTests
//
//  Turning a bulk read of the library into songs, and when the index reads Music again. No
//  Music here: the reads are fakes. `MusicLibraryLookupTests` checks the real bulk read
//  against Music under --test-all.
//

import XCTest
@testable import StarBar

final class MusicLibraryIndexTests: XCTestCase {

    private let song = iTunesEMdK.music.rawValue
    private let musicVideo = iTunesEMdK.musicVideo.rawValue
    private let user = iTunesERtK.user.rawValue
    private let computed = iTunesERtK.computed.rawValue

    /// Columns for `rows`, each a track's values in `MusicLibraryIndex.keys` order, with the
    /// persistent IDs read again unchanged
    private func columns(_ rows: [[Any]]) -> MusicLibraryIndex.Columns {
        var columns = MusicLibraryIndex.Columns()
        for (index, key) in MusicLibraryIndex.keys.enumerated() {
            columns[key] = rows.map { $0[index] }
        }
        columns[MusicLibraryIndex.recheckKey] = columns["persistentID"]
        return columns
    }

    private func row(_ id: String, _ name: String, by artist: String, albumArtist: Any = "", album: Any = "",
                     duration: Any = 200.0, rating: Any = 0, kind: Any? = nil, played: Any = 0, media: Any? = nil) -> [Any] {
        return [id, name, artist, albumArtist, album, duration, rating, kind ?? NSNumber(value: user),
                played, media ?? NSNumber(value: song)]
    }

    // MARK: - Columns to songs

    func testEachRowBecomesASong() throws {
        let songs = try XCTUnwrap(MusicLibraryIndex.songs(from: columns([
            row("A1", "Zombie", by: "The Cranberries", albumArtist: "The Cranberries", album: "No Need to Argue",
                duration: 306.5, rating: 80, played: 12),
            row("B2", "Linger", by: "The Cranberries", rating: 60, kind: NSNumber(value: computed))
        ])))

        XCTAssertEqual(songs, [
            LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries", albumArtist: "The Cranberries",
                        album: "No Need to Argue", duration: 306.5, rating: 80, isRatingComputed: false, playedCount: 12),
            LibrarySong(persistentID: "B2", name: "Linger", artist: "The Cranberries", albumArtist: "", album: "",
                        duration: 200, rating: 60, isRatingComputed: true, playedCount: 0)
        ])
    }

    func testOnlySongsAreKept() throws {
        let songs = try XCTUnwrap(MusicLibraryIndex.songs(from: columns([
            row("A1", "Zombie", by: "The Cranberries"),
            row("B2", "Zombie", by: "The Cranberries", media: NSNumber(value: musicVideo))
        ])))

        XCTAssertEqual(songs.map { $0.persistentID }, ["A1"])
    }

    func testAnEnumeratedValueCanComeAsADescriptor() throws {
        let songs = try XCTUnwrap(MusicLibraryIndex.songs(from: columns([
            row("A1", "Zombie", by: "The Cranberries", kind: NSAppleEventDescriptor(enumCode: computed),
                media: NSAppleEventDescriptor(enumCode: song))
        ])))

        XCTAssertEqual(songs.first?.isRatingComputed, true)
    }

    func testAValueMusicCouldNotGiveIsLeftOut() throws {
        // A missing value comes back as NSNull or a null descriptor, never as a string
        let songs = try XCTUnwrap(MusicLibraryIndex.songs(from: columns([
            row("A1", "Zombie", by: "The Cranberries", albumArtist: NSNull(), album: NSNull(),
                duration: NSNull(), rating: NSNull(), played: NSAppleEventDescriptor.null())
        ])))

        XCTAssertEqual(songs.first, LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries",
                                                albumArtist: "", album: "", duration: nil, rating: 0,
                                                isRatingComputed: false, playedCount: 0))
    }

    func testATrackWithNoNameOrIDIsSkipped() throws {
        var rows = [row("A1", "Zombie", by: "The Cranberries"), row("", "Linger", by: "The Cranberries"),
                    row("C3", "Dreams", by: "The Cranberries")]
        rows[2][1] = NSNull()

        let songs = try XCTUnwrap(MusicLibraryIndex.songs(from: columns(rows)))

        XCTAssertEqual(songs.map { $0.persistentID }, ["A1"])
    }

    func testAShortColumnThrowsTheReadAway() {
        var columns = self.columns([row("A1", "Zombie", by: "The Cranberries"), row("B2", "Linger", by: "The Cranberries")])
        columns["rating"]?.removeLast()

        XCTAssertNil(MusicLibraryIndex.songs(from: columns))
    }

    func testAMissingColumnThrowsTheReadAway() {
        var columns = self.columns([row("A1", "Zombie", by: "The Cranberries")])
        columns["album"] = nil

        XCTAssertNil(MusicLibraryIndex.songs(from: columns))
    }

    func testIDsThatMovedDuringTheReadThrowItAway() {
        // One song deleted and another added between the reads: every count still agrees,
        // and only the second read of the IDs can tell
        var columns = self.columns([row("A1", "Zombie", by: "The Cranberries"), row("B2", "Linger", by: "The Cranberries")])
        columns[MusicLibraryIndex.recheckKey] = ["A1", "C3"]

        XCTAssertNil(MusicLibraryIndex.songs(from: columns))
    }

    func testAReadWithNoTracksIsAFailure() {
        // A read that went wrong quietly looks exactly like this; an empty library would match
        // nothing until the next edit
        XCTAssertNil(MusicLibraryIndex.songs(from: columns([])))
    }

    func testCodes() {
        XCTAssertEqual(MusicLibraryIndex.code(NSNumber(value: song)), song)
        XCTAssertEqual(MusicLibraryIndex.code(NSAppleEventDescriptor(enumCode: song)), song)
        XCTAssertEqual(MusicLibraryIndex.code(NSAppleEventDescriptor(typeCode: song)), song)
        XCTAssertNil(MusicLibraryIndex.code("song"))
        XCTAssertNil(MusicLibraryIndex.code(NSNull()))
    }

    // MARK: - When Music is read

    /// A fake library and Music process, counting reads. `gate`, when set, holds each read
    /// until it is signalled, so a test can act while one is out.
    private final class FakeMusic {
        var pid: pid_t? = 501
        var songs: [LibrarySong]? = [LibrarySong(persistentID: "A1", name: "Zombie", artist: "The Cranberries",
                                                  albumArtist: "", album: "", duration: nil, rating: 80,
                                                  isRatingComputed: false, playedCount: 0)]
        var gate: DispatchSemaphore?
        private let lock = NSLock()
        private var _reads = 0
        var reads: Int {
            lock.lock(); defer { lock.unlock() }
            return _reads
        }

        func read(_ pid: pid_t) -> [LibrarySong]? {
            lock.lock()
            _reads += 1
            let gate = self.gate
            let songs = self.songs
            lock.unlock()
            gate?.wait()
            return songs
        }
    }

    private var music: FakeMusic!
    private var center: NotificationCenter!
    private var index: MusicLibraryIndex!

    override func setUp() {
        super.setUp()
        music = FakeMusic()
        center = NotificationCenter()
        let music = self.music!
        index = MusicLibraryIndex(readLibrary: { music.read($0) }, musicPID: { music.pid })
        index.observeLibraryChanges(in: center)
    }

    /// The matcher `withMatcher` hands back, waiting for a read if there is one
    private func ask() -> SongMatcher? {
        let answered = expectation(description: "withMatcher answered")
        var result: SongMatcher?
        index.withMatcher {
            result = $0
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        return result
    }

    private func zombie(in matcher: SongMatcher?) -> LibrarySong? {
        return matcher?.match(for: SongQuery(name: "Zombie", artist: "The Cranberries", album: "", duration: nil))
    }

    func testTheFirstAskReadsTheLibrary() {
        XCTAssertEqual(zombie(in: ask())?.persistentID, "A1")
        XCTAssertEqual(music.reads, 1)
    }

    func testLaterAsksUseTheSameRead() {
        _ = ask()
        _ = ask()
        _ = ask()

        XCTAssertEqual(music.reads, 1)
        XCTAssertFalse(index.needsRead)
    }

    func testEitherLibraryNotificationMeansReadingAgain() {
        _ = ask()

        center.post(name: .ITLibraryDidChange, object: nil)
        XCTAssertTrue(index.needsRead)
        _ = ask()
        XCTAssertEqual(music.reads, 2)

        center.post(name: Notification.Name("com.apple.iTunes.libraryChanged"), object: nil)
        _ = ask()
        XCTAssertEqual(music.reads, 3)
    }

    func testANotificationReadsNothingByItself() {
        // Event-driven, not eager: a library edit costs nothing until something asks
        _ = ask()
        center.post(name: .ITLibraryDidChange, object: nil)
        center.post(name: .ITLibraryDidChange, object: nil)

        XCTAssertEqual(music.reads, 1)
    }

    func testAsksDuringAReadShareIt() {
        music.gate = DispatchSemaphore(value: 0)
        let both = expectation(description: "both answered")
        both.expectedFulfillmentCount = 2
        var answers: [SongMatcher?] = []
        index.withMatcher { answers.append($0); both.fulfill() }
        index.withMatcher { answers.append($0); both.fulfill() }

        music.gate?.signal()
        wait(for: [both], timeout: 5)

        XCTAssertEqual(music.reads, 1)
        XCTAssertEqual(answers.compactMap { zombie(in: $0)?.persistentID }, ["A1", "A1"])
    }

    func testAChangeDuringAReadLeavesItStale() {
        // The change may or may not be in what was read, so the read is used once and the
        // next ask reads again
        music.gate = DispatchSemaphore(value: 0)
        let answered = expectation(description: "answered")
        var answer: SongMatcher?
        index.withMatcher { answer = $0; answered.fulfill() }

        center.post(name: .ITLibraryDidChange, object: nil)
        music.gate?.signal()
        wait(for: [answered], timeout: 5)

        XCTAssertNotNil(zombie(in: answer))
        XCTAssertTrue(index.needsRead)
        music.gate = nil
        _ = ask()
        XCTAssertEqual(music.reads, 2)
    }

    func testNoMusicMeansNoMatcherAndNoRead() {
        music.pid = nil

        XCTAssertNil(ask())
        XCTAssertEqual(music.reads, 0)
    }

    func testMusicQuittingDropsTheIndex() {
        _ = ask()
        music.pid = nil

        XCTAssertNil(ask())
    }

    func testANewMusicProcessIsReadAgain() {
        // The library notifications don't cover edits made while StarBar wasn't listening to
        // that Music, such as a cloud library sync at launch
        _ = ask()
        music.pid = 777

        XCTAssertTrue(index.needsRead)
        _ = ask()
        XCTAssertEqual(music.reads, 2)
    }

    func testAFailedReadIsTriedAgainNextTime() {
        music.songs = nil
        XCTAssertNil(ask())

        music.songs = [LibrarySong(persistentID: "B2", name: "Zombie", artist: "The Cranberries", albumArtist: "",
                                   album: "", duration: nil, rating: 0, isRatingComputed: false, playedCount: 0)]
        XCTAssertEqual(zombie(in: ask())?.persistentID, "B2")
        XCTAssertEqual(music.reads, 2)
    }

}
