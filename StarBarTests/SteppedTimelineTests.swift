//
//  SteppedTimelineTests.swift
//  StarBarTests
//
//  The strip's animation time: steps on time count in full, a stall counts only as a step.
//

import XCTest
@testable import StarBar

final class SteppedTimelineTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testStepsOnTimeAddUpToTheClocksTime() {
        var timeline = SteppedTimeline(start: start)
        for frame in 1...18 {
            timeline.step(at: start.addingTimeInterval(Double(frame) / 60))
        }
        XCTAssertEqual(timeline.elapsed, 0.3, accuracy: 1e-9)
    }

    func testAFrameOrTwoLateStillCountsInFull() {
        var timeline = SteppedTimeline(start: start)
        XCTAssertEqual(timeline.step(at: start.addingTimeInterval(2.0 / 60)), 2.0 / 60, accuracy: 1e-9)
    }

    func testAStallCountsAsOneLongStep() {
        var timeline = SteppedTimeline(start: start)
        timeline.step(at: start.addingTimeInterval(1.0 / 60))
        // 440 ms with no frame, then the frames carry on
        timeline.step(at: start.addingTimeInterval(1.0 / 60 + 0.44))
        XCTAssertEqual(timeline.elapsed, 1.0 / 60 + SteppedTimeline.maxStep, accuracy: 1e-9)
        timeline.step(at: start.addingTimeInterval(2.0 / 60 + 0.44))
        XCTAssertEqual(timeline.elapsed, 2.0 / 60 + SteppedTimeline.maxStep, accuracy: 1e-9, "from where it was drawn")
    }

    func testAStallBeforeTheFirstFrameStartsTheAnimationLate() {
        var timeline = SteppedTimeline(start: start)
        XCTAssertEqual(timeline.step(at: start.addingTimeInterval(0.44)), SteppedTimeline.maxStep, accuracy: 1e-9)
    }

    func testAClockThatGoesBackCountsNothing() {
        var timeline = SteppedTimeline(start: start)
        timeline.step(at: start.addingTimeInterval(0.01))
        timeline.step(at: start)
        XCTAssertEqual(timeline.elapsed, 0.01, accuracy: 1e-9)
    }

}
