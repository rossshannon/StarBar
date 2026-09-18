//
//  RatingWriterTests.swift
//  StarBarTests
//
//  When ratings reach Music, against a fake clock and a recording write. No Music needed.
//

import XCTest
@testable import StarBar

final class RatingWriterTests: XCTestCase {

    private var clock: FakeClock!
    private var written: [(rating: Int, identity: Int?)]!
    private var writer: RatingWriter!

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        written = []
        writer = RatingWriter(interval: 2, clock: clock) { [unowned self] request in
            self.written.append((request.rating, request.identity))
        }
    }

    override func tearDown() {
        writer = nil
        super.tearDown()
    }

    private func rate(_ rating: Int, song: Int? = 1) {
        writer.rate(RatingWriter.Request(rating: rating, track: nil, identity: song, name: "song \(song ?? 0)"))
    }

    func testTheFirstRatingGoesAtOnce() {
        rate(60)

        XCTAssertEqual(written.map { $0.rating }, [60])
        XCTAssertNil(writer.heldRating)
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
    }

    func testARatingInsideTheWindowWaitsForItToClose() {
        rate(60)
        clock.advance(by: 0.5)
        rate(80)

        XCTAssertEqual(written.map { $0.rating }, [60], "the second rating is held")
        XCTAssertEqual(writer.heldRating, 80)
        XCTAssertEqual(clock.pendingOneShot?.seconds, 1.5, "the timer fires when the window closes")

        clock.advance(by: 1.5)
        clock.fireOneShot()
        XCTAssertEqual(written.map { $0.rating }, [60, 80])
        XCTAssertNil(writer.heldRating)
    }

    /// Holding a shortcut down sends one write, the last value, when the window closes
    func testOnlyTheNewestHeldRatingIsSent() {
        rate(20)
        for rating in [40, 60, 80, 100] {
            clock.advance(by: 0.3)
            rate(rating)
        }

        XCTAssertEqual(written.map { $0.rating }, [20])
        XCTAssertEqual(clock.pendingOneShots.count, 1, "one timer, not one per press")
        clock.fireOneShot()
        XCTAssertEqual(written.map { $0.rating }, [20, 100])
    }

    /// The bug the review flagged: rating song A, then song B within the window, lost A's rating
    func testAHeldRatingForAnotherSongIsSentRatherThanReplaced() {
        rate(60, song: 1)
        clock.advance(by: 0.5)
        rate(80, song: 1)       // held for song 1
        clock.advance(by: 0.5)
        rate(40, song: 2)       // the song changed under it

        XCTAssertEqual(written.map { $0.rating }, [60, 80], "song 1's held rating went out at once")
        XCTAssertEqual(written.last?.identity, 1)
        XCTAssertEqual(writer.heldRating, 40, "song 2's rating is now the held one")

        clock.fireOneShot()
        XCTAssertEqual(written.map { $0.rating }, [60, 80, 40])
        XCTAssertEqual(written.last?.identity, 2)
    }

    /// The immediate path too: a rating for a new song arriving just as the window closes
    /// (the hold timer has up to 200 ms of tolerance) must not discard the held one
    func testAHeldRatingForAnotherSongIsSentWhenTheNextRatingGoesAtOnce() {
        rate(60, song: 1)
        clock.advance(by: 0.5)
        rate(80, song: 1)       // held for song 1, timer due in 1.5 s
        clock.advance(by: 1.5)  // the window has closed but the timer has not fired yet
        rate(40, song: 2)

        XCTAssertEqual(written.map { $0.rating }, [60, 80, 40], "song 1's held rating, then song 2's at once")
        XCTAssertEqual(written.map { $0.identity }, [1, 1, 2])
        XCTAssertNil(writer.heldRating)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the old timer was cancelled")
    }

    func testAHeldRatingForTheSameSongIsReplaced() {
        rate(60, song: 1)
        clock.advance(by: 0.5)
        rate(80, song: 1)
        clock.advance(by: 0.5)
        rate(100, song: 1)

        XCTAssertEqual(written.map { $0.rating }, [60])
        clock.fireOneShot()
        XCTAssertEqual(written.map { $0.rating }, [60, 100])
    }

    /// Two ratings without an identity (the launch gap) count as the same song
    func testUnknownIdentitiesCountAsTheSameSong() {
        rate(60, song: nil)
        clock.advance(by: 0.5)
        rate(80, song: nil)
        clock.advance(by: 0.5)
        rate(100, song: nil)

        XCTAssertEqual(written.map { $0.rating }, [60])
        clock.fireOneShot()
        XCTAssertEqual(written.map { $0.rating }, [60, 100])
    }

    /// Quitting inside the window must not lose the last rating
    func testFlushSendsTheHeldRatingNow() {
        rate(60)
        clock.advance(by: 0.5)
        rate(80)

        writer.flush()

        XCTAssertEqual(written.map { $0.rating }, [60, 80])
        XCTAssertNil(writer.heldRating)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the timer was cancelled")
    }

    func testFlushWithNothingHeldDoesNothing() {
        rate(60)
        writer.flush()
        XCTAssertEqual(written.map { $0.rating }, [60])
    }

    /// A held write that has gone out starts a fresh window, so the next rating waits too
    func testTheWindowRestartsAfterAHeldWrite() {
        rate(60)
        clock.advance(by: 0.5)
        rate(80)
        clock.advance(by: 1.5)
        clock.fireOneShot()

        clock.advance(by: 0.5)
        rate(100)
        XCTAssertEqual(written.map { $0.rating }, [60, 80], "still inside the window the held write opened")
        XCTAssertEqual(writer.heldRating, 100)
    }

    func testAfterTheWindowTheNextRatingGoesAtOnce() {
        rate(60)
        clock.advance(by: 2)
        rate(80)

        XCTAssertEqual(written.map { $0.rating }, [60, 80])
        XCTAssertNil(writer.heldRating)
    }

}
