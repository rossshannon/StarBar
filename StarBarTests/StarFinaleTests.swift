//
//  StarFinaleTests.swift
//  StarBarTests
//
//  The five-star finale as pure timing and geometry, and as drawn: when each star throws its
//  small star, which way they fan in the menu bar and on the strip, how one grows, turns and
//  shrinks away, that nothing leaves the frame a view is sized from, and that a frame draws
//  each piece in its own colour where the rule puts it.
//

import XCTest
@testable import StarBar

final class StarFinaleTests: XCTestCase {

    private let stagger: TimeInterval = 0.05

    /// The menu bar's, for its 16 point stars 4 apart
    private func menuBar(stagger: TimeInterval = 0.05) -> StarFinale {
        return .menuBar(starSize: 16, spacing: 4, stagger: stagger)
    }

    /// The strip's, for its 12 point stars 3 apart at scale 1
    private func strip(scale: CGFloat = 1, stagger: TimeInterval = 0.05) -> StarFinale {
        return .strip(starSize: 12 * scale, spacing: 3 * scale, stagger: stagger)
    }

    /// Every finale the app plays: the menu bar's and the strip's at each scale, under the
    /// run's stagger and the plain pop's, which has none
    private var everyFinale: [(name: String, finale: StarFinale)] {
        var all: [(name: String, finale: StarFinale)] = []
        for stagger in [0.05, 0] {
            all.append(("menu bar, stagger \(stagger)", menuBar(stagger: stagger)))
            let scales: [CGFloat] = [1, 1.44, 2]
            for scale in scales {
                all.append(("strip at \(scale), stagger \(stagger)", strip(scale: scale, stagger: stagger)))
            }
        }
        return all
    }

    /// Moments through a finale, four to a frame at 60 Hz, and a little past its end
    private func moments(of finale: StarFinale) -> [TimeInterval] {
        return stride(from: 0, through: finale.duration + 0.02, by: 1.0 / 240.0).map { $0 }
    }

    private func smallStar(_ star: Int, in finale: StarFinale, at elapsed: TimeInterval) -> StarFinale.Piece? {
        return finale.pieces(at: elapsed).first { $0.star == star && $0.isStar }
    }

    private func dot(_ star: Int, in finale: StarFinale, at elapsed: TimeInterval) -> StarFinale.Piece? {
        return finale.pieces(at: elapsed).first { $0.star == star && !$0.isStar }
    }

    /// When star `star`'s small star leaves
    private func launch(of star: Int) -> TimeInterval {
        return TimeInterval(star) * stagger + StarFinale.launchDelay
    }

    // MARK: - When

    func testEachStarThrowsASmallStarAndItsDotJustAfterTheRunReachesIt() {
        let finale = menuBar()
        XCTAssertTrue(finale.pieces(at: 0).isEmpty, "nothing in the air on the first frame")
        XCTAssertTrue(finale.pieces(at: launch(of: 0) - 0.001).isEmpty)

        let first = finale.pieces(at: launch(of: 0) + 0.001)
        XCTAssertEqual(first.map { $0.star }, [0, 0], "the first star's, and nothing else yet")
        XCTAssertEqual(first.map { $0.isStar }, [true, false], "a small star, then the dot that trails it")

        for star in 0..<StarFinale.starCount {
            XCTAssertNil(smallStar(star, in: finale, at: launch(of: star) - 0.001), "star \(star) hasn't thrown yet")
            XCTAssertNotNil(smallStar(star, in: finale, at: launch(of: star) + 0.001), "star \(star) has")
            XCTAssertNotNil(dot(star, in: finale, at: launch(of: star) + 0.001))
        }
        XCTAssertEqual(finale.pieces(at: 0.3).count, 10, "all five pairs in the air together")
    }

    func testTheyGoInTheOrderTheyLeftAndTheLastOneEndsTheFinale() {
        let finale = menuBar()
        for star in 0..<StarFinale.starCount {
            let landed = launch(of: star) + StarFinale.flightDuration
            XCTAssertNotNil(smallStar(star, in: finale, at: landed - 0.01), "star \(star) still flying")
            XCTAssertNil(smallStar(star, in: finale, at: landed + 0.001), "star \(star) gone")
            XCTAssertNil(dot(star, in: finale, at: landed + 0.001), "and its dot with it")
        }
        XCTAssertEqual(finale.duration, 0.88, accuracy: 0.0001)
        XCTAssertEqual(finale.duration, StarFinale.duration(stagger: stagger))
        XCTAssertFalse(finale.pieces(at: finale.duration - 0.01).isEmpty)
        XCTAssertTrue(finale.pieces(at: finale.duration + 0.001).isEmpty, "nothing once the last has shrunk away")
    }

    /// The plain pop lights every star together, so its finale throws all five at once
    func testWithNoStaggerAllFiveLeaveTogether() {
        let finale = menuBar(stagger: 0)
        XCTAssertEqual(finale.duration, StarFinale.launchDelay + StarFinale.flightDuration, accuracy: 0.0001)
        XCTAssertTrue(finale.pieces(at: StarFinale.launchDelay - 0.001).isEmpty)
        XCTAssertEqual(finale.pieces(at: StarFinale.launchDelay + 0.001).count, 10)
    }

    // MARK: - Where

    func testTheFirstStarsLeansLeftTheLastOnesRightAndTheMiddleOnesFliesStraightOut() throws {
        let finale = menuBar()
        XCTAssertEqual(finale.lean(of: 0), 0.84, accuracy: 0.0001, "48 degrees")
        XCTAssertEqual(finale.lean(of: 2), 0)
        XCTAssertEqual(finale.lean(of: 4), -0.84, accuracy: 0.0001)

        // 0.4 s in, all five are well out: star i's own centre is 20 i from the first's
        let offsets = try (0..<5).map { try XCTUnwrap(smallStar($0, in: finale, at: 0.4)).offset.dx }
        XCTAssertLessThan(offsets[0], -10, "left of the first star")
        XCTAssertLessThan(offsets[1], 20, "left of its own star")
        XCTAssertEqual(offsets[2], 40, accuracy: 0.0001, "straight out from the middle star")
        XCTAssertGreaterThan(offsets[3], 60)
        XCTAssertGreaterThan(offsets[4], 90, "right of the last star")
        for (left, right) in zip(offsets, offsets.dropFirst()) {
            XCTAssertLessThan(left, right, "a fan, in the stars' own order")
        }
    }

    /// The screen's top edge is about 12 points above the menu bar's stars, and the strip's
    /// panel ends at the strip's bottom edge
    func testTheMenuBarsFanDownAndTheStripsFanUp() {
        for (name, finale) in everyFinale {
            for elapsed in moments(of: finale) {
                for piece in finale.pieces(at: elapsed) {
                    if finale.fan == .down {
                        XCTAssertLessThan(piece.offset.dy, 0, "\(name) at \(elapsed): star \(piece.star) below the stars")
                    } else {
                        XCTAssertGreaterThan(piece.offset.dy, 0, "\(name) at \(elapsed): star \(piece.star) above the stars")
                    }
                }
            }
        }
        XCTAssertEqual(menuBar().fan, .down)
        XCTAssertEqual(strip().fan, .up)
    }

    /// Nothing the menu bar's finale draws comes nearer the screen's top edge than the stars
    /// themselves are
    func testTheMenuBarsPiecesNeverRiseAboveTheStarsCentres() {
        for stagger in [0.05, 0] {
            let finale = menuBar(stagger: stagger)
            for elapsed in moments(of: finale) {
                for piece in finale.pieces(at: elapsed) {
                    XCTAssertLessThan(piece.offset.dy + piece.radius, 0, "at \(elapsed), star \(piece.star)")
                }
            }
            XCTAssertEqual(finale.bounds.maxY, finale.miniRadius, accuracy: 0.0001, "so its frame reaches only that far up")
        }
    }

    func testTheMenuBarsSmallStarsEndAboutTwentySevenPointsBelowTheStars() throws {
        let finale = menuBar()
        let lowest = moments(of: finale).flatMap { finale.pieces(at: $0) }.map { $0.offset.dy - $0.radius }.min()
        XCTAssertLessThan(try XCTUnwrap(lowest), -24, "well clear of the menu bar")
        XCTAssertGreaterThan(try XCTUnwrap(lowest), -31)
        XCTAssertEqual(finale.reach, 23)
        XCTAssertEqual(finale.miniRadius, 3.4, accuracy: 0.0001)
        XCTAssertEqual(finale.pitch, 20)
    }

    /// There is room above the strip's stars, so its small stars are bigger for their size
    func testTheStripsFinaleIsBiggerForItsStars() {
        let inMenuBar = menuBar()
        let onStrip = strip()
        XCTAssertGreaterThan(onStrip.reach / onStrip.starSize, inMenuBar.reach / inMenuBar.starSize)
        XCTAssertGreaterThan(onStrip.miniRadius / onStrip.starSize, inMenuBar.miniRadius / inMenuBar.starSize)
        XCTAssertEqual(onStrip.pitch, 15)
        let doubled = strip(scale: 2)
        XCTAssertEqual(doubled.reach, 2 * onStrip.reach, accuracy: 0.0001, "and it scales with the strip")
        XCTAssertEqual(doubled.miniRadius, 2 * onStrip.miniRadius, accuracy: 0.0001)
        XCTAssertEqual(doubled.dotRadius, 2 * onStrip.dotRadius, accuracy: 0.0001)
    }

    func testEverythingDrawnStaysInsideTheBoundsAViewIsSizedFrom() {
        for (name, finale) in everyFinale {
            let bounds = finale.bounds
            for elapsed in moments(of: finale) {
                for piece in finale.pieces(at: elapsed) {
                    let drawn = NSRect(x: piece.offset.dx - piece.radius, y: piece.offset.dy - piece.radius,
                                       width: 2 * piece.radius, height: 2 * piece.radius)
                    XCTAssertTrue(bounds.contains(drawn), "\(name) at \(elapsed): star \(piece.star) at \(drawn) in \(bounds)")
                }
            }
        }
    }

    // MARK: - One small star

    func testASmallStarLeavesAtHalfSizeIsFullWithinAFewFramesAndShrinksAway() throws {
        let finale = menuBar()
        let flight = StarFinale.flightDuration
        let leaving = try XCTUnwrap(smallStar(0, in: finale, at: launch(of: 0) + 0.001))
        XCTAssertEqual(leaving.radius, finale.miniRadius / 2, accuracy: 0.1, "half size as it leaves")

        for progress in [0.15, 0.3, 0.44] {
            let piece = try XCTUnwrap(smallStar(0, in: finale, at: launch(of: 0) + progress * flight))
            XCTAssertEqual(piece.radius, finale.miniRadius, accuracy: 0.0001, "full size \(progress) of the way")
        }
        // Every twentieth of the flight from 0.45 to 0.95
        let radii = (9...19).compactMap { smallStar(0, in: finale, at: launch(of: 0) + Double($0) * 0.05 * flight)?.radius }
        XCTAssertEqual(radii.count, 11)
        for (earlier, later) in zip(radii, radii.dropFirst()) {
            XCTAssertLessThan(later, earlier, "it only shrinks from there")
        }
        let last = try XCTUnwrap(smallStar(0, in: finale, at: launch(of: 0) + 0.99 * flight))
        XCTAssertLessThan(last.radius, 0.05, "to nothing")
    }

    func testASmallStarFliesOutFastSlowsAndFallsALittle() throws {
        let finale = menuBar()
        let flight = StarFinale.flightDuration
        // The middle star's flies straight down, so its dy is its distance and its fall
        func depth(_ progress: Double) throws -> CGFloat {
            let piece = try XCTUnwrap(smallStar(2, in: finale, at: launch(of: 2) + progress * flight))
            return -piece.offset.dy
        }
        let leaving = try depth(0.001)
        let aQuarter = try depth(0.25)
        let half = try depth(0.5)
        let landing = try depth(0.999)
        XCTAssertEqual(leaving, 5, accuracy: 0.3, "it leaves from just outside its star")
        XCTAssertGreaterThan(aQuarter - leaving, 2 * (landing - half), "most of the way in the first quarter")
        XCTAssertEqual(landing, finale.reach + finale.drop, accuracy: 0.1, "as far as it reaches, and the fall")
        XCTAssertEqual(finale.drop, 4)
    }

    func testSmallStarsTurnAsTheyFlyEachTheOtherWayFromItsNeighbour() throws {
        let finale = menuBar()
        for star in 0..<StarFinale.starCount {
            let leaving = try XCTUnwrap(smallStar(star, in: finale, at: launch(of: star) + 0.001))
            XCTAssertEqual(leaving.rotation, 0, accuracy: 0.02)
            let landing = try XCTUnwrap(smallStar(star, in: finale, at: launch(of: star) + 0.999 * StarFinale.flightDuration))
            let expected = (star % 2 == 0 ? 1 : -1) * StarFinale.turn
            XCTAssertEqual(landing.rotation, expected, accuracy: 0.02, "star \(star): about 150 degrees")
            let trailing = try XCTUnwrap(dot(star, in: finale, at: launch(of: star) + 0.5 * StarFinale.flightDuration))
            XCTAssertEqual(trailing.rotation, 0, "a dot has nothing to turn")
        }
    }

    func testADotTrailsItsSmallStarNearerTheStarsAndToOneSide() throws {
        for finale in [menuBar(), strip()] {
            for star in 0..<StarFinale.starCount {
                let elapsed = launch(of: star) + 0.3 * StarFinale.flightDuration
                let small = try XCTUnwrap(smallStar(star, in: finale, at: elapsed))
                let trailing = try XCTUnwrap(dot(star, in: finale, at: elapsed))
                XCTAssertEqual(trailing.radius, finale.dotRadius, accuracy: 0.0001)
                XCTAssertLessThan(trailing.radius, small.radius)
                XCTAssertLessThan(abs(trailing.offset.dy), abs(small.offset.dy), "\(finale.fan), star \(star): not as far out")
                let apart = hypot(trailing.offset.dx - small.offset.dx, trailing.offset.dy - small.offset.dy)
                XCTAssertGreaterThan(apart, small.radius + trailing.radius, "\(finale.fan), star \(star): clear of its small star")
            }
        }
    }

    // MARK: - Colours

    func testEachSmallStarTakesOneOfTheIconsColoursAndItsDotAnother() {
        XCTAssertEqual(StarFinale.colours, StarFlourish.bandColours)
        XCTAssertEqual(StarFinale.colours.count, StarFinale.starCount, "one to a star")
        let finale = menuBar()
        let pieces = finale.pieces(at: 0.3)
        XCTAssertEqual(pieces.count, 10)
        for piece in pieces where piece.isStar {
            XCTAssertEqual(StarFinale.colour(of: piece), StarFinale.colours[piece.star])
        }
        for piece in pieces where !piece.isStar {
            XCTAssertEqual(StarFinale.colour(of: piece), StarFinale.colours[(piece.star + 2) % 5])
            XCTAssertNotEqual(StarFinale.colour(of: piece), StarFinale.colours[piece.star], "no pair is one colour")
        }
    }

    // MARK: - The view

    func testTheViewsFrameHoldsTheWholeFinaleInWholePointsAroundTheFirstStar() {
        for (name, finale) in everyFinale {
            let centre = NSPoint(x: 1234.4, y: 987.236)
            let placed = StarFinaleView.frame(for: finale, firstStarAt: centre)

            XCTAssertEqual(placed.frame.minX, placed.frame.minX.rounded(), name)
            XCTAssertEqual(placed.frame.minY, placed.frame.minY.rounded(), name)
            XCTAssertEqual(placed.frame.width, placed.frame.width.rounded(), name)
            XCTAssertEqual(placed.frame.height, placed.frame.height.rounded(), name)
            XCTAssertEqual(placed.frame.minX + placed.origin.x, centre.x, accuracy: 0.0001, "\(name): the first star stays where it is")
            XCTAssertEqual(placed.frame.minY + placed.origin.y, centre.y, accuracy: 0.0001, name)
            let reach = finale.bounds.offsetBy(dx: centre.x, dy: centre.y)
            XCTAssertTrue(placed.frame.contains(reach), "\(name): \(reach) in \(placed.frame)")
            XCTAssertLessThan(placed.frame.width, reach.width + 7, "\(name): with a little room, not a lot")
        }
    }

    func testTheViewIsNeverInTheWayOfAClick() {
        let view = StarFinaleView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        view.finale = menuBar()
        view.elapsed = 0.3
        XCTAssertNil(view.hitTest(NSPoint(x: 50, y: 30)))
    }

    func testAStarsOutlineTurnsAboutItsOwnMiddle() {
        let centre = NSPoint(x: 50, y: 40)
        let upright = StarFinale.Piece(star: 0, isStar: true, offset: .zero, radius: 10, rotation: 0)
        let path = StarFinaleView.path(for: upright, at: centre)
        XCTAssertTrue(path.contains(centre))
        XCTAssertEqual(path.bounds.maxY, 50, accuracy: 0.001, "a point straight up")
        XCTAssertEqual(path.bounds.minY, 40 - 8.09, accuracy: 0.01, "and two feet")
        XCTAssertEqual(path.bounds.midX, 50, accuracy: 0.001)

        var turned = upright
        turned.rotation = .pi
        let upsideDown = StarFinaleView.path(for: turned, at: centre)
        XCTAssertTrue(upsideDown.contains(centre), "still about the same middle")
        XCTAssertEqual(upsideDown.bounds.minY, 30, accuracy: 0.001, "the point straight down")
        XCTAssertEqual(upsideDown.bounds.maxY, 40 + 8.09, accuracy: 0.01)

        // A fifth of a turn brings a five-pointed star back onto itself
        turned.rotation = 2 * .pi / 5
        let same = StarFinaleView.path(for: turned, at: centre).bounds
        XCTAssertEqual(same.minX, path.bounds.minX, accuracy: 0.001)
        XCTAssertEqual(same.maxY, path.bounds.maxY, accuracy: 0.001)
        XCTAssertEqual(same.width, path.bounds.width, accuracy: 0.001)
    }

    func testADotsOutlineIsACircleOfItsRadius() {
        let piece = StarFinale.Piece(star: 3, isStar: false, offset: .zero, radius: 2.5, rotation: 0)
        let path = StarFinaleView.path(for: piece, at: NSPoint(x: 20, y: 30))
        XCTAssertEqual(path.bounds.minX, 17.5, accuracy: 0.001)
        XCTAssertEqual(path.bounds.minY, 27.5, accuracy: 0.001)
        XCTAssertEqual(path.bounds.width, 5, accuracy: 0.001)
        XCTAssertEqual(path.bounds.height, 5, accuracy: 0.001)
    }

    // MARK: - As drawn

    /// A finale view sized for `finale`, with its first star where `frame(for:firstStarAt:)`
    /// puts it
    private func finaleView(for finale: StarFinale) -> StarFinaleView {
        let placed = StarFinaleView.frame(for: finale, firstStarAt: NSPoint(x: 100, y: 40))
        let view = StarFinaleView(frame: NSRect(origin: .zero, size: placed.frame.size))
        view.origin = placed.origin
        view.finale = finale
        return view
    }

    /// What the view draws, one pixel a point
    private func drawn(_ view: StarFinaleView) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    /// The pixel that holds `point`, with y up from the view's bottom as AppKit draws
    private func colour(in bitmap: NSBitmapImageRep, at point: NSPoint) throws -> NSColor {
        return try XCTUnwrap(bitmap.colorAt(x: Int(point.x), y: bitmap.pixelsHigh - 1 - Int(point.y)))
    }

    private func paintedPixels(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                count += 1
            }
        }
        return count
    }

    /// Which of the finale's five colours `colour` is nearest
    private func nearestColour(to colour: NSColor) throws -> Int {
        let distances = try StarFinale.colours.map { candidate -> CGFloat in
            let other = try XCTUnwrap(candidate.usingColorSpace(.deviceRGB))
            return abs(other.redComponent - colour.redComponent) + abs(other.greenComponent - colour.greenComponent)
                + abs(other.blueComponent - colour.blueComponent)
        }
        let least = try XCTUnwrap(distances.min())
        return try XCTUnwrap(distances.firstIndex(of: least))
    }

    /// The strip's finale at twice its size, 0.35 s in: all ten pieces are in the air, each
    /// clear of the others, and big enough that the pixel at its middle is all its own
    func testAFrameDrawsEachPieceInItsOwnColourWhereTheRulePutsIt() throws {
        let finale = strip(scale: 2)
        let view = finaleView(for: finale)
        view.elapsed = 0.35
        let bitmap = try drawn(view)

        let pieces = finale.pieces(at: 0.35)
        XCTAssertEqual(pieces.count, 10)
        for piece in pieces {
            let centre = NSPoint(x: view.origin.x + piece.offset.dx, y: view.origin.y + piece.offset.dy)
            let middle = try colour(in: bitmap, at: centre)
            let what = "star \(piece.star)'s \(piece.isStar ? "small star" : "dot")"
            XCTAssertGreaterThan(middle.alphaComponent, 0.9, "\(what) is drawn at \(centre)")
            let expected = piece.isStar ? piece.star : (piece.star + 2) % 5
            XCTAssertEqual(try nearestColour(to: middle), expected, "\(what) in its colour")
        }
        // Nothing where nothing is: the first star's own centre, which the finale never covers
        XCTAssertEqual(try colour(in: bitmap, at: view.origin).alphaComponent, 0, "the five stars themselves aren't drawn")
    }

    func testNothingIsDrawnBeforeTheFirstLeavesAfterTheLastHasGoneOrWithNoFinale() throws {
        let finale = strip(scale: 2)
        let view = finaleView(for: finale)

        view.elapsed = 0
        XCTAssertEqual(paintedPixels(in: try drawn(view)), 0, "the first frame is empty")
        view.elapsed = 0.35
        XCTAssertGreaterThan(paintedPixels(in: try drawn(view)), 400, "ten pieces in the air")
        view.elapsed = finale.duration + 0.01
        XCTAssertEqual(paintedPixels(in: try drawn(view)), 0)

        view.elapsed = 0.35
        view.finale = nil
        XCTAssertEqual(paintedPixels(in: try drawn(view)), 0, "no finale, nothing drawn")
    }

}
