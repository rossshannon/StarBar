//
//  ScrobbleQueueTests.swift
//  StarBarTests
//

import XCTest
@testable import StarBar

final class ScrobbleQueueTests: XCTestCase {

    private let user = "listener"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// What the queue takes for now; tests move it on by hand
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var store = MemoryScrobbleQueueStore()
    private let day: TimeInterval = 24 * 60 * 60

    override func setUp() {
        super.setUp()
        now = start
        store = MemoryScrobbleQueueStore()
    }

    private func makeQueue(user: String? = nil) -> ScrobbleQueue {
        return ScrobbleQueue(user: user ?? self.user, store: store, now: { self.now })
    }

    /// A play of `title` that started `ago` seconds before `start`
    private func scrobble(_ title: String = "Song", artist: String = "Artist", ago: TimeInterval = 600) -> Scrobble {
        return Scrobble(track: .test(title, artist: artist), startedAt: start.addingTimeInterval(-ago), source: "music")
    }

    private func love(_ title: String = "Song", artist: String = "Artist", _ loved: Bool = true) -> ScrobbleQueue.LoveChange {
        return ScrobbleQueue.LoveChange(title: title, artist: artist, loved: loved)
    }

    // MARK: - Scrobbles

    func testAddedScrobbleStaysUntilFinished() {
        let queue = makeQueue()
        let play = scrobble()
        queue.add(play)

        XCTAssertEqual(queue.nextBatch(), [play], "A scrobble just added should be the next batch")
        XCTAssertEqual(queue.nextBatch(), [play], "nextBatch must only look: the scrobble should still be there until Last.fm answers")
        XCTAssertFalse(queue.isEmpty, "A waiting scrobble should make the queue not empty")

        queue.finished([play])
        XCTAssertTrue(queue.nextBatch().isEmpty, "A finished scrobble should be gone")
        XCTAssertTrue(queue.isEmpty, "The queue should be empty once its only scrobble is finished")
        XCTAssertEqual(store.contents[user], queue.contents, "The store should hold what the queue holds")
        XCTAssertEqual(store.contents[user]?.scrobbles, [], "The store should no longer hold the finished scrobble")
    }

    func testScrobblesAddedOutOfOrderComeOutOldestFirst() {
        // Catches an append in place of an insert: two players can finish plays out of order
        let queue = makeQueue()
        let newest = scrobble("C", ago: 100)
        let oldest = scrobble("A", ago: 900)
        let middle = scrobble("B", ago: 500)
        queue.add(newest)
        queue.add(oldest)
        queue.add(middle)

        XCTAssertEqual(queue.nextBatch().map { $0.track.title }, ["A", "B", "C"], "Scrobbles should come out in order of when they started")
    }

    func testScrobblesStartedAtTheSameTimeKeepTheOrderTheyWereAdded() {
        let queue = makeQueue()
        queue.add(scrobble("First", ago: 300))
        queue.add(scrobble("Second", ago: 300))

        XCTAssertEqual(queue.nextBatch().map { $0.track.title }, ["First", "Second"], "Equal start times should keep insertion order")
    }

    func testManyScrobblesGoInBatchesOfFifty() {
        let queue = makeQueue()
        for index in 0..<120 {
            queue.add(scrobble("Song \(index)", ago: TimeInterval(10_000 - index)))
        }

        var sizes: [Int] = []
        var titles: [String] = []
        for _ in 0..<5 {
            let batch = queue.nextBatch()
            if batch.isEmpty { break }
            sizes.append(batch.count)
            titles += batch.map { $0.track.title }
            queue.finished(batch)
        }

        XCTAssertEqual(sizes, [50, 50, 20], "120 scrobbles should go in batches of 50, 50 and 20")
        XCTAssertEqual(titles, (0..<120).map { "Song \($0)" }, "Every scrobble should be sent once, oldest first")
        XCTAssertTrue(queue.isEmpty, "Nothing should be left once every batch is finished")
    }

    func testTheSamePlayIsAddedOnce() {
        let queue = makeQueue()
        queue.add(scrobble("Song", artist: "Artist", ago: 300))
        queue.add(scrobble("SONG", artist: "artist", ago: 300))

        XCTAssertEqual(queue.contents.scrobbles.count, 1, "The same song at the same start time, differing only in case, should be added once")
    }

    func testTheSameSongStartedAgainIsAddedAgain() {
        let queue = makeQueue()
        queue.add(scrobble("Song", ago: 600))
        queue.add(scrobble("Song", ago: 300))

        XCTAssertEqual(queue.contents.scrobbles.count, 2, "A second play of the same song, started later, is a play of its own")
    }

    func testAnotherSongAtTheSameTimeIsAdded() {
        let queue = makeQueue()
        queue.add(scrobble("One", ago: 300))
        queue.add(scrobble("Two", ago: 300))

        XCTAssertEqual(queue.contents.scrobbles.count, 2, "Only the same song makes a duplicate, not the same time alone")
    }

    func testAScrobbleWithNoArtistIsNotAdded() {
        let queue = makeQueue()
        queue.add(scrobble("Song", artist: "  "))

        XCTAssertTrue(queue.isEmpty, "Last.fm takes nothing without an artist, so it should never be queued")
        XCTAssertEqual(store.saves, 0, "Ignoring a scrobble should not save")
    }

    func testAScrobbleTooOldIsDroppedAtNextBatch() {
        let queue = makeQueue()
        let kept = scrobble("Kept", ago: 600)
        queue.add(scrobble("Old", ago: 1200))
        queue.add(kept)
        let savesBefore = store.saves

        // "Old" is now 14 days and 5 minutes old, "Kept" 5 minutes short of 14 days
        now = start.addingTimeInterval(14 * day - 900)
        XCTAssertEqual(queue.nextBatch(), [kept], "A scrobble more than 14 days old should be dropped, one just under kept")
        XCTAssertEqual(store.saves, savesBefore + 1, "Dropping old scrobbles should save once")
        XCTAssertEqual(store.contents[user]?.scrobbles, [kept], "The store should no longer hold the dropped scrobble")
    }

    func testAScrobbleTooOldIsDroppedWhenTheQueueIsRead() {
        let old = scrobble("Old", ago: 15 * day)
        let recent = scrobble("Recent", ago: 13 * day)
        store.contents[user] = ScrobbleQueue.Contents(scrobbles: [old, recent])

        let queue = makeQueue()

        XCTAssertEqual(queue.contents.scrobbles, [recent], "A scrobble 15 days old should be dropped at launch, one 13 days old kept")
        XCTAssertEqual(store.saves, 1, "Dropping at launch should save once")
    }

    func testOpeningAQueueWithNothingTooOldDoesNotSave() {
        store.contents[user] = ScrobbleQueue.Contents(scrobbles: [scrobble(ago: 13 * day)])
        _ = makeQueue()

        XCTAssertEqual(store.saves, 0, "A queue read at launch with nothing to drop should not be written back")
    }

    func testPastTheLimitTheOldestScrobblesGo() {
        let limit = ScrobbleQueue.maxScrobbles
        let waiting = (0..<(limit + 2)).map { scrobble("Song \($0)", ago: TimeInterval(limit + 10 - $0)) }
        store.contents[user] = ScrobbleQueue.Contents(scrobbles: waiting)
        let queue = makeQueue()

        let newest = scrobble("Newest", ago: 1)
        queue.add(newest)

        XCTAssertEqual(queue.contents.scrobbles.count, limit, "The queue should never hold more than maxScrobbles")
        XCTAssertEqual(queue.contents.scrobbles.first?.track.title, "Song 3", "The three oldest should have gone")
        XCTAssertEqual(queue.contents.scrobbles.last, newest, "The newest should be kept")
        XCTAssertEqual(store.contents[user]?.scrobbles.count, limit, "The store should hold the capped list")
    }

    // MARK: - Hearts

    func testLoveThenUnloveLeavesOnlyTheUnlove() {
        let queue = makeQueue()
        queue.add(love("Song", artist: "Artist", true))
        queue.add(love("song", artist: "ARTIST", false))

        XCTAssertEqual(queue.contents.loves, [love("song", artist: "ARTIST", false)], "A heart set then cleared should send only where it ended up")
        XCTAssertEqual(queue.nextLove, love("song", artist: "ARTIST", false), "The waiting change should be the unlove")
    }

    func testChangesForDifferentSongsKeepTheirOrder() {
        let queue = makeQueue()
        queue.add(love("One"))
        queue.add(love("Two", false))
        queue.add(love("Three"))

        XCTAssertEqual(queue.contents.loves.map { $0.title }, ["One", "Two", "Three"], "Changes for different songs should all wait, oldest first")
        XCTAssertEqual(queue.nextLove?.title, "One", "nextLove should be the oldest")
    }

    func testFinishingAChangeReplacedInFlightKeepsTheNewerOne() {
        // Catches a finished(_:) that removes by song rather than by exact change
        let queue = makeQueue()
        let sent = love("Song", true)
        queue.add(sent)
        let newer = love("Song", false)
        queue.add(newer)

        queue.finished(sent)

        XCTAssertEqual(queue.contents.loves, [newer], "The unlove added while the love was being sent should stay")
    }

    func testFinishingTheExactChangeRemovesIt() {
        let queue = makeQueue()
        let change = love("Song")
        queue.add(change)
        queue.finished(change)

        XCTAssertNil(queue.nextLove, "A finished change should be gone")
        XCTAssertTrue(queue.isEmpty, "The queue should be empty once its only change is finished")
        XCTAssertEqual(store.contents[user]?.loves, [], "The store should no longer hold the finished change")
    }

    func testAChangeWithNoArtistIsIgnored() {
        let queue = makeQueue()
        queue.add(love("Song", artist: " "))

        XCTAssertNil(queue.nextLove, "A change with an empty artist should never be queued")
        XCTAssertEqual(store.saves, 0, "Ignoring a change should not save")
    }

    func testIsForSameSongIgnoresCaseAndLoved() {
        XCTAssertTrue(love("Song", artist: "Artist", true).isForSameSong(as: love("SONG", artist: "artist", false)), "Case and direction shouldn't matter")
        XCTAssertFalse(love("Song", artist: "Artist").isForSameSong(as: love("Song", artist: "Other")), "Another artist is another song")
        XCTAssertFalse(love("Song", artist: "Artist").isForSameSong(as: love("Other", artist: "Artist")), "Another title is another song")
    }

    // MARK: - The last play scrobbled

    func testLastScrobbledIsKeptPerPlayerAndSurvivesANewQueue() {
        let queue = makeQueue()
        let music = PlayTracker.Earlier(identity: "music-song", startedAt: start, duration: 240)
        let spotify = PlayTracker.Earlier(identity: "spotify-song", startedAt: start.addingTimeInterval(-60), duration: nil)
        queue.noteScrobbled(music, player: "music")
        queue.noteScrobbled(spotify, player: "spotify")

        XCTAssertEqual(queue.lastScrobbled(player: "music"), music, "Music's last play should be kept")
        XCTAssertEqual(queue.lastScrobbled(player: "spotify"), spotify, "Spotify's last play should be kept apart from Music's")
        XCTAssertTrue(queue.isEmpty, "The last play scrobbled is not something waiting to be sent")

        let reopened = makeQueue()
        XCTAssertEqual(reopened.lastScrobbled(player: "music"), music, "The last play should survive a new queue on the same store")
        XCTAssertNil(reopened.lastScrobbled(player: "other"), "A player never noted should have nothing")
    }

    // MARK: - Persistence

    func testANewQueueSeesWhatTheFirstKeptForTheSameUserOnly() {
        let first = makeQueue()
        let play = scrobble()
        first.add(play)
        first.add(love("Song"))

        let again = makeQueue()
        XCTAssertEqual(again.nextBatch(), [play], "A new queue for the same user should see the waiting scrobble")
        XCTAssertEqual(again.nextLove, love("Song"), "A new queue for the same user should see the waiting heart")

        let other = makeQueue(user: "someone-else")
        XCTAssertTrue(other.isEmpty, "Another user's queue should see nothing of this one's")
    }

    func testDeleteAllEmptiesTheQueueAndTheStore() {
        let queue = makeQueue()
        queue.add(scrobble())
        queue.add(love())
        queue.noteScrobbled(PlayTracker.Earlier(identity: "x", startedAt: start, duration: nil), player: "music")

        queue.deleteAll()

        XCTAssertEqual(queue.contents, ScrobbleQueue.Contents(), "deleteAll should forget everything, the last play included")
        XCTAssertEqual(store.deletes, [user], "deleteAll should tell the store to delete this user's queue")
        XCTAssertNil(store.contents[user], "The store should hold nothing for the user")
    }

    func testCallsThatChangeNothingDoNotSave() {
        // Catches a save on every call: every scrobble saves, so a needless write costs
        let queue = makeQueue()
        let play = scrobble()
        let change = love()
        let earlier = PlayTracker.Earlier(identity: "x", startedAt: start, duration: 240)
        queue.add(play)
        queue.add(change)
        queue.noteScrobbled(earlier, player: "music")
        XCTAssertEqual(store.saves, 3, "Each call that changed something should save exactly once")

        queue.add(play)
        queue.add(change)
        queue.noteScrobbled(earlier, player: "music")
        _ = queue.nextBatch()
        queue.finished([scrobble("Never added")])
        queue.finished([])
        queue.finished(love("Never added"))

        XCTAssertEqual(store.saves, 3, "Calls that changed nothing should not save")
    }

}

/// `FileScrobbleQueueStore` on a temporary folder of its own
final class FileScrobbleQueueStoreTests: XCTestCase {

    private var directory: URL!
    private var store: FileScrobbleQueueStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScrobbleQueueTests-\(UUID().uuidString)", isDirectory: true)
        store = FileScrobbleQueueStore(directory: directory)
    }

    override func tearDown() {
        store?.synchronize()
        if let directory = directory {
            try? FileManager.default.removeItem(at: directory)
        }
        store = nil
        directory = nil
        super.tearDown()
    }

    private func sampleContents() -> ScrobbleQueue.Contents {
        let track = Scrobble.Track(title: "Song", artist: "Artist", album: "Album", albumArtist: "Various", trackNumber: 3, duration: 241)
        let bare = Scrobble.Track(title: "Other", artist: "Someone")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return ScrobbleQueue.Contents(
            scrobbles: [
                Scrobble(track: track, startedAt: start, source: "music"),
                Scrobble(track: bare, startedAt: start.addingTimeInterval(300), source: "spotify")
            ],
            loves: [ScrobbleQueue.LoveChange(title: "Song", artist: "Artist", loved: true)],
            lastScrobbled: ["music": PlayTracker.Earlier(identity: "abc", startedAt: start, duration: 241)]
        )
    }

    func testSaveThenLoadRoundTrips() {
        let contents = sampleContents()
        store.save(contents, user: "listener")
        store.synchronize()

        let loaded = store.load(user: "listener")
        XCTAssertEqual(loaded, contents, "Scrobbles, hearts and the last play should come back as they were saved")
        XCTAssertEqual(loaded?.scrobbles.first?.track.album, "Album", "The album should survive the file")
        XCTAssertEqual(loaded?.scrobbles.first?.track.duration, 241, "The duration should survive the file")
        XCTAssertEqual(loaded?.scrobbles.first?.timestamp, 1_800_000_000, "Dates should come back equal to the second")
    }

    func testLoadStraightAfterSaveSeesTheSave() {
        // Catches a load that reads the file without waiting for the writes queued before it
        let contents = sampleContents()
        store.save(contents, user: "listener")

        XCTAssertEqual(store.load(user: "listener"), contents, "A load should wait for every save before it")
    }

    func testAMissingFileLoadsAsNil() {
        XCTAssertNil(store.load(user: "nobody"), "A user with no file should load as nil")
    }

    func testTheFileIsPrivate() throws {
        store.save(sampleContents(), user: "listener")
        store.synchronize()

        let attributes = try FileManager.default.attributesOfItem(atPath: store.url(user: "listener").path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600, "The queue file should be readable by its owner only")
    }

    func testAUserNameBecomesASafeFileNameInTheFolder() {
        let file = store.url(user: "../Some.User/Name_-1")

        XCTAssertEqual(file.lastPathComponent, "queue-someusername_-1.json", "The name should be lower case ASCII letters, digits, - and _ only")
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL.path, directory.standardizedFileURL.path, "The file should be inside the store's folder")
        XCTAssertEqual(store.url(user: "./.."), directory.appendingPathComponent("queue-unnamed.json"), "A name with nothing usable left should still have a file of its own")
    }

    func testDeleteRemovesTheFile() {
        store.save(sampleContents(), user: "listener")
        store.delete(user: "listener")
        store.synchronize()

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(user: "listener").path), "delete should remove the file")
        XCTAssertNil(store.load(user: "listener"), "A deleted queue should load as nil")
    }

    func testACorruptFileLoadsAsNil() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a queue".utf8).write(to: store.url(user: "listener"))

        XCTAssertNil(store.load(user: "listener"), "A file that won't decode should be treated as empty")
    }

}
