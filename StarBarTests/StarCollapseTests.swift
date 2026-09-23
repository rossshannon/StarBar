import XCTest
@testable import StarBar

final class StarCollapseTests: XCTestCase {
    private let stars = Stars.rating(70, starSize: NSSize(width: 16, height: 16), spacing: 4, isFavorited: true)

    func testCollapseKeepsTheFullStripUntilTheStarsAreGoneThenTakesTheBadgeWidth() {
        let layout = MenuBarStripLayout(starSize: NSSize(width: 16, height: 16), spacing: 4)
        for frame in 0...60 {
            let progress = Double(frame) / 60
            let allocation: CGFloat = StarCollapse.hasShrunk(progress: progress) ? 68 : 132
            let width = StarCollapse.width(from: 132, to: 68, progress: progress)
            XCTAssertEqual(width, allocation, "content and allocation change together, once")
            let collapse = StarCollapse.image(stars: stars, width: width - 8, progress: progress, isFavorited: true)
            XCTAssertEqual(layout.image(containing: collapse, allocation: allocation).size.width + 8, allocation)
            let rolloutWidth = StarRollout.width(from: 68, to: 132, progress: progress)
            let rollout = StarRollout.image(stars: stars, width: rolloutWidth - 8, progress: progress)
            XCTAssertEqual(layout.image(containing: rollout).size.width + 8, layout.statusItemWidth)
        }
    }

    func testOnlyStarsToAddButtonStartsACollapse() {
        XCTAssertTrue(StarCollapse.shouldCollapse(wasStopped: false, isStopped: false,
                                                  previousMode: .rating, mode: .addToLibrary))
        XCTAssertFalse(StarCollapse.shouldCollapse(wasStopped: true, isStopped: false,
                                                   previousMode: .rating, mode: .addToLibrary))
        XCTAssertFalse(StarCollapse.shouldCollapse(wasStopped: false, isStopped: true,
                                                   previousMode: .rating, mode: .addToLibrary))
        XCTAssertFalse(StarCollapse.shouldCollapse(wasStopped: false, isStopped: false,
                                                   previousMode: .rating, mode: .rating))
        XCTAssertFalse(StarCollapse.shouldCollapse(wasStopped: false, isStopped: false,
                                                   previousMode: .addToLibrary, mode: .rating))
    }

    func testStarsGoThenTheItemNarrowsUnseenThenTheBadgeAndHeartComeIn() {
        XCTAssertEqual(StarCollapse.duration, 0.75, accuracy: 0.0001)
        XCTAssertEqual(StarCollapse.duration * StarCollapse.shrinkFraction, StarCollapse.fadeOutDuration, accuracy: 0.0001)
        XCTAssertEqual(StarCollapse.duration * (StarCollapse.badgeStart - StarCollapse.shrinkFraction),
                       StarCollapse.settleDuration, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(StarCollapse.settleDuration, 0.33, "the measured slide of the narrower item")

        let halfwayOut = StarCollapse.shrinkFraction / 2
        XCTAssertEqual(StarCollapse.scale(progress: halfwayOut), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StarCollapse.heartOpacity(progress: halfwayOut), 0.5, accuracy: 0.0001)
        XCTAssertFalse(StarCollapse.hasShrunk(progress: halfwayOut))

        // Everything is gone before the item narrows, and nothing returns until the slide is over
        XCTAssertTrue(StarCollapse.hasShrunk(progress: StarCollapse.shrinkFraction))
        for progress in stride(from: StarCollapse.shrinkFraction, through: StarCollapse.badgeStart, by: 0.01) {
            XCTAssertEqual(StarCollapse.scale(progress: progress), 0)
            XCTAssertEqual(StarCollapse.heartOpacity(progress: progress), 0)
            XCTAssertEqual(StarCollapse.badgeOpacity(progress: progress), 0)
        }

        let halfwayIn = (StarCollapse.badgeStart + 1) / 2
        XCTAssertEqual(StarCollapse.badgeOpacity(progress: halfwayIn), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StarCollapse.heartOpacity(progress: halfwayIn), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StarCollapse.badgeOpacity(progress: 1), 1)
        XCTAssertEqual(StarCollapse.heartOpacity(progress: 1), 1)
    }

    func testALateFrameCannotSkipTheHiddenWait() {
        // Frames at 0 s, 0.1 s and then, after a stall, 0.6 s
        let late = StarCollapse.progress(elapsed: 0.6, sinceNarrowing: nil)
        XCTAssertEqual(late, StarCollapse.shrinkFraction, "the stall ends at the narrowing point, not past it")
        XCTAssertEqual(StarCollapse.badgeOpacity(progress: late), 0)
        XCTAssertEqual(StarCollapse.heartOpacity(progress: late), 0)
        // The wait runs from the narrowing, however late it was
        XCTAssertEqual(StarCollapse.badgeOpacity(progress: StarCollapse.progress(
            elapsed: 5, sinceNarrowing: StarCollapse.settleDuration * 0.99)), 0)
        XCTAssertGreaterThan(StarCollapse.badgeOpacity(progress: StarCollapse.progress(
            elapsed: 5, sinceNarrowing: StarCollapse.settleDuration + StarCollapse.fadeInDuration / 2)), 0)
        XCTAssertEqual(StarCollapse.progress(elapsed: 5, sinceNarrowing: StarCollapse.duration), 1)
        XCTAssertEqual(StarCollapse.progress(elapsed: StarCollapse.fadeOutDuration / 2, sinceNarrowing: nil),
                       StarCollapse.shrinkFraction / 2, accuracy: 0.0001)
    }

    func testSlowFirstFrameDoesNotSkipTheFadeOut() {
        let clock = FakeClock()
        var timing = MenuBarAnimationTiming(duration: StarCollapse.duration)
        clock.advance(by: 0.3)
        XCTAssertEqual(StarCollapse.scale(progress: timing.progress(at: clock.now())), 1)
        clock.advance(by: StarCollapse.fadeOutDuration / 2)
        XCTAssertEqual(StarCollapse.scale(progress: timing.progress(at: clock.now())), 0.5, accuracy: 0.0001)
        clock.advance(by: StarCollapse.duration)
        XCTAssertEqual(timing.progress(at: clock.now()), 1, accuracy: 0.0001)
    }

    func testScaleAndWidthClampAndNeverReverse() {
        XCTAssertEqual(StarCollapse.scale(progress: -1), 1)
        XCTAssertEqual(StarCollapse.scale(progress: 2), 0)
        XCTAssertEqual(StarCollapse.width(from: 132, to: 68, progress: -1), 132)
        XCTAssertEqual(StarCollapse.width(from: 132, to: 68, progress: 2), 68)
        var previousScale: CGFloat = 1
        var previousWidth: CGFloat = 132
        var widthChanges = 0
        for step in 0...100 {
            let progress = Double(step) / 100
            let scale = StarCollapse.scale(progress: progress)
            let width = StarCollapse.width(from: 132, to: 68, progress: progress)
            XCTAssertLessThanOrEqual(scale, previousScale)
            XCTAssertLessThanOrEqual(width, previousWidth)
            if width != previousWidth { widthChanges += 1 }
            previousScale = scale
            previousWidth = width
        }
        XCTAssertEqual(widthChanges, 1, "each width change makes the menu bar slide the item")
    }

    func testOldHalfStarsSurviveReplacementOfTheControlsRating() {
        let control = RatingControl(rating: 70)
        let outgoing = control.stars
        control.update(mode: .addToLibrary)
        control.update(rating: 0)
        XCTAssertEqual(outgoing.stars.map { $0.style }, [.full, .full, .full, .half, .dot])
        let oldImage = StarCollapse.image(stars: outgoing, width: 124, progress: 0.1, isFavorited: true)
        let newImage = StarCollapse.image(stars: control.stars, width: 124, progress: 0.1, isFavorited: true)
        XCTAssertNotEqual(oldImage.tiffRepresentation, newImage.tiffRepresentation)
        XCTAssertEqual(control.rating, 0, "Rendering must not restore the old rating to the live control")
    }

    func testEmptyWhileNarrowingThenTheBadgeAppears() throws {
        let image = StarCollapse.image(stars: stars, width: 124, progress: StarCollapse.shrinkFraction, isFavorited: true)
        let bitmap = try bitmap(image)
        XCTAssertTrue(image.isTemplate)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent, 0)
            }
        }
        let badge = try self.bitmap(StarCollapse.image(stars: stars, width: 60, progress: 0.9, isFavorited: true))
        XCTAssertTrue((0..<badge.pixelsWide).contains { x in
            (0..<badge.pixelsHigh).contains { y in (badge.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        })
    }

    func testOutlinedHeartStaysAtTheRightEdgeAndIsHiddenWhileNarrowing() throws {
        func heartAlpha(_ progress: Double) throws -> [CGFloat] {
            let width = StarCollapse.width(from: 132, to: 68, progress: progress) - 8
            let image = StarCollapse.image(stars: stars, width: width, progress: progress, isFavorited: false)
            let bitmap = try bitmap(image)
            let heartWidth = Int((16 * CGFloat(bitmap.pixelsWide) / width).rounded())
            return (0..<bitmap.pixelsHigh).flatMap { y in
                ((bitmap.pixelsWide - heartWidth)..<bitmap.pixelsWide).map { x in
                    bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                }
            }
        }
        let before = try heartAlpha(0)
        XCTAssertTrue(before.contains { $0 > 0 })
        XCTAssertEqual(try heartAlpha(1), before, "same heart in the same place at the right edge")
        let narrowing = (StarCollapse.shrinkFraction + StarCollapse.badgeStart) / 2
        XCTAssertTrue(try heartAlpha(narrowing).allSatisfy { $0 == 0 })
    }

    func testSeparateOutlineLeavesNoDuplicateHeartInTransitionImages() throws {
        let control = RatingControl(rating: 100, drawsFavorite: false)
        let old = control.stars
        control.update(rating: 50)
        var images = [StarRollout.image(stars: control.stars, width: 124, progress: 1)]
        for progress in [0.0, 0.2, 0.6, 1.0] {
            let width = StarCollapse.width(from: 132, to: 68, progress: progress) - 8
            images.append(StarCollapse.image(stars: old, width: width, progress: progress, isFavorited: false))
            images.append(StarRatingTransition.image(from: old, to: control.stars, progress: progress))
        }
        for image in images {
            let bitmap = try bitmap(image)
            let heartWidth = Int((16 * CGFloat(bitmap.pixelsWide) / image.size.width).rounded())
            let alpha = (0..<bitmap.pixelsHigh).flatMap { y in
                ((bitmap.pixelsWide - heartWidth)..<bitmap.pixelsWide).map { x in
                    bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                }
            }
            XCTAssertTrue(alpha.allSatisfy { $0 == 0 }, "The anchored outline must be the only heart")
        }
        XCTAssertFalse(control.isFavorited, "Separate drawing must not change the favourite state")
    }

    func testDeletingLibraryTrackUsesTheCatalogCollapseDespiteChangingIdentity() throws {
        try assertDeletionCollapses(changesIdentity: true, hasMissingTrackUpdate: false)
    }

    func testDeletingLibraryCopyUsesTheSameCollapseAfterAMissingTrackUpdate() throws {
        try assertDeletionCollapses(changesIdentity: false, hasMissingTrackUpdate: true)
    }

    private func assertDeletionCollapses(changesIdentity: Bool, hasMissingTrackUpdate: Bool) throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Reduce Motion intentionally bypasses the animation")
        let clock = FakeClock()
        let menu = MenuBarRatingControl(widthClock: clock)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        let track = FakeTrack(name: "StarBar deletion animation \(UUID().uuidString)", rating: 80)
        let record = PlayingTrack(track: track)
        let copy = FakeTrack(name: track.name, persistentID: "00000000000000B2", rating: 80)
        if !changesIdentity {
            track.objectClassCode = MusicTrackClass.urlTrack
            record.didAddToLibrary(copy)
        }
        menu.applyTrackDisplay(record, isStopped: false, musicIsRunning: true)
        clock.fireRepeating()
        clock.advance(by: StarRollout.duration + 0.01)
        clock.fireRepeating()
        XCTAssertEqual(menu.ratingControl.mode, .rating)
        let outgoingStars = menu.ratingControl.stars
        let fullWidth = menu.statusItem.length

        if hasMissingTrackUpdate {
            menu.applyTrackDisplay(nil, isStopped: false, musicIsRunning: true)
            XCTAssertEqual(menu.ratingControl.mode, .rating, "hold the previous strip while Music settles")
        }
        track.isPresent = !changesIdentity
        copy.isPresent = false
        let stream = FakeTrack(name: track.name,
                               persistentID: changesIdentity ? "00000000000000C3" : track.persistentID)
        stream.objectClassCode = MusicTrackClass.urlTrack
        menu.applyTrackDisplay(PlayingTrack(track: stream), isStopped: false, musicIsRunning: true)

        XCTAssertEqual(menu.ratingControl.mode, .addToLibrary)
        let timer = try XCTUnwrap(clock.timers.last)
        XCTAssertTrue(timer.isValid, "the display update must start the collapse, not snap to the badge")
        XCTAssertEqual(timer.seconds, 1.0 / 60.0)
        let layout = MenuBarStripLayout(starSize: menu.ratingControl.starSize, spacing: menu.ratingControl.spacing)
        let expectedStart = layout.image(containing: StarCollapse.image(
            stars: outgoingStars, width: fullWidth - 8, progress: 0, isFavorited: false))
        XCTAssertEqual(menu.statusItem.button?.image?.tiffRepresentation, expectedStart.tiffRepresentation,
                       "collapse begins with the deleted song's actual stars")

        clock.fireRepeating()
        clock.advance(by: StarCollapse.fadeOutDuration * 0.5)
        clock.fireRepeating()
        XCTAssertTrue(timer.isValid)
        XCTAssertEqual(menu.statusItem.length, fullWidth, "the item keeps its width while the stars are visible")

        // The later legacy save signal must not restart a collapse already in progress.
        menu.applyTrackDisplay(PlayingTrack(track: stream), isStopped: false, musicIsRunning: true)
        XCTAssertTrue(clock.timers.last === timer)

        // Nor may Music briefly sending no track and then the same song again, as it did in
        // the first live try: that cut the collapse short and narrowed the item in one step.
        menu.applyTrackDisplay(nil, isStopped: false, musicIsRunning: true)
        menu.applyTrackDisplay(PlayingTrack(track: stream), isStopped: false, musicIsRunning: true)
        XCTAssertTrue(clock.timers.last === timer)
        XCTAssertTrue(timer.isValid)
        XCTAssertEqual(menu.statusItem.length, fullWidth)

        // Once the stars are gone the item narrows, once, to the add button's own width. This
        // frame is late, as when Music reads hold the main thread: on the collapse's own clock
        // the badge would already be fading in, but the wait is timed from the narrowing.
        let compactWidth = menu.ratingControl.starsImage.size.width + 8
        XCTAssertLessThan(compactWidth, fullWidth)
        clock.advance(by: StarCollapse.fadeOutDuration * 0.5 + StarCollapse.settleDuration
                      + StarCollapse.fadeInDuration * 0.5)
        clock.fireRepeating()
        XCTAssertTrue(timer.isValid)
        XCTAssertEqual(menu.statusItem.length, compactWidth, "narrowed while nothing is showing")
        XCTAssertTrue(try isBlank(XCTUnwrap(menu.statusItem.button?.image)), "nothing shows while the item slides")
        clock.advance(by: StarCollapse.settleDuration * 0.9)
        clock.fireRepeating()
        XCTAssertTrue(timer.isValid)
        XCTAssertTrue(try isBlank(XCTUnwrap(menu.statusItem.button?.image)))

        clock.advance(by: StarCollapse.duration)
        clock.fireRepeating()
        XCTAssertFalse(timer.isValid)
        XCTAssertEqual(menu.statusItem.length, compactWidth)
        XCTAssertEqual(menu.statusItem.button?.image?.tiffRepresentation,
                       menu.ratingControl.starsImage.tiffRepresentation,
                       "the add button fills the narrowed item with no padding")

        // A rated song after the narrowing widens the item in one step and rolls the stars out
        let rated = FakeTrack(name: "StarBar rated after collapse \(UUID().uuidString)",
                              persistentID: "00000000000000D4", rating: 60)
        menu.applyTrackDisplay(PlayingTrack(track: rated), isStopped: false, musicIsRunning: true)
        XCTAssertEqual(menu.ratingControl.mode, .rating)
        XCTAssertEqual(menu.statusItem.length, fullWidth)
        let rollout = try XCTUnwrap(clock.timers.last)
        XCTAssertFalse(rollout === timer)
        XCTAssertTrue(rollout.isValid, "stars roll out rather than snapping in")
        XCTAssertTrue(rated.ratingsWritten.isEmpty)
        XCTAssertTrue(track.ratingsWritten.isEmpty)
        XCTAssertTrue(copy.ratingsWritten.isEmpty)
        XCTAssertTrue(stream.ratingsWritten.isEmpty)
    }

    private func isBlank(_ image: NSImage) throws -> Bool {
        let bitmap = try bitmap(image)
        return !(0..<bitmap.pixelsWide).contains { x in
            (0..<bitmap.pixelsHigh).contains { y in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let data = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: data))
    }
}
