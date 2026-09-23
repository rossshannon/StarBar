//
//  iTunesRadioStationRatingTests.swift
//  StarBarTests
//
//  The real rating path from iTunesRadioStation to a track, with fake tracks in place of
//  Music. Rating writes go only to fake tracks. Refresh tests can read Music if it is
//  running, but also work without it; they never write to the user's library.
//
//  The station and the player are singletons whose state carries over between tests, so
//  each test starts by flushing what is held and does not assume a fresh throttle window,
//  and `tearDown` clears what it set.
//
//  Under tests the station subscribes to none of Music's distributed notifications or
//  workspace events, so changing songs or editing the library during a run cannot add to or
//  starve the player updates these tests count. Library signals come from a private centre,
//  and both re-reads, after a library change and after a refused write, run on a
//  `FakeClock`: the tests never wait on the main run loop, so nothing else in the host app
//  can post a player update among the ones they count.
//

import XCTest
import Cocoa
import iTunesLibrary
@testable import StarBar

final class iTunesRadioStationRatingTests: XCTestCase {

    private let station = iTunesRadioStation.shared

    override func setUp() {
        super.setUp()
        station.flushHeldRatingWrite()
        station.cancelPendingRereads()
    }

    override func tearDown() {
        station.flushHeldRatingWrite()
        // A re-read left waiting would otherwise run in the next test, or count as pending there
        station.cancelPendingRereads()
        station.rereadClock = RunLoopClock()
        // Leave no fake song behind as "what is playing" for the rest of the run
        iTunesPlayer.shared.update(nil, broadcast: false)
        super.tearDown()
    }

    /// Make `track` the song playing, as the rating shortcuts do before each press: the
    /// record is replaced, and nothing is broadcast
    private func play(_ track: FakeTrack) {
        iTunesPlayer.shared.update(track, broadcast: false)
    }

    func testARatingReachesTheGivenTrackAndAHeldOneIsFlushed() {
        let track = FakeTrack(name: "Fake", rating: 0)
        play(track)

        station.setRating(70, on: track)
        station.setRating(90, on: track)
        // Whether the window was open already decides if 70 went at once or was replaced;
        // either way at most one write has happened and 90 is still waiting
        XCTAssertLessThanOrEqual(track.ratingsWritten.count, 1)
        XCTAssertNotEqual(track.rating, 90, "the second rating is held")

        station.flushHeldRatingWrite()
        XCTAssertEqual(track.ratingsWritten.last, 90, "flushing sends the held rating")
        XCTAssertEqual(track.rating, 90)
    }

    /// Half stars survive the trip: Music stores them as multiples of 10
    func testHalfStarRatingsAreWrittenUnchanged() {
        let track = FakeTrack(name: "Half", rating: 0)
        play(track)
        station.setRating(50, on: track)
        station.flushHeldRatingWrite()

        XCTAssertEqual(track.rating, 50)
        XCTAssertEqual(track.userRating, 50, "written ratings read back as user ratings")
    }

    /// A rating held for one song is sent, not dropped, when the next song is rated. The song
    /// is told from the player record alone, with **no notification from Music in between**:
    /// that is what a rating shortcut pressed straight after a track change looks like, and
    /// an identity taken from the last notification lost the held rating here.
    func testARatingHeldForThePreviousSongIsSentWhenTheNextSongIsRated() {
        let first = FakeTrack(name: "First", persistentID: "00000000000000A1", rating: 0)
        let second = FakeTrack(name: "Second", persistentID: "00000000000000B2", rating: 0)

        play(first)
        station.setRating(60, on: first)
        station.setRating(80, on: first)
        XCTAssertNotEqual(first.rating, 80, "the second rating is held")

        play(second)
        station.setRating(40, on: second)
        XCTAssertEqual(first.ratingsWritten.last, 80, "the held rating for the first song went out")
        XCTAssertNotEqual(second.rating, 40, "and the new one is held in its place")

        station.flushHeldRatingWrite()
        XCTAssertEqual(second.ratingsWritten.last, 40)
        XCTAssertEqual(first.ratingsWritten.last, 80, "the first song got nothing more")
    }

    /// The shortcuts replace the player record on every press. A new record for the same
    /// song must still count as the same song, or a held-down key would send every repeat.
    func testANewRecordForTheSameSongStillReplacesTheHeldRating() {
        let track = FakeTrack(name: "Same", persistentID: "00000000000000C3", rating: 0)

        play(track)
        station.setRating(20, on: track)
        let writtenBeforeTheBurst = track.ratingsWritten.count
        for rating in [40, 60, 80] {
            play(track)     // a fresh record, as each key repeat makes
            station.setRating(rating, on: track)
        }
        XCTAssertEqual(track.ratingsWritten.count, writtenBeforeTheBurst, "the repeats were held, not sent one by one")

        station.flushHeldRatingWrite()
        XCTAssertEqual(track.ratingsWritten.last, 80)
    }

    func testSongIdentityPrefersThePersistentIDAndFallsBackToTheNames() throws {
        let decoder = JSONDecoder()
        let withID = try decoder.decode(PlayInfo.self, from: Data(#"{"name":"A","artist":"B","album":"C","persistentID":42}"#.utf8))
        let withoutID = try decoder.decode(PlayInfo.self, from: Data(#"{"name":"A","artist":"B","album":"C"}"#.utf8))
        let unnamed = try decoder.decode(PlayInfo.self, from: Data(#"{"artist":"B"}"#.utf8))

        XCTAssertEqual(withID.songIdentity, "42")
        XCTAssertEqual(withoutID.songIdentity, "A|B|C")
        XCTAssertNil(unnamed.songIdentity)
    }

    // MARK: - Library changes and deleted rating targets

    /// Exercise the subscriptions through a private centre, never the system-wide one.
    /// As with the refused-write tests below, refreshes may read Music but never write it.
    func testDocumentedLibraryChangeRefreshesTheCachedPlayer() {
        let center = NotificationCenter()
        station.observeLibraryChanges(in: center)
        defer { center.removeObserver(station) }
        let clock = useFakeRereadClock()
        let track = FakeTrack(name: "Deleted", rating: 20)
        play(track)
        let original = iTunesPlayer.shared.playing
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        track.isPresent = false
        center.post(name: .ITLibraryDidChange, object: nil, userInfo: ["media-domains": 1])
        XCTAssertEqual(updates, 0, "the notification waits for the settling interval")
        XCTAssertEqual(clock.pendingOneShot?.seconds, iTunesRadioStation.libraryChangedReadDelay)
        clock.fireAllOneShots()

        XCTAssertEqual(updates, 1)
        XCTAssertFalse(iTunesPlayer.shared.playing === original, "cached library answers are replaced")
        XCTAssertTrue(track.ratingsWritten.isEmpty)
    }

    func testLibraryNotificationBurstCoalescesAndLaterLegacySignalStillRefreshes() {
        let center = NotificationCenter()
        station.observeLibraryChanges(in: center)
        defer { center.removeObserver(station) }
        let clock = useFakeRereadClock()
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        let legacy = Notification.Name("com.apple.iTunes.libraryChanged")

        for _ in 0..<3 {
            center.post(name: .ITLibraryDidChange, object: nil)
            center.post(name: legacy, object: nil)
        }
        XCTAssertEqual(updates, 0, "nothing is read while the burst is still arriving")
        XCTAssertEqual(clock.pendingOneShots.count, 1, "the burst leaves one re-read waiting")
        // Fire them all: a re-read left over from earlier in the burst would add an update
        clock.fireAllOneShots()
        XCTAssertEqual(updates, 1, "both names share one coalesced refresh")

        center.post(name: legacy, object: nil)
        clock.fireAllOneShots()
        XCTAssertEqual(updates, 2, "the later signal reconciles a state that settled late")
    }

    func testLibraryRefreshWaitsForAHeldRatingThenRuns() {
        let center = NotificationCenter()
        station.observeLibraryChanges(in: center)
        defer { center.removeObserver(station) }
        let clock = useFakeRereadClock()
        let track = FakeTrack(name: "Held during library change", rating: 0)
        play(track)
        station.setRating(20, on: track)
        station.setRating(80, on: track)
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        center.post(name: .ITLibraryDidChange, object: nil)
        clock.fireAllOneShots()
        XCTAssertEqual(updates, 0, "Music cannot yet report the held rating")
        XCTAssertEqual(clock.pendingOneShot?.seconds, iTunesRadioStation.ratingSaveDelay, "the read waits out the write window instead")

        station.flushHeldRatingWrite()
        clock.fireAllOneShots()
        XCTAssertEqual(track.ratingsWritten.last, 80)
        XCTAssertEqual(updates, 1, "the deferred refresh is not lost")
    }

    func testCommittingStaleStarsRefreshesInsteadOfRatingTheDeletedTrack() throws {
        let menu = try XCTUnwrap((NSApp.delegate as? AppDelegate)?.menuBarRatingControl)
        let track = FakeTrack(name: "Deleted before click", rating: 20)
        play(track)
        XCTAssertNotNil(iTunesPlayer.shared.playing?.ratingTrack, "cache the original rating target")
        menu.ratingControl.update(rating: 20)
        track.isPresent = false
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        menu.ratingControl.commit(rating: 80)

        XCTAssertEqual(updates, 1, "a rejected click refreshes without waiting for a library signal")
        XCTAssertEqual(track.rating, 20)
        XCTAssertTrue(track.ratingsWritten.isEmpty)
    }

    func testCommittingStaleStarsRefreshesWhenOnlyTheLibraryCopyWasDeleted() throws {
        let menu = try XCTUnwrap((NSApp.delegate as? AppDelegate)?.menuBarRatingControl)
        let playing = FakeTrack(name: "Still playing", persistentID: "00000000000000A1")
        let libraryCopy = FakeTrack(name: "Library copy", persistentID: "00000000000000B2", rating: 20)
        play(playing)
        iTunesPlayer.shared.playing?.didAddToLibrary(libraryCopy)
        menu.ratingControl.update(rating: 20)
        libraryCopy.isPresent = false
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        menu.ratingControl.commit(rating: 80)
        station.flushHeldRatingWrite()

        XCTAssertEqual(updates, 1, "the playing object can survive its rating target")
        XCTAssertTrue(playing.ratingsWritten.isEmpty)
        XCTAssertTrue(libraryCopy.ratingsWritten.isEmpty)
    }

    // MARK: - A refused write

    /// Only a refused property write schedules the re-read, and two refusals mean one read
    func testOnlyARefusedWriteSchedulesOneRereadOfThePlayer() {
        let clock = useFakeRereadClock()
        let error = NSError(domain: NSOSStatusErrorDomain, code: -54, userInfo: nil)
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = station.eventDidFail(appleEvent(eventClass: 0x636F7265, eventID: 0x67657464).aeDesc!, withError: error)   // core/getd
        XCTAssertFalse(station.hasPendingRereadAfterRefusedWrite, "a failed read changes nothing")
        XCTAssertTrue(clock.pendingOneShots.isEmpty)

        _ = station.eventDidFail(appleEvent(eventClass: 0x636F7265, eventID: 0x73657464).aeDesc!, withError: error)   // core/setd
        _ = station.eventDidFail(appleEvent(eventClass: 0x636F7265, eventID: 0x73657464).aeDesc!, withError: error)
        XCTAssertTrue(station.hasPendingRereadAfterRefusedWrite, "a refused write schedules a re-read")
        XCTAssertEqual(clock.pendingOneShots.count, 1, "two refusals leave one re-read waiting")
        XCTAssertEqual(clock.pendingOneShot?.seconds, iTunesRadioStation.refusedWriteRereadDelay)
        XCTAssertEqual(updates, 0, "and it has not run yet")

        // Fire them all: a re-read the second refusal failed to replace would add an update
        clock.fireAllOneShots()
        XCTAssertFalse(station.hasPendingRereadAfterRefusedWrite)
        // Each re-read ends in one player update. Two would mean the refusals were not
        // coalesced.
        XCTAssertEqual(updates, 1, "two refusals, one re-read")
    }

    /// While a rating is held the re-read waits for it: reading first would repaint the stars
    /// with a value Music is about to replace, and nothing afterwards would correct them
    func testTheRereadWaitsWhileARatingIsHeld() {
        let clock = useFakeRereadClock()
        let track = FakeTrack(name: "Held", rating: 0)
        play(track)
        station.setRating(60, on: track)
        station.setRating(80, on: track)    // held
        var updates = 0
        let observer = NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { _ in updates += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let error = NSError(domain: NSOSStatusErrorDomain, code: -54, userInfo: nil)
        _ = station.eventDidFail(appleEvent(eventClass: 0x636F7265, eventID: 0x73657464).aeDesc!, withError: error)
        clock.fireAllOneShots()

        XCTAssertEqual(updates, 0, "no re-read while the rating is held")
        XCTAssertTrue(station.hasPendingRereadAfterRefusedWrite, "it is waiting for the held rating instead")
        XCTAssertEqual(clock.pendingOneShot?.seconds, iTunesRadioStation.ratingSaveDelay, "for the rest of the write window")

        station.flushHeldRatingWrite()
        clock.fireAllOneShots()
        XCTAssertEqual(track.ratingsWritten.last, 80)
        XCTAssertEqual(updates, 1, "the deferred re-read is not lost")
        XCTAssertFalse(station.hasPendingRereadAfterRefusedWrite)
    }

    /// The failed-event handler tells a property write from a read by the event's class and
    /// ID, which have to be read as attributes: the descriptor type is always 'aevt'
    func testFailedEventClassAndIDAreDecoded() {
        let descriptor = appleEvent(eventClass: 0x636F7265, eventID: 0x73657464)   // 'core' / 'setd'
        let (eventClass, eventID) = iTunesRadioStation.classAndID(of: descriptor.aeDesc!)
        XCTAssertEqual(eventClass, "core")
        XCTAssertEqual(eventID, "setd")
        XCTAssertEqual(String(fourCharCode: 0x61657674), "aevt")
    }

    // MARK: - Helpers

    /// Time the station's re-reads by hand. `tearDown` puts the real clock back.
    private func useFakeRereadClock() -> FakeClock {
        let clock = FakeClock()
        station.rereadClock = clock
        return clock
    }

    private func appleEvent(eventClass: UInt32, eventID: UInt32) -> NSAppleEventDescriptor {
        return NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(eventClass),
            eventID: AEEventID(eventID),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

}
