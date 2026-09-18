//
//  iTunesRadioStationRatingTests.swift
//  StarBarTests
//
//  The real rating path from iTunesRadioStation to a track, with a fake track in place of
//  Music. The station is a singleton whose throttle window carries over between calls, so
//  each test flushes what it holds and does not assume a fresh window.
//
//  These reach Music only as the test host already does: the station's init reads the
//  current track once, and a synthetic playerInfo notification runs the usual player
//  update. Nothing here writes to Music; the tracks rated are fakes.
//

import XCTest
@testable import StarBar

final class iTunesRadioStationRatingTests: XCTestCase {

    func testARatingReachesTheGivenTrackAndAHeldOneIsFlushed() {
        let track = FakeTrack(name: "Fake", rating: 0)
        let station = iTunesRadioStation.shared
        station.flushHeldRatingWrite()

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
        iTunesRadioStation.shared.setRating(50, on: track)
        iTunesRadioStation.shared.flushHeldRatingWrite()

        XCTAssertEqual(track.rating, 50)
        XCTAssertEqual(track.userRating, 50, "written ratings read back as user ratings")
    }

    /// The song a rating belongs to comes from Music's notification, so a rating held for
    /// one song is sent, not dropped, when the next song is rated
    func testARatingHeldForThePreviousSongIsSentWhenTheNextSongIsRated() {
        let first = FakeTrack(name: "First", persistentID: "0000000000000001", rating: 0)
        let second = FakeTrack(name: "Second", persistentID: "0000000000000002", rating: 0)
        let station = iTunesRadioStation.shared
        station.flushHeldRatingWrite()

        station.playInfoChanged(playerInfoNotification(name: "First", persistentID: 1))
        station.setRating(60, on: first)
        station.setRating(80, on: first)
        XCTAssertEqual(first.ratingsWritten.count, 1, "the second rating is held")

        station.playInfoChanged(playerInfoNotification(name: "Second", persistentID: 2))
        station.setRating(40, on: second)
        XCTAssertEqual(first.ratingsWritten.last, 80, "the held rating for the first song went out")

        station.flushHeldRatingWrite()
        XCTAssertEqual(second.ratingsWritten.last, 40)
        XCTAssertEqual(first.ratingsWritten.count, 2, "and the first song got nothing more")
    }

    /// What Music posts on a track change, with the keys the station decodes
    private func playerInfoNotification(name: String, persistentID: Int) -> Notification {
        return Notification(name: Notification.Name("com.apple.iTunes.playerInfo"), object: nil, userInfo: [
            "Name": name,
            "Artist": "Artist",
            "Album": "Album",
            "Persistent ID": persistentID,
            "Player State": "Playing",
        ])
    }

    /// The failed-event handler tells a property write from a read by the event's class and
    /// ID, which have to be read as attributes: the descriptor type is always 'aevt'
    func testFailedEventClassAndIDAreDecoded() {
        let descriptor = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(0x636F7265),   // 'core'
            eventID: AEEventID(0x73657464),             // 'setd'
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        let (eventClass, eventID) = iTunesRadioStation.classAndID(of: descriptor.aeDesc!)
        XCTAssertEqual(eventClass, "core")
        XCTAssertEqual(eventID, "setd")
        XCTAssertEqual(String(fourCharCode: 0x61657674), "aevt")
    }

}
