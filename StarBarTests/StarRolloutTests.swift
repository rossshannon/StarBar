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

    func testSpotifyHeartFadesOutCompletelyBeforeTheRolloutStarts() {
        XCTAssertEqual(StarRollout.outgoingHeartOpacity(progress: 0), 1)
        XCTAssertEqual(StarRollout.outgoingHeartOpacity(progress: 1), 0)
        XCTAssertLessThan(StarRollout.outgoingHeartOpacity(progress: 0.6), StarRollout.outgoingHeartOpacity(progress: 0.3))
        // Music's heart is still hidden when the rollout begins, so the two never show together
        XCTAssertEqual(StarRollout.heartOpacity(progress: 0), 0)
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
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, isRunning: true))

        // Repeated bare Stopped notifications cannot end the session, regardless of delay.
        for _ in 0..<5 {
            XCTAssertFalse(playback.update(hasTrack: false, isStopped: true, isRunning: true))
            XCTAssertFalse(playback.isStopped)
            XCTAssertTrue(playback.isWaitingForTrack)
            XCTAssertFalse(playback.canInteract)
        }
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, isRunning: true))
        XCTAssertFalse(playback.isStopped)
        XCTAssertFalse(playback.isWaitingForTrack)
        XCTAssertTrue(playback.canInteract)
        XCTAssertEqual(stops, 0)
    }

    func testPausedEmptyTrackDoesNotRevealFiveTemporaryDots() {
        let playback = MenuBarPlaybackState(didStop: { XCTFail("No session to end") })
        XCTAssertFalse(playback.update(hasTrack: false, isStopped: false, isRunning: true))
        XCTAssertTrue(playback.isStopped)
        XCTAssertFalse(playback.canInteract)
    }

    func testPlaybackEndingRetainsDisplayUntilMusicQuits() {
        var stops = 0
        let playback = MenuBarPlaybackState(didStop: { stops += 1 })
        _ = playback.update(hasTrack: true, isStopped: false, isRunning: true)
        _ = playback.update(hasTrack: false, isStopped: true, isRunning: true)
        XCTAssertFalse(playback.isStopped)
        XCTAssertFalse(playback.canInteract)
        XCTAssertEqual(stops, 0)

        XCTAssertFalse(playback.update(hasTrack: false, isStopped: true, isRunning: false))
        XCTAssertTrue(playback.isStopped)
        XCTAssertFalse(playback.isWaitingForTrack)
        XCTAssertFalse(playback.canInteract)
        XCTAssertEqual(stops, 1)
        _ = playback.update(hasTrack: false, isStopped: true, isRunning: false)
        XCTAssertEqual(stops, 1, "Repeated quit updates must not reset twice")
    }

    func testMusicQuitRearmsEntranceForItsNextSession() {
        let playback = MenuBarPlaybackState(didStop: {})
        _ = playback.update(hasTrack: true, isStopped: false, isRunning: true)
        // Even a retained track object cannot keep the display active after Music quits.
        XCTAssertFalse(playback.update(hasTrack: true, isStopped: false, isRunning: false))
        XCTAssertTrue(playback.isStopped)
        XCTAssertFalse(playback.update(hasTrack: false, isStopped: true, isRunning: true))
        XCTAssertTrue(playback.isStopped, "Opening Music without a song must keep the dot")
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, isRunning: true))
        XCTAssertFalse(playback.isStopped)
        XCTAssertTrue(playback.canInteract)
    }

    func testPauseWithATrackKeepsTheCurrentPlaybackSession() {
        let playback = MenuBarPlaybackState(didStop: { XCTFail("Pause must not collapse") })
        _ = playback.update(hasTrack: true, isStopped: false, isRunning: true)
        XCTAssertTrue(playback.update(hasTrack: true, isStopped: false, isRunning: true))
        XCTAssertFalse(playback.isStopped)
        XCTAssertTrue(playback.canInteract)
    }

    func testMissingTrackWhileStillPlayingPreservesTheLastRatingUntilReplacement() {
        let playback = MenuBarPlaybackState(didStop: { XCTFail("Missing data must not stop the session") })
        let control = RatingControl(rating: 70)
        control.updateFavorited(true)
        _ = playback.update(hasTrack: true, isStopped: false, isRunning: true)

        if playback.update(hasTrack: false, isStopped: false, isRunning: true) {
            control.update(rating: 0)
            control.updateFavorited(false)
        }
        XCTAssertEqual(control.rating, 70)
        XCTAssertTrue(control.isFavorited)
        XCTAssertFalse(playback.canInteract)

        if playback.update(hasTrack: true, isStopped: false, isRunning: true) {
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
        _ = playback.update(hasTrack: true, isStopped: false, isRunning: true)
        XCTAssertFalse(playback.update(hasTrack: true, isStopped: true, isRunning: true))
        XCTAssertFalse(playback.canInteract)
        XCTAssertFalse(playback.isStopped)
        XCTAssertTrue(playback.isWaitingForTrack)
    }

    // MARK: - The wait for the widened item

    func testStarsWaitForTheMenuBarToPlaceTheWidenedItem() {
        var schedule = StarRollout.Schedule()
        let settle = StarRollout.settleDuration
        XCTAssertGreaterThanOrEqual(settle, 8.0 / 60.0, "the longest slide of a widened item measured, eight frames")
        XCTAssertEqual(schedule.progress(elapsed: 0, sinceWidening: 0), 0)
        XCTAssertEqual(schedule.progress(elapsed: settle / 2, sinceWidening: settle / 2), 0, "the item is still being slid into place")
        // The roll starts on the first frame after the wait, and from nothing
        XCTAssertEqual(schedule.progress(elapsed: settle, sinceWidening: settle), 0)
        XCTAssertEqual(schedule.progress(elapsed: settle + 0.5, sinceWidening: settle + 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(schedule.progress(elapsed: settle + 1, sinceWidening: settle + 1), 1, accuracy: 1e-9)
        XCTAssertEqual(schedule.progress(elapsed: 2, sinceWidening: 2), 1, "and stops at its end")
    }

    func testAFirstFrameThatWasLateAnywayWaitsNoLonger() {
        // A new song's first frame comes after the Music reads it sets off, by which time the
        // menu bar has long since put the item in its place
        var schedule = StarRollout.Schedule()
        XCTAssertEqual(schedule.progress(elapsed: 0, sinceWidening: 0.25), 0)
        XCTAssertEqual(schedule.progress(elapsed: 0.25, sinceWidening: 0.5), 0.25, accuracy: 1e-9)
    }

    func testNothingRollsBeforeTheItemHasWidened() {
        // From Spotify's heart the item widens only once the heart has faded out of it
        var schedule = StarRollout.Schedule()
        let settle = StarRollout.settleDuration
        XCTAssertEqual(schedule.progress(elapsed: 0.1, sinceWidening: nil), 0)
        XCTAssertEqual(schedule.progress(elapsed: 0.2, sinceWidening: 0), 0)
        XCTAssertEqual(schedule.progress(elapsed: 0.2 + settle / 2, sinceWidening: settle / 2), 0)
        XCTAssertEqual(schedule.progress(elapsed: 0.2 + settle, sinceWidening: settle), 0)
        XCTAssertEqual(schedule.progress(elapsed: 0.2 + settle + 0.5, sinceWidening: settle + 0.5), 0.5, accuracy: 1e-9)
    }

    func testTheWaitIsTimeOnTheClockHoweverLittleWasDrawn() {
        // A held main thread counts for little of the transition's own time, but the menu bar
        // slides the item all the same, so the wait is over when the thread is free again
        var schedule = StarRollout.Schedule()
        XCTAssertEqual(schedule.progress(elapsed: 0, sinceWidening: 0), 0)
        XCTAssertEqual(schedule.progress(elapsed: SteppedTimeline.maxStep, sinceWidening: 0.4), 0)
        XCTAssertEqual(schedule.progress(elapsed: SteppedTimeline.maxStep + 0.5, sinceWidening: 0.9), 0.5, accuracy: 1e-9)
    }

    // MARK: - The rollout as the menu bar draws it

    /// A menu bar control on a fake clock that has just been given its first song, so the
    /// stars are about to roll in from the stopped dot. Reduce Motion is set off for the test
    /// rather than read from the machine, since CI's runners have it on and it skips the rollout.
    private func startRollout() -> (clock: FakeClock, menu: MenuBarRatingControl) {
        let readReduceMotion = MenuBarRatingControl.reduceMotion
        MenuBarRatingControl.reduceMotion = { false }
        addTeardownBlock { MenuBarRatingControl.reduceMotion = readReduceMotion }
        let clock = FakeClock()
        let menu = MenuBarRatingControl(widthClock: clock)
        XCTAssertFalse(menu.isAnimating)
        let track = FakeTrack(name: "StarBar rollout \(UUID().uuidString)", rating: 80)
        menu.applyTrackDisplay(PlayingTrack(track: track), isStopped: false, musicIsRunning: true)
        XCTAssertEqual(menu.ratingControl.mode, .rating)
        return (clock, menu)
    }

    private func isBlank(_ image: NSImage?) throws -> Bool {
        let data = try XCTUnwrap(XCTUnwrap(image).tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        return !(0..<bitmap.pixelsWide).contains { x in
            (0..<bitmap.pixelsHigh).contains { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
    }

    func testTheWidenedItemIsLeftEmptyUntilItHasSettledAndThenTheStarsRoll() throws {
        let (clock, menu) = startRollout()
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        let layout = MenuBarStripLayout(starSize: menu.ratingControl.starSize, spacing: menu.ratingControl.spacing)
        XCTAssertEqual(menu.statusItem.length, layout.statusItemWidth, "the item widens in one step, before anything is drawn in it")
        XCTAssertTrue(menu.isAnimating, "Music's repeats wait from here")

        // Frames that come at once, as they do when nothing reads Music first
        clock.fireRepeating()
        clock.runFrames(for: StarRollout.settleDuration - 2.0 / 60.0)
        XCTAssertTrue(try isBlank(menu.statusItem.button?.image), "nothing shows while the menu bar slides the wider item into place")

        clock.runFrames(for: 6.0 / 60.0)
        XCTAssertFalse(try isBlank(menu.statusItem.button?.image), "the first star is on its way")
        XCTAssertTrue(menu.isAnimating)

        clock.runFrames(for: StarRollout.duration)
        XCTAssertFalse(menu.isAnimating, "the roll takes its second and no more")
        XCTAssertEqual(menu.statusItem.length, layout.statusItemWidth)
    }

    func testAFirstFrameHeldUpByMusicReadsStartsTheRollWithoutASecondWait() throws {
        let (clock, menu) = startRollout()
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        clock.advance(by: 0.25)
        clock.fireRepeating()
        XCTAssertTrue(try isBlank(menu.statusItem.button?.image), "the roll starts from nothing, at its first frame")
        clock.runFrames(for: 3.0 / 60.0)
        XCTAssertFalse(try isBlank(menu.statusItem.button?.image))
    }

    func testAHeldMainThreadPausesTheRollRatherThanFinishingIt() throws {
        let (clock, menu) = startRollout()
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        clock.advance(by: 0.25)
        clock.fireRepeating()
        clock.runFrames(for: 0.3)

        // Music reads hold the main thread for longer than the rest of the roll takes. On
        // the wall clock the stars would now be home, having been seen a third of the way
        clock.advance(by: StarRollout.duration)
        clock.fireRepeating()
        XCTAssertTrue(menu.isAnimating, "the stars carry on from where they were last drawn")

        clock.runFrames(for: StarRollout.duration - 0.3 - SteppedTimeline.maxStep - 0.05)
        XCTAssertTrue(menu.isAnimating, "and still have a twentieth of the roll to go")
        clock.runFrames(for: 0.1)
        XCTAssertFalse(menu.isAnimating)
    }
}
