//
//  RatingReminderTests.swift
//  StarBarTests
//
//  When the reminder to rate an unrated track fires, and the star sweep that goes with it.
//  Needs no Music app, so these run on any Mac.
//

import XCTest
@testable import StarBar

final class RatingReminderTests: XCTestCase {

    // MARK: - Reminder position

    func testLongTrackRemindsThirtySecondsBeforeTheEnd() {
        // 75% of 600 s is 450 s, but 30 s left is later
        XCTAssertEqual(RatingReminder.reminderPosition(duration: 600), 570)
    }

    func testShortTrackRemindsAtThreeQuarters() {
        // 30 s left of 60 s is halfway, so 75% is later
        XCTAssertEqual(RatingReminder.reminderPosition(duration: 60), 45)
    }

    func testRulesMeetAtTwoMinutes() {
        XCTAssertEqual(RatingReminder.reminderPosition(duration: 120), 90)
    }

    func testTrackShorterThanThirtySecondsStillRemindsAtThreeQuarters() {
        XCTAssertEqual(RatingReminder.reminderPosition(duration: 20), 15)
    }

    // MARK: - Decision

    func testBeforeTheReminderPointWaitsForTheRemainingTime() {
        let decision = RatingReminder.decision(position: 500, duration: 600, isRated: false, alreadyReminded: false)
        XCTAssertEqual(decision, .wait(seconds: 70))
    }

    func testAtTheReminderPointRemindsNow() {
        let decision = RatingReminder.decision(position: 570, duration: 600, isRated: false, alreadyReminded: false)
        XCTAssertEqual(decision, .remindNow)
    }

    func testBetweenTheReminderPointAndTheEndRemindsNow() {
        // For example, the user seeked forwards past the reminder point
        let decision = RatingReminder.decision(position: 590, duration: 600, isRated: false, alreadyReminded: false)
        XCTAssertEqual(decision, .remindNow)
    }

    func testRatedTrackNeverReminds() {
        XCTAssertEqual(RatingReminder.decision(position: 100, duration: 600, isRated: true, alreadyReminded: false), .never)
        XCTAssertEqual(RatingReminder.decision(position: 580, duration: 600, isRated: true, alreadyReminded: false), .never)
    }

    func testTrackRemindsOnlyOnce() {
        XCTAssertEqual(RatingReminder.decision(position: 100, duration: 600, isRated: false, alreadyReminded: true), .never)
        XCTAssertEqual(RatingReminder.decision(position: 580, duration: 600, isRated: false, alreadyReminded: true), .never)
    }

    func testAtOrPastTheEndNeverReminds() {
        XCTAssertEqual(RatingReminder.decision(position: 600, duration: 600, isRated: false, alreadyReminded: false), .never)
        XCTAssertEqual(RatingReminder.decision(position: 610, duration: 600, isRated: false, alreadyReminded: false), .never)
    }

    func testUnknownDurationNeverReminds() {
        // Streams report a duration of 0
        XCTAssertEqual(RatingReminder.decision(position: 10, duration: 0, isRated: false, alreadyReminded: false), .never)
    }

    // MARK: - Star sweep

    func testSweepGoesRightThenBack() {
        let positions = (0..<StarSweep.positions.count).map {
            StarSweep.position(atElapsed: (Double($0) + 0.5) * StarSweep.stepDuration)
        }
        XCTAssertEqual(positions, [0, 1, 2, 3, 4, 3, 2, 1, 0])
    }

    func testSweepLastsAboutHalfTheSound() {
        XCTAssertEqual(StarSweep.duration, 0.784, accuracy: 0.01)
    }

    func testSweepIsOverAfterItsDuration() {
        XCTAssertEqual(StarSweep.position(atElapsed: 0), 0)
        XCTAssertNil(StarSweep.position(atElapsed: StarSweep.duration))
        XCTAssertNil(StarSweep.position(atElapsed: -0.01))
    }

    // MARK: - Drawing

    func testSweepDrawsAnOutlineStarInPlaceOfOneDot() {
        let control = RatingControl(rating: 0)
        control.updateSweep(position: 2)
        XCTAssertEqual(control.stars.stars.map { $0.style }, [.dot, .dot, .outline, .dot, .dot])

        control.updateSweep(position: nil)
        XCTAssertEqual(control.stars.stars.map { $0.style }, [.dot, .dot, .dot, .dot, .dot])
    }

    func testSweepRedrawsWithoutChangingTheRating() {
        let control = RatingControl(rating: 0)
        var changes = 0
        control.didChange = { changes += 1 }

        control.updateSweep(position: 4)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(control.rating, 0)

        // Same position again: nothing to redraw
        control.updateSweep(position: 4)
        XCTAssertEqual(changes, 1)
    }

    func testSweepLeavesRatedStarsAlone() {
        let control = RatingControl(rating: 40)
        control.updateSweep(position: 0)
        XCTAssertEqual(control.stars.stars.map { $0.style }, [.full, .full, .dot, .dot, .dot])
    }

}
