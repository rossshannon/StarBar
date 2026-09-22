import XCTest
@testable import StarBar

final class StarRatingTransitionTests: XCTestCase {
    func testSlowMusicReadBeforeFirstFrameDoesNotConsumeTheAnimation() {
        let clock = FakeClock()
        var timing = MenuBarAnimationTiming(duration: StarRatingTransition.duration)
        clock.advance(by: 0.233)
        XCTAssertEqual(timing.progress(at: clock.now()), 0,
                       "The first display callback must start the animation, even after slow Music reads")
        clock.advance(by: 0.1)
        XCTAssertEqual(timing.progress(at: clock.now()), 0.5, accuracy: 0.0001)
        clock.advance(by: 0.1)
        XCTAssertEqual(timing.progress(at: clock.now()), 1, accuracy: 0.0001)
    }

    func testReplacementAnimationGetsItsOwnFirstFrame() {
        let clock = FakeClock()
        var first = MenuBarAnimationTiming(duration: StarRatingTransition.duration)
        XCTAssertEqual(first.progress(at: clock.now()), 0)
        clock.advance(by: 0.1)
        XCTAssertEqual(first.progress(at: clock.now()), 0.5, accuracy: 0.0001)
        var replacement = MenuBarAnimationTiming(duration: StarRatingTransition.duration)
        clock.advance(by: 1)
        XCTAssertEqual(replacement.progress(at: clock.now()), 0)
        clock.advance(by: StarRatingTransition.duration)
        XCTAssertEqual(replacement.progress(at: clock.now()), 1, accuracy: 0.0001)
    }

    private func stars(_ rating: Int) -> Stars {
        Stars.rating(rating, starSize: NSSize(width: 16, height: 16), spacing: 4, isFavorited: false)
    }

    func testOnlyDifferentRatingsInAnActiveRatingStripAnimate() {
        func eligible(_ stopped: Bool = false, _ mode: RatingControl.Mode = .rating, _ rating: Int = 50) -> Bool {
            StarRatingTransition.shouldAnimate(wasStopped: stopped, isStopped: false,
                                               previousMode: mode, mode: .rating, from: stars(100), to: stars(rating))
        }
        XCTAssertTrue(eligible())
        XCTAssertFalse(eligible(true))
        XCTAssertFalse(eligible(false, .addToLibrary))
        XCTAssertFalse(eligible(false, .rating, 100))
        XCTAssertFalse(StarRatingTransition.shouldAnimate(wasStopped: false, isStopped: true,
                                                          previousMode: .rating, mode: .rating,
                                                          from: stars(100), to: stars(50)))
        XCTAssertFalse(StarRatingTransition.shouldAnimate(wasStopped: false, isStopped: false,
                                                          previousMode: .rating, mode: .addToLibrary,
                                                          from: stars(100), to: stars(50)))
    }

    func testEndpointsMatchNativeDrawingForEveryHalfStarRating() throws {
        for from in stride(from: 0, through: 100, by: 10) {
            for to in stride(from: 0, through: 100, by: 10) {
                let start = StarRatingTransition.image(from: stars(from), to: stars(to), progress: -1)
                let end = StarRatingTransition.image(from: stars(from), to: stars(to), progress: 2)
                XCTAssertEqual(try pixels(start), try pixels(stars(from).image), "Start \(from) to \(to)")
                XCTAssertEqual(try pixels(end), try pixels(stars(to).image), "End \(from) to \(to)")
            }
        }
    }

    func testUnchangedStarsAndHeartStayIdenticalThroughout() throws {
        let reference = StarRatingTransition.image(from: stars(100), to: stars(50), progress: 0)
        for step in 0...20 {
            let image = StarRatingTransition.image(from: stars(100), to: stars(50), progress: Double(step) / 20)
            XCTAssertEqual(image.size, reference.size)
            XCTAssertEqual(try pixels(image, xRange: 0..<40), try pixels(reference, xRange: 0..<40))
            XCTAssertEqual(try pixels(image, xRange: 104..<124), try pixels(reference, xRange: 104..<124))
        }
    }

    func testRetractionGetsSmallerAndGrowthReversesIt() throws {
        var lastInk = Double.greatestFiniteMagnitude
        for step in 0...20 {
            let progress = Double(step) / 20
            let down = StarRatingTransition.image(from: stars(100), to: stars(0), progress: progress)
            let up = StarRatingTransition.image(from: stars(0), to: stars(100), progress: 1 - progress)
            let alpha = try pixels(down, xRange: 64..<100)
            let ink = alpha.reduce(0, +)
            // Check quarter-phase milestones; subpixel rasterisation can vary coverage
            // slightly between adjacent frames even while the shape gets smaller.
            if step % 5 == 0 {
                XCTAssertLessThan(ink, lastInk)
                lastInk = ink
            }
            let reverse = try pixels(up, xRange: 64..<100)
            XCTAssertLessThan(zip(alpha, reverse).map { abs($0 - $1) }.max() ?? 0, 0.01)
        }
    }

    func testRenderingDoesNotChangeTheTargetRating() {
        let control = RatingControl(rating: 100)
        let previous = control.stars
        control.update(rating: 50)
        _ = StarRatingTransition.image(from: previous, to: control.stars, progress: 0.5).tiffRepresentation
        XCTAssertEqual(control.rating, 50)
        XCTAssertEqual(control.stars.stars.map { $0.style }, [.full, .full, .half, .dot, .dot])
    }

    private func pixels(_ image: NSImage, xRange: Range<Int>? = nil) throws -> [Double] {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 124, pixelsHigh: 16,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<16).flatMap { y in
            (xRange ?? 0..<124).map { x in Double(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) }
        }
    }
}
