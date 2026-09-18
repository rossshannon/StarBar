//
//  iTunesRadioStationRatingTests.swift
//  StarBarTests
//
//  The real rating path from iTunesRadioStation to a track, with a fake track in place of
//  Music. Beyond what the test host does at launch, nothing here sends Music an Apple
//  Event: the track is supplied, so the station
//  never asks Music which one is playing.
//

import XCTest
@testable import StarBar

final class iTunesRadioStationRatingTests: XCTestCase {

    /// One test, in one order, because the station is a singleton whose throttle window
    /// carries over between calls: the first write goes out at once, a second inside the
    /// window is held, and flushing (what quitting does) sends it.
    func testARatingReachesTheGivenTrackAndAHeldOneIsFlushed() {
        let track = FakeTrack(name: "Fake", rating: 0)
        let station = iTunesRadioStation.shared

        station.setRating(70, on: track)
        XCTAssertEqual(track.rating, 70, "the first rating is written at once")
        XCTAssertEqual(track.ratingsWritten, [70])

        station.setRating(90, on: track)
        XCTAssertEqual(track.ratingsWritten, [70], "a rating inside the window is held")

        station.flushHeldRatingWrite()
        XCTAssertEqual(track.ratingsWritten, [70, 90], "flushing sends the held rating")
        XCTAssertEqual(track.rating, 90)
    }

    /// Half stars survive the trip: Music stores them as multiples of 10
    func testHalfStarRatingsAreWrittenUnchanged() {
        let track = FakeTrack(name: "Half", rating: 0)
        // A fresh window is not guaranteed after the test above, so flush before reading
        iTunesRadioStation.shared.setRating(50, on: track)
        iTunesRadioStation.shared.flushHeldRatingWrite()

        XCTAssertEqual(track.rating, 50)
        XCTAssertEqual(track.userRating, 50, "written ratings read back as user ratings")
    }

}
