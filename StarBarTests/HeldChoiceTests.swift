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

    // MARK: - When Music didn't answer and nothing is held

    /// What the menu bar would show for "B" with the stars on show `onShow`
    private func shown(_ choice: inout HeldChoice<Int>, answered: Int?, refusals: Int = 0, onShow: Int, isSameSong: Bool = true,
                       at seconds: TimeInterval) -> Int {
        return choice.value(answered: answered, trackID: "B", refusals: refusals, onShow: onShow, isSameSong: isSameSong,
                            otherwise: 0, now: at(seconds))
    }

    func testNoAnswerKeepsTheSongsStarsOnShow() {
        var choice = HeldChoice<Int>()
        XCTAssertEqual(shown(&choice, answered: 60, onShow: 0, at: 0), 60)
        XCTAssertEqual(shown(&choice, answered: nil, onShow: 60, at: 1), 60)
    }

    func testNoAnswerForANewSongIsOtherwise() {
        var choice = HeldChoice<Int>()
        XCTAssertEqual(shown(&choice, answered: 60, onShow: 0, at: 0), 60)
        XCTAssertEqual(shown(&choice, answered: nil, onShow: 60, isSameSong: false, at: 1), 0, "the stars on show are another song's")
        var other = HeldChoice<Int>()
        XCTAssertEqual(other.value(answered: 60, trackID: "A", refusals: 0, onShow: 0, isSameSong: true, otherwise: 0, now: start), 60)
        XCTAssertEqual(shown(&other, answered: nil, onShow: 60, at: 1), 0, "nor for another track")
    }

    func testARefusalSinceTheStarsWereShownBringsBackMusicsLastAnswer() {
        // The sixth review, 2026-10-30: Music's own songs kept a refused rating on show
        var choice = HeldChoice<Int>()
        XCTAssertEqual(shown(&choice, answered: 40, onShow: 0, at: 0), 40)
        choice.hold(80, for: "B", during: 3, refusals: 0, now: at(1))
        // Music refuses the write, and doesn't answer the read after it
        XCTAssertEqual(shown(&choice, answered: nil, refusals: 1, onShow: 80, at: 1.5), 40)
        XCTAssertFalse(choice.isHolding)
        // Nor the next: Music's answer stays on show
        XCTAssertEqual(shown(&choice, answered: nil, refusals: 1, onShow: 40, at: 2), 40)
    }

    func testARefusalOnceTheHoldHasRunOutStillBringsBackMusicsLastAnswer() {
        var choice = HeldChoice<Int>()
        XCTAssertEqual(shown(&choice, answered: 40, onShow: 0, at: 0), 40)
        choice.hold(80, for: "B", during: 3, refusals: 0, now: at(1))
        XCTAssertEqual(shown(&choice, answered: nil, refusals: 1, onShow: 80, at: 5), 40)
    }

    func testARefusalWithNoAnswerYetIsOtherwise() {
        var choice = HeldChoice<Int>()
        XCTAssertEqual(shown(&choice, answered: nil, onShow: 0, isSameSong: false, at: 0), 0)
        XCTAssertEqual(shown(&choice, answered: nil, refusals: 1, onShow: 80, at: 1), 0)
    }

    func testAnAnswerAfterARefusalIsShown() {
        var choice = HeldChoice<Int>()
        XCTAssertEqual(shown(&choice, answered: 40, onShow: 0, at: 0), 40)
        choice.hold(80, for: "B", during: 3, refusals: 0, now: at(1))
        XCTAssertEqual(shown(&choice, answered: 20, refusals: 1, onShow: 80, at: 1.5), 20, "Music's answer, which changed in Music")
        XCTAssertEqual(shown(&choice, answered: nil, refusals: 1, onShow: 20, at: 2), 20)
    }

}
