//
//  HeldChoiceTests.swift
//  StarBarTests
//
//  A rating or heart the user just chose, held on screen over Music's reads. Pure, so it
//  runs anywhere.
//

import XCTest
@testable import StarBar

final class HeldChoiceTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private var held = HeldChoice<Int>()

    override func setUp() {
        super.setUp()
        held = HeldChoice<Int>()
        // 4 stars chosen over Music's 2
        held.hold(80, for: "A", during: 3, refusals: 0, now: start)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        return start.addingTimeInterval(seconds)
    }

    func testNothingHeldShowsMusicsAnswer() {
        var none = HeldChoice<Int>()
        XCTAssertEqual(none.value(answered: 40, trackID: "A", refusals: 0, now: start), 40)
        XCTAssertNil(none.value(answered: nil, trackID: "A", refusals: 0, now: start))
    }

    func testTheChoiceWinsOverAnOldAnswer() {
        XCTAssertEqual(held.value(answered: 40, trackID: "A", refusals: 0, now: at(1)), 80)
        XCTAssertTrue(held.isHolding)
    }

    func testMusicAgreeingEndsTheHold() {
        XCTAssertEqual(held.value(answered: 80, trackID: "A", refusals: 0, now: at(1)), 80)
        XCTAssertFalse(held.isHolding)
        // A change made in Music afterwards shows at once
        XCTAssertEqual(held.value(answered: 20, trackID: "A", refusals: 0, now: at(1.5)), 20)
    }

    func testNoAnswerNeitherConfirmsNorEndsTheHold() {
        // The third review: a slow read took the stars on screen for Music's answer, ended
        // the hold, and the next answer put the old stars back
        XCTAssertEqual(held.value(answered: nil, trackID: "A", refusals: 0, now: at(1)), 80)
        XCTAssertTrue(held.isHolding)
        XCTAssertEqual(held.value(answered: 40, trackID: "A", refusals: 0, now: at(2)), 80, "Music has yet to apply it")
    }

    func testTheHoldRunsOut() {
        XCTAssertEqual(held.value(answered: 40, trackID: "A", refusals: 0, now: at(3)), 40)
        XCTAssertFalse(held.isHolding)
    }

    func testNoAnswerAfterTheHoldRunsOutIsNoAnswer() {
        XCTAssertNil(held.value(answered: nil, trackID: "A", refusals: 0, now: at(3)))
        XCTAssertFalse(held.isHolding)
    }

    func testAnotherTrackEndsTheHold() {
        XCTAssertEqual(held.value(answered: 40, trackID: "B", refusals: 0, now: at(1)), 40)
        XCTAssertFalse(held.isHolding)
        XCTAssertEqual(held.value(answered: 40, trackID: "A", refusals: 0, now: at(1.5)), 40, "nor does it come back")
    }

    func testARefusedWriteEndsTheHold() {
        // Music's value is the true one again: the corrective read must show it
        XCTAssertEqual(held.value(answered: 40, trackID: "A", refusals: 1, now: at(0.5)), 40)
        XCTAssertFalse(held.isHolding)
    }

    func testDroppingEndsTheHold() {
        held.drop()
        XCTAssertEqual(held.value(answered: 40, trackID: "A", refusals: 0, now: at(1)), 40)
    }

    func testAHeartIsHeldTheSameWay() {
        var heart = HeldChoice<Bool>()
        heart.hold(true, for: "A", during: 2, refusals: 3, now: start)
        XCTAssertEqual(heart.value(answered: nil, trackID: "A", refusals: 3, now: at(0.5)), true)
        XCTAssertEqual(heart.value(answered: false, trackID: "A", refusals: 3, now: at(1)), true)
        XCTAssertEqual(heart.value(answered: true, trackID: "A", refusals: 3, now: at(1.5)), true)
        XCTAssertFalse(heart.isHolding)
    }

}
