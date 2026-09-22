import XCTest
@testable import StarBar

final class StarCollapseTests: XCTestCase {
    private let stars = Stars.rating(70, starSize: NSSize(width: 16, height: 16), spacing: 4, isFavorited: true)

    func testCollapseAndRolloutKeepTheSameMenuBarCanvas() {
        let layout = MenuBarStripLayout(starSize: NSSize(width: 16, height: 16), spacing: 4)
        for frame in 0...60 {
            let progress = Double(frame) / 60
            let collapseWidth = StarCollapse.width(from: 132, to: 68, progress: progress)
            let collapse = StarCollapse.image(stars: stars, width: collapseWidth - 8,
                                              progress: progress, isFavorited: true)
            let rolloutWidth = StarRollout.width(from: 68, to: 132, progress: progress)
            let rollout = StarRollout.image(stars: stars, width: rolloutWidth - 8, progress: progress)
            for content in [collapse, rollout] {
                XCTAssertEqual(layout.image(containing: content).size.width + 8, layout.statusItemWidth)
            }
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

    func testShrinkOverlapsNarrowingAndBadgeFadesInLate() {
        XCTAssertEqual(StarCollapse.duration, 0.35)
        XCTAssertEqual(StarCollapse.duration * StarCollapse.shrinkFraction, 0.15, accuracy: 0.0001)
        let halfwayThroughShrink = StarCollapse.shrinkFraction / 2
        XCTAssertEqual(StarCollapse.scale(progress: halfwayThroughShrink), 0.5, accuracy: 0.0001)
        XCTAssertLessThan(StarCollapse.width(from: 132, to: 68, progress: halfwayThroughShrink), 132)
        XCTAssertEqual(StarCollapse.scale(progress: StarCollapse.shrinkFraction), 0)
        XCTAssertEqual(StarCollapse.badgeOpacity(progress: 0.55), 0)
        XCTAssertEqual(StarCollapse.badgeOpacity(progress: 0.775), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StarCollapse.badgeOpacity(progress: 1), 1)
        XCTAssertLessThan(StarCollapse.width(from: 132, to: 68, progress: 0.55), 100)
    }

    func testSlowFirstFrameDoesNotSkipTheShrink() {
        let clock = FakeClock()
        var timing = MenuBarAnimationTiming(duration: StarCollapse.duration)
        clock.advance(by: 0.3)
        XCTAssertEqual(StarCollapse.scale(progress: timing.progress(at: clock.now())), 1)
        clock.advance(by: 0.075)
        XCTAssertEqual(StarCollapse.scale(progress: timing.progress(at: clock.now())), 0.5, accuracy: 0.0001)
        clock.advance(by: 0.275)
        XCTAssertEqual(timing.progress(at: clock.now()), 1, accuracy: 0.0001)
    }

    func testScaleAndWidthClampAndNeverReverse() {
        XCTAssertEqual(StarCollapse.scale(progress: -1), 1)
        XCTAssertEqual(StarCollapse.scale(progress: 2), 0)
        XCTAssertEqual(StarCollapse.width(from: 132, to: 68, progress: -1), 132)
        XCTAssertEqual(StarCollapse.width(from: 132, to: 68, progress: 2), 68)
        var previousScale: CGFloat = 1
        var previousWidth: CGFloat = 132
        for step in 0...100 {
            let progress = Double(step) / 100
            let scale = StarCollapse.scale(progress: progress)
            let width = StarCollapse.width(from: 132, to: 68, progress: progress)
            XCTAssertLessThanOrEqual(scale, previousScale)
            XCTAssertLessThanOrEqual(width, previousWidth)
            XCTAssertGreaterThanOrEqual(width, 68)
            previousScale = scale
            previousWidth = width
        }
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

    func testPhaseBoundaryHasNeitherStarsNorBadge() throws {
        let image = StarCollapse.image(stars: stars, width: 124, progress: StarCollapse.shrinkFraction, isFavorited: true)
        let bitmap = try bitmap(image)
        XCTAssertTrue(image.isTemplate)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent, 0)
            }
        }
        let badge = try self.bitmap(StarCollapse.image(stars: stars, width: 124, progress: 0.7, isFavorited: true))
        XCTAssertTrue((0..<badge.pixelsWide).contains { x in
            (0..<badge.pixelsHigh).contains { y in (badge.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        })
    }

    func testOutlinedHeartStaysAtTheRightEdgeThroughBothPhases() throws {
        var reference: [CGFloat]?
        for progress in [0.0, 0.1, 0.2, 0.6, 1.0] {
            let width = StarCollapse.width(from: 132, to: 68, progress: progress) - 8
            let image = StarCollapse.image(stars: stars, width: width, progress: progress, isFavorited: false)
            let bitmap = try bitmap(image)
            let heartWidth = Int((16 * CGFloat(bitmap.pixelsWide) / width).rounded())
            let pixels = (0..<bitmap.pixelsHigh).flatMap { y in
                ((bitmap.pixelsWide - heartWidth)..<bitmap.pixelsWide).map { x in
                    bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                }
            }
            XCTAssertTrue(pixels.contains { $0 > 0 })
            if let reference = reference { XCTAssertEqual(pixels, reference) }
            reference = pixels
        }
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

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let data = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: data))
    }
}
