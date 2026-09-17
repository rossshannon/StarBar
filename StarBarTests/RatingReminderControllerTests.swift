//
//  RatingReminderControllerTests.swift
//  StarBarTests
//
//  The reminder's state over time: once per track, cancelled by a rating, a pause or the
//  setting. Drives the controller with a fake player, bell and clock, so no Music is needed.
//

import XCTest
@testable import StarBar

final class RatingReminderControllerTests: XCTestCase {

    private var control: RatingControl!
    private var bell: FakeBell!
    private var clock: FakeClock!
    private var player: RatingReminderController.PlayerSnapshot?
    private var isBusy = false
    /// Simulates Music too slow to answer: reads return nil although a track is playing
    private var readsFail = false
    private var fullReads = 0
    private var positionReads = 0
    private var controller: RatingReminderController!

    override func setUp() {
        super.setUp()
        control = RatingControl(rating: 0)
        bell = FakeBell()
        clock = FakeClock()
        isBusy = false
        readsFail = false
        fullReads = 0
        positionReads = 0
        player = nil
        controller = RatingReminderController(
            ratingControl: control,
            readPlayer: { [unowned self] in
                self.fullReads += 1
                return self.readsFail ? nil : self.player
            },
            readPosition: { [unowned self] in
                self.positionReads += 1
                return self.readsFail ? nil : self.player?.position
            },
            redraw: {},
            isBusy: { [unowned self] in self.isBusy },
            bell: bell,
            clock: clock
        )
    }

    override func tearDown() {
        controller = nil
        clock = nil
        bell = nil
        control = nil
        super.tearDown()
    }

    private func snapshot(track: String = "A", playing: Bool = true, position: TimeInterval, duration: TimeInterval = 600, rated: Bool = false) -> RatingReminderController.PlayerSnapshot {
        return RatingReminderController.PlayerSnapshot(trackID: track, isPlaying: playing, position: position, duration: duration, isRated: rated)
    }

    /// Update the player, then tell the controller, as a Music notification would
    private func update(_ snapshot: RatingReminderController.PlayerSnapshot?) {
        player = snapshot
        controller.playerDidUpdate(snapshot)
    }

    // MARK: - Scheduling

    func testChecksThePositionRegularlyThenRings() {
        update(snapshot(position: 500))
        XCTAssertEqual(bell.playCount, 0)
        XCTAssertEqual(clock.pendingOneShot?.seconds, RatingReminderController.positionCheckInterval)

        player = snapshot(position: 502)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 0)

        player = snapshot(position: 570.3)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 1)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testSeekingForwardsIsNoticedWithoutANotification() {
        update(snapshot(position: 100))
        player = snapshot(position: 590)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 1)
    }

    func testSeekingBackwardsKeepsWaiting() {
        update(snapshot(position: 500))
        player = snapshot(position: 300)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 0)
        XCTAssertNotNil(clock.pendingOneShot)
    }

    func testTrackRatedInMusicBetweenChecksDoesNotRing() {
        update(snapshot(position: 560))
        // Rated in Music itself, which may send no notification
        player = snapshot(position: 575, rated: true)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 0)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testCheckThatIsNotDueReadsOnlyThePosition() {
        update(snapshot(position: 500))
        player = snapshot(position: 502)
        clock.fireOneShot()
        XCTAssertEqual(positionReads, 1)
        XCTAssertEqual(fullReads, 0)
    }

    func testWaitShorterThanTheCheckIntervalIsUsed() {
        update(snapshot(position: 568.5))
        XCTAssertEqual(clock.pendingOneShot?.seconds ?? 0, 1.75, accuracy: 0.001)
    }

    func testOneSlowReadDoesNotCancelTheReminder() {
        update(snapshot(position: 560))
        readsFail = true
        clock.fireOneShot()
        XCTAssertNotNil(clock.pendingOneShot)

        readsFail = false
        player = snapshot(position: 575)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 1)
    }

    func testSlowConfirmReadIsRetried() {
        // The position read works, but the full read before ringing fails once
        var failNextFullRead = true
        controller = RatingReminderController(
            ratingControl: control,
            readPlayer: { [unowned self] in
                if failNextFullRead {
                    failNextFullRead = false
                    return nil
                }
                return self.player
            },
            readPosition: { [unowned self] in self.player?.position },
            redraw: {},
            bell: bell,
            clock: clock
        )
        controller.playerDidUpdate(snapshot(position: 560))
        player = snapshot(position: 575)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 0)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 1)
    }

    func testGivesUpAfterRepeatedFailedReads() {
        update(snapshot(position: 500))
        readsFail = true
        for _ in 0..<RatingReminderController.maximumFailedReads {
            clock.fireOneShot()
        }
        XCTAssertNil(clock.pendingOneShot)
    }

    func testConfirmReadThatFindsPlaybackPausedDoesNotRing() {
        update(snapshot(position: 560))
        // Paused, and the notification hasn't arrived yet
        player = snapshot(playing: false, position: 575)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 0)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testStalledPositionWaitsAtLeastASecond() {
        update(snapshot(position: 569.99))
        XCTAssertEqual(clock.pendingOneShot?.seconds, RatingReminderController.minimumWait)
    }

    func testRingsOnlyOncePerTrack() {
        update(snapshot(position: 580))
        update(snapshot(position: 585))
        update(snapshot(position: 590))
        XCTAssertEqual(bell.playCount, 1)
    }

    func testNextTrackGetsItsOwnReminder() {
        update(snapshot(track: "A", position: 580))
        update(snapshot(track: "B", position: 590))
        XCTAssertEqual(bell.playCount, 2)
    }

    func testTrackPlayedAgainLaterGetsAnotherReminder() {
        update(snapshot(track: "A", position: 580))
        update(snapshot(track: "B", position: 10, rated: true))
        update(snapshot(track: "A", position: 580))
        XCTAssertEqual(bell.playCount, 2)
    }

    func testPauseDuringTheSweepLetsItFinish() {
        update(snapshot(position: 580))
        update(snapshot(playing: false, position: 580))
        XCTAssertNotNil(control.sweepPosition)
        XCTAssertTrue(bell.isPlaying)
    }

    func testTrackChangeOrMusicQuittingDuringTheSweepLetsItFinish() {
        update(snapshot(track: "A", position: 580))
        update(snapshot(track: "B", position: 0))
        update(nil)
        XCTAssertNotNil(control.sweepPosition)
        XCTAssertTrue(bell.isPlaying)
    }

    func testPauseCancelsTheTimer() {
        update(snapshot(position: 500))
        update(snapshot(playing: false, position: 500))
        XCTAssertNil(clock.pendingOneShot)
    }

    func testMusicQuittingCancelsTheTimer() {
        update(snapshot(position: 500))
        update(nil)
        XCTAssertNil(clock.pendingOneShot)
    }

    // MARK: - Ratings and settings

    func testRatingBeforeTheReminderPointCancelsIt() {
        update(snapshot(position: 569))
        controller.userDidRate()
        XCTAssertNil(clock.pendingOneShot)

        // Music saves the rating 2 s later, so the next update can still say unrated
        update(snapshot(position: 571))
        XCTAssertEqual(bell.playCount, 0)
    }

    func testRatingDuringTheSweepStopsItAndTheBell() {
        update(snapshot(position: 580))
        XCTAssertNotNil(control.sweepPosition)
        controller.userDidRate()
        XCTAssertNil(control.sweepPosition)
        XCTAssertFalse(bell.isPlaying)
    }

    func testTurningTheSettingOffCancels() {
        update(snapshot(position: 500))
        controller.setEnabled(false)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testTurningTheSettingOnReadsThePlayer() {
        player = snapshot(position: 500)
        controller.setEnabled(true)
        XCTAssertNotNil(clock.pendingOneShot)
    }

    func testWaitsWhileTheUserDragsAcrossTheStars() {
        isBusy = true
        update(snapshot(position: 580))
        XCTAssertEqual(bell.playCount, 0)
        XCTAssertNil(control.sweepPosition)

        // Still dragging: the check reads only the position, next to the 60 Hz drag timer
        player = snapshot(position: 581)
        clock.fireOneShot()
        XCTAssertEqual(fullReads, 0)

        isBusy = false
        player = snapshot(position: 581)
        clock.fireOneShot()
        XCTAssertEqual(bell.playCount, 1)
    }

    // MARK: - Sweep

    func testSweepMovesWithTheClockThenClears() {
        update(snapshot(position: 580))
        XCTAssertEqual(control.sweepPosition, 0)

        var seen: [Int] = [0]
        while control.sweepPosition != nil {
            clock.advance(by: 1.0 / 60.0)
            clock.fireRepeating()
            if let position = control.sweepPosition, position != seen.last {
                seen.append(position)
            }
        }
        XCTAssertEqual(seen, StarSweep.positions)
        XCTAssertEqual(control.rating, 0)
    }

    func testStopSweepClearsTheStar() {
        update(snapshot(position: 580))
        controller.stopSweep()
        XCTAssertNil(control.sweepPosition)
    }

}

// MARK: - Fakes

private final class FakeBell: RatingReminderBell {
    private(set) var playCount = 0
    private(set) var isPlaying = false
    func play() {
        playCount += 1
        isPlaying = true
    }
    func stop() { isPlaying = false }
}
