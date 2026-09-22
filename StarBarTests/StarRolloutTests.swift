import XCTest
@testable import StarBar

final class StarRolloutTests: XCTestCase {
    private let size = NSSize(width: 16, height: 16)

    func testRolloutStartsForStoppedIconOrAddButtonButNotOrdinarySongReplacement() {
        XCTAssertTrue(StarRollout.shouldRoll(wasStopped: true, isStopped: false,
                                             previousMode: .rating, mode: .rating))
        XCTAssertTrue(StarRollout.shouldRoll(wasStopped: false, isStopped: false,
                                             previousMode: .addToLibrary, mode: .rating))
        XCTAssertFalse(StarRollout.shouldRoll(wasStopped: false, isStopped: false,
                                              previousMode: .rating, mode: .rating))
        XCTAssertFalse(StarRollout.shouldRoll(wasStopped: false, isStopped: false,
                                              previousMode: .rating, mode: .addToLibrary))
        XCTAssertFalse(StarRollout.shouldRoll(wasStopped: false, isStopped: true,
                                              previousMode: .addToLibrary, mode: .rating))
    }

    func testAddButtonRevealUsesItsActualWidthAndEndsAtTheNormalRating() {
        let fromWidth = RatingControl.imageWidth(mode: .addToLibrary, starSize: size, spacing: 4) + 8
        let toWidth = RatingControl.imageWidth(mode: .rating, starSize: size, spacing: 4) + 8
        XCTAssertLessThan(fromWidth, toWidth)
        XCTAssertEqual(StarRollout.width(from: fromWidth, to: toWidth, progress: 0), fromWidth)
        XCTAssertEqual(StarRollout.width(from: fromWidth, to: toWidth, progress: 1), toWidth)
        for index in 0..<5 {
            let final = StarRollout.pose(index: index, starSize: size, spacing: 4,
                                         imageWidth: toWidth - 8, progress: 1)
            XCTAssertEqual(final.x, 4 + CGFloat(index) * 20, accuracy: 0.0001)
            XCTAssertEqual(final.angle, 0, accuracy: 0.0001)
        }
    }

    private func pose(_ index: Int, _ progress: Double) -> StarRollout.Pose {
        let width = StarRollout.width(from: 32, to: 132, progress: progress) - 8
        return StarRollout.pose(index: index, starSize: size, spacing: 4,
                                imageWidth: width, progress: progress)
    }

    func testEveryStarFinishesUprightInItsNormalSlot() {
        for index in 0..<5 {
            let final = pose(index, 1)
            XCTAssertEqual(final.x, 4 + CGFloat(index) * 20, accuracy: 0.0001)
            XCTAssertEqual(final.angle, 0, accuracy: 0.0001)
            XCTAssertEqual(final.opacity, 1, accuracy: 0.0001)
        }
    }

    func testStarsAppearInOrder() {
        XCTAssertGreaterThan(pose(0, 0.05).opacity, 0)
        XCTAssertEqual(pose(1, 0.05).opacity, 0)
        XCTAssertEqual(pose(4, 0.05).opacity, 0)
        XCTAssertGreaterThan(pose(4, 0.3).opacity, 0)
    }

    func testLeftmostStarArrivesBeforeRightmost() {
        XCTAssertEqual(pose(0, 0.8).angle, 0, accuracy: 0.0001)
        XCTAssertLessThan(pose(4, 0.8).angle, 0)
    }

    func testStarsRollLeftAndTurnAnticlockwiseWithoutReversing() {
        // Account for the status item's moving left edge: x is relative to its fixed right edge.
        for index in 0..<5 {
            var previousX: CGFloat = .greatestFiniteMagnitude
            var previousAngle: CGFloat = -.greatestFiniteMagnitude
            for step in 0...100 {
                let progress = Double(step) / 100
                let current = pose(index, progress)
                let width = StarRollout.width(from: 32, to: 132, progress: progress) - 8
                XCTAssertLessThanOrEqual(current.x - width, previousX + 0.0001)
                XCTAssertGreaterThanOrEqual(current.angle, previousAngle - 0.0001)
                previousX = current.x - width
                previousAngle = current.angle
            }
        }
    }

    func testWidthClampsAndGrowsWithoutOvershoot() {
        XCTAssertEqual(StarRollout.width(from: 32, to: 132, progress: -1), 32)
        XCTAssertEqual(StarRollout.width(from: 32, to: 132, progress: 2), 132)
        var previous: CGFloat = 32
        for step in 0...100 {
            let width = StarRollout.width(from: 32, to: 132, progress: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(width, previous)
            XCTAssertLessThanOrEqual(width, 132)
            previous = width
        }
    }

    func testHeartAppearsAfterStarsHaveStartedRolling() {
        XCTAssertEqual(StarRollout.heartOpacity(progress: 0.5), 0)
        XCTAssertGreaterThan(StarRollout.heartOpacity(progress: 0.8), 0)
        XCTAssertEqual(StarRollout.heartOpacity(progress: 1), 1)
    }

    func testRenderingPreservesRatingAndFavourite() {
        let control = RatingControl(rating: 70)
        control.updateFavorited(true)
        for progress in [0.0, 0.3, 0.7, 1.0] {
            let image = StarRollout.image(stars: control.stars, width: 124, progress: progress)
            XCTAssertTrue(image.isTemplate)
            XCTAssertNotNil(image.tiffRepresentation)
        }
        XCTAssertEqual(control.rating, 70)
        XCTAssertTrue(control.isFavorited)
        XCTAssertEqual(control.stars.stars.map { $0.style }, [.full, .full, .full, .half, .dot])
    }

    func testTrackChangeGapKeepsTheStripAndDoesNotStartAnotherRollout() {
        var stops = 0
        let playback = MenuBarPlaybackState(didStop: { stops += 1 })
        XCTAssertTrue(playback.isStopped)
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, musicIsRunning: true))

        // Repeated bare Stopped notifications cannot end the session, regardless of delay.
        for _ in 0..<5 {
            XCTAssertFalse(playback.update(hasTrack: false, isStopped: true, musicIsRunning: true))
            XCTAssertFalse(playback.isStopped)
            XCTAssertTrue(playback.isWaitingForTrack)
            XCTAssertFalse(playback.canInteract)
        }
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, musicIsRunning: true))
        XCTAssertFalse(playback.isStopped)
        XCTAssertFalse(playback.isWaitingForTrack)
        XCTAssertTrue(playback.canInteract)
        XCTAssertEqual(stops, 0)
    }

    func testPausedEmptyTrackDoesNotRevealFiveTemporaryDots() {
        let playback = MenuBarPlaybackState(didStop: { XCTFail("No session to end") })
        XCTAssertFalse(playback.update(hasTrack: false, isStopped: false, musicIsRunning: true))
        XCTAssertTrue(playback.isStopped)
        XCTAssertFalse(playback.canInteract)
    }

    func testPlaybackEndingRetainsDisplayUntilMusicQuits() {
        var stops = 0
        let playback = MenuBarPlaybackState(didStop: { stops += 1 })
        _ = playback.update(hasTrack: true, isStopped: false, musicIsRunning: true)
        _ = playback.update(hasTrack: false, isStopped: true, musicIsRunning: true)
        XCTAssertFalse(playback.isStopped)
        XCTAssertFalse(playback.canInteract)
        XCTAssertEqual(stops, 0)

        XCTAssertFalse(playback.update(hasTrack: false, isStopped: true, musicIsRunning: false))
        XCTAssertTrue(playback.isStopped)
        XCTAssertFalse(playback.isWaitingForTrack)
        XCTAssertFalse(playback.canInteract)
        XCTAssertEqual(stops, 1)
        _ = playback.update(hasTrack: false, isStopped: true, musicIsRunning: false)
        XCTAssertEqual(stops, 1, "Repeated quit updates must not reset twice")
    }

    func testMusicQuitRearmsEntranceForItsNextSession() {
        let playback = MenuBarPlaybackState(didStop: {})
        _ = playback.update(hasTrack: true, isStopped: false, musicIsRunning: true)
        // Even a retained track object cannot keep the display active after Music quits.
        XCTAssertFalse(playback.update(hasTrack: true, isStopped: false, musicIsRunning: false))
        XCTAssertTrue(playback.isStopped)
        XCTAssertFalse(playback.update(hasTrack: false, isStopped: true, musicIsRunning: true))
        XCTAssertTrue(playback.isStopped, "Opening Music without a song must keep the dot")
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, musicIsRunning: true))
        XCTAssertFalse(playback.isStopped)
        XCTAssertTrue(playback.canInteract)
    }

    func testPauseWithATrackKeepsTheCurrentPlaybackSession() {
        let playback = MenuBarPlaybackState(didStop: { XCTFail("Pause must not collapse") })
        _ = playback.update(hasTrack: true, isStopped: false, musicIsRunning: true)
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, musicIsRunning: true))
        XCTAssertFalse(playback.isStopped)
        XCTAssertTrue(playback.canInteract)
    }

    func testMissingTrackWhileStillPlayingPreservesTheLastRatingUntilReplacement() {
        let playback = MenuBarPlaybackState(didStop: { XCTFail("Missing data must not stop the session") })
        let control = RatingControl(rating: 70)
        control.updateFavorited(true)
        _ = playback.update(hasTrack: true, isStopped: false, musicIsRunning: true)

        if playback.update(hasTrack: false, isStopped: false, musicIsRunning: true) {
            control.update(rating: 0)
            control.updateFavorited(false)
        }
        XCTAssertEqual(control.rating, 70)
        XCTAssertTrue(control.isFavorited)
        XCTAssertFalse(playback.canInteract)

        if playback.update(hasTrack: true, isStopped: false, musicIsRunning: true) {
            control.update(rating: 30)
            control.updateFavorited(false)
        }
        XCTAssertEqual(control.rating, 30)
        XCTAssertFalse(control.isFavorited)
        XCTAssertTrue(playback.canInteract)
        XCTAssertFalse(playback.isStopped)
    }

    func testExplicitStopRetainsDisplayButDisablesActionsEvenWithATrackObject() {
        let playback = MenuBarPlaybackState(didStop: { XCTFail("Only quitting ends the session") })
        _ = playback.update(hasTrack: true, isStopped: false, musicIsRunning: true)
        XCTAssertFalse(playback.update(hasTrack: true, isStopped: true, musicIsRunning: true))
        XCTAssertFalse(playback.canInteract)
        XCTAssertFalse(playback.isStopped)
        XCTAssertTrue(playback.isWaitingForTrack)
    }
}
