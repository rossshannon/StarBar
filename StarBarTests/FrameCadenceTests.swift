//
//  FrameCadenceTests.swift
//  StarBarTests
//
//  What the log says of how a menu bar transition was drawn, and the transitions' own time:
//  frames on time count in full, and a held main thread pauses the motion.
//

import XCTest
@testable import StarBar

final class FrameCadenceTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - The cadence

    func testFramesOnTimeAreNotLate() {
        var cadence = FrameCadence()
        for frame in 0...60 {
            cadence.frame(at: start.addingTimeInterval(Double(frame) / 60), animationTime: Double(frame) / 60)
        }
        XCTAssertEqual(cadence.frames, 61)
        XCTAssertEqual(cadence.lateFrames, 0)
        XCTAssertEqual(cadence.longestGap, 1.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(cadence.span, 1, accuracy: 1e-9)
    }

    func testAFasterDisplayIsNotLateEither() {
        var cadence = FrameCadence()
        for frame in 0...120 {
            cadence.frame(at: start.addingTimeInterval(Double(frame) / 120), animationTime: Double(frame) / 120)
        }
        XCTAssertEqual(cadence.lateFrames, 0)
    }

    func testAHeldMainThreadIsTheLongestGapAndSaysWhereTheMotionStood() {
        var cadence = FrameCadence()
        cadence.frame(at: start, animationTime: 0)
        cadence.frame(at: start.addingTimeInterval(1.0 / 60), animationTime: 1.0 / 60)
        cadence.frame(at: start.addingTimeInterval(2.0 / 60), animationTime: 2.0 / 60)
        // 300 ms with no frame, drawn as one step
        cadence.frame(at: start.addingTimeInterval(2.0 / 60 + 0.3), animationTime: 2.0 / 60 + SteppedTimeline.maxStep)
        cadence.frame(at: start.addingTimeInterval(3.0 / 60 + 0.3), animationTime: 3.0 / 60 + SteppedTimeline.maxStep)
        XCTAssertEqual(cadence.frames, 5)
        XCTAssertEqual(cadence.lateFrames, 1)
        XCTAssertEqual(cadence.longestGap, 0.3, accuracy: 1e-9)
        XCTAssertEqual(cadence.longestGapAt, 2.0 / 60, accuracy: 1e-9, "the frame that stayed on screen")
        XCTAssertEqual(cadence.summary, "5 frames in 0.350 s, 1 late, longest gap 300 ms at 0.03 s in")
    }

    func testOneMissedRefreshAtSixtyHertzIsLate() {
        var cadence = FrameCadence()
        cadence.frame(at: start, animationTime: 0)
        cadence.frame(at: start.addingTimeInterval(2.0 / 60), animationTime: 2.0 / 60)
        XCTAssertEqual(cadence.lateFrames, 1)
    }

    func testATransitionOfOneFrameHasNoGaps() {
        var cadence = FrameCadence()
        XCTAssertEqual(cadence.summary, "0 frames")
        cadence.frame(at: start, animationTime: 0)
        XCTAssertEqual(cadence.summary, "1 frame")
        XCTAssertEqual(cadence.longestGap, 0)
    }

    // MARK: - The transitions' time

    func testTheFirstFrameStartsTheTransitionHoweverLateItIs() {
        var timing = MenuBarAnimationTiming(duration: StarRollout.duration)
        XCTAssertEqual(timing.progress(at: start.addingTimeInterval(0.233)), 0)
        XCTAssertEqual(timing.elapsed, 0)
    }

    func testFramesOnTimeRunTheTransitionInItsOwnDuration() {
        var timing = MenuBarAnimationTiming(duration: StarRollout.duration)
        var progress = timing.progress(at: start)
        for frame in 1...60 {
            progress = timing.progress(at: start.addingTimeInterval(Double(frame) / 60))
        }
        XCTAssertEqual(progress, 1, accuracy: 1e-9)
    }

    func testAHeldMainThreadPausesTheRolloutRatherThanJumpingIt() {
        var timing = MenuBarAnimationTiming(duration: StarRollout.duration)
        var before = timing.progress(at: start)
        for frame in 1...12 {
            before = timing.progress(at: start.addingTimeInterval(Double(frame) / 60))
        }
        XCTAssertEqual(before, 0.2 / StarRollout.duration, accuracy: 1e-9)
        // Music's reads hold the main thread for 300 ms, a third of the rollout
        let after = timing.progress(at: start.addingTimeInterval(0.5))
        XCTAssertEqual(after - before, SteppedTimeline.maxStep / StarRollout.duration, accuracy: 1e-9,
                       "one step on from the frame that was drawn, not 0.3 s on")
        let next = timing.progress(at: start.addingTimeInterval(0.5 + 1.0 / 60))
        XCTAssertEqual(next - after, (1.0 / 60) / StarRollout.duration, accuracy: 1e-9, "then it carries on")
    }

    func testProgressStopsAtTheEnd() {
        var timing = MenuBarAnimationTiming(duration: StarRatingTransition.duration)
        _ = timing.progress(at: start)
        var progress = 0.0
        for frame in 1...60 {
            progress = timing.progress(at: start.addingTimeInterval(Double(frame) / 60))
        }
        XCTAssertEqual(progress, 1)
    }

}
