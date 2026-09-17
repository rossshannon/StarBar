//
//  RatingWriteThrottleTests.swift
//  StarBarTests
//
//  The timing rule only, with a fake clock. No Music, so these run anywhere.
//

import XCTest
@testable import StarBar

class RatingWriteThrottleTests: XCTestCase {

    let start = Date(timeIntervalSinceReferenceDate: 0)

    func testFirstRatingIsSentImmediately() {
        var throttle = RatingWriteThrottle(interval: 2.0)

        XCTAssertEqual(throttle.decide(at: start), .now)
    }

    func testSecondRatingInsideTheWindowIsHeldUntilItCloses() {
        var throttle = RatingWriteThrottle(interval: 2.0)
        _ = throttle.decide(at: start)

        let decision = throttle.decide(at: start.addingTimeInterval(0.5))

        XCTAssertEqual(decision, .hold(until: start.addingTimeInterval(2.0)))
    }

    func testEveryRatingInsideTheWindowIsHeldUntilTheSameMoment() {
        var throttle = RatingWriteThrottle(interval: 2.0)
        _ = throttle.decide(at: start)

        // Holding a rating shortcut down must not push the write further away each time
        let first = throttle.decide(at: start.addingTimeInterval(0.5))
        let second = throttle.decide(at: start.addingTimeInterval(1.0))
        let third = throttle.decide(at: start.addingTimeInterval(1.9))

        XCTAssertEqual(first, .hold(until: start.addingTimeInterval(2.0)))
        XCTAssertEqual(second, first)
        XCTAssertEqual(third, first)
    }

    func testRatingAfterTheWindowIsSentImmediately() {
        var throttle = RatingWriteThrottle(interval: 2.0)
        _ = throttle.decide(at: start)

        XCTAssertEqual(throttle.decide(at: start.addingTimeInterval(2.0)), .now)
    }

    func testAWriteSentAtTheEndOfTheWindowStartsAFreshWindow() {
        var throttle = RatingWriteThrottle(interval: 2.0)
        _ = throttle.decide(at: start)
        let held = start.addingTimeInterval(2.0)
        throttle.didWrite(at: held)

        // A rating chosen just after the held write still waits for the new window
        XCTAssertEqual(throttle.decide(at: held.addingTimeInterval(0.1)),
                       .hold(until: held.addingTimeInterval(2.0)))
        // …and one after it goes straight out
        XCTAssertEqual(throttle.decide(at: held.addingTimeInterval(2.0)), .now)
    }

    func testSeparateRatingsWellApartAreAllSentImmediately() {
        var throttle = RatingWriteThrottle(interval: 2.0)

        // The ordinary case: one click, then another a few seconds later. Neither waits.
        XCTAssertEqual(throttle.decide(at: start), .now)
        XCTAssertEqual(throttle.decide(at: start.addingTimeInterval(5.0)), .now)
        XCTAssertEqual(throttle.decide(at: start.addingTimeInterval(30.0)), .now)
    }

    func testLastWriteDateIsUnsetBeforeAnyRating() {
        let throttle = RatingWriteThrottle(interval: 2.0)

        XCTAssertNil(throttle.lastWriteDate)
    }

    func testHoldingDoesNotCountAsAWrite() {
        var throttle = RatingWriteThrottle(interval: 2.0)
        _ = throttle.decide(at: start)
        _ = throttle.decide(at: start.addingTimeInterval(0.5))

        // The held rating hasn't gone to Music yet, so the window still dates from the first
        XCTAssertEqual(throttle.lastWriteDate, start)
    }

}
