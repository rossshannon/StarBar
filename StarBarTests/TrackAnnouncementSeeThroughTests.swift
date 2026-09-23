//
//  TrackAnnouncementSeeThroughTests.swift
//  StarBarTests
//
//  The rules for seeing through the strip: where the hole goes for a pointer, how the mask
//  around it is tiled, how the background fades, and what counts as typing.
//

import XCTest
@testable import StarBar

final class TrackAnnouncementSeeThroughTests: XCTestCase {

    private let strip = CGRect(x: 100, y: 50, width: 1000, height: 150)

    // MARK: - Where the hole goes

    func testAPointerOverTheStripGetsAHoleUnderIt() throws {
        let hole = try XCTUnwrap(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 400, y: 120), stripFrame: strip, radius: 60, feather: 24))

        XCTAssertEqual(hole.centre, CGPoint(x: 300, y: 70), "in the strip's own coordinates")
        XCTAssertEqual(hole.radius, 60)
        XCTAssertEqual(hole.feather, 24)
    }

    func testAPointerJustOutsideTheStripStillReachesIt() throws {
        // 40 points above the top edge: the lower part of a 60 point hole shows
        let hole = try XCTUnwrap(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 400, y: 240), stripFrame: strip, radius: 60, feather: 24))
        XCTAssertEqual(hole.centre, CGPoint(x: 300, y: 190))

        // Diagonally off a corner, but less than the radius away from it
        XCTAssertNotNil(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 1130, y: 230), stripFrame: strip, radius: 60, feather: 24))
    }

    func testAPointerFarFromTheStripHasNoHole() {
        XCTAssertNil(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 400, y: 260), stripFrame: strip, radius: 60, feather: 24), "exactly a radius away: nothing would show")
        XCTAssertNil(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 400, y: 900), stripFrame: strip, radius: 60, feather: 24))
        // Off a corner by 50 on each axis: 71 points away
        XCTAssertNil(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 1150, y: 250), stripFrame: strip, radius: 60, feather: 24))
    }

    func testNoRadiusMeansNoHole() {
        XCTAssertNil(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 400, y: 120), stripFrame: strip, radius: 0, feather: 24))
    }

    func testTheSoftEdgeIsNeverWiderThanTheHole() throws {
        let hole = try XCTUnwrap(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 400, y: 120), stripFrame: strip, radius: 20, feather: 50))
        XCTAssertEqual(hole.feather, 20)
        let negative = try XCTUnwrap(TrackAnnouncementSeeThrough.peephole(pointer: CGPoint(x: 400, y: 120), stripFrame: strip, radius: 20, feather: -5))
        XCTAssertEqual(negative.feather, 0)
    }

    // MARK: - The mask

    func testTheHoleSitsOnWholePixels() {
        let peephole = TrackAnnouncementPeephole(centre: CGPoint(x: 100.3, y: 40.7), radius: 30.2, feather: 10)
        for scale: CGFloat in [1, 2, 3] {
            let rect = TrackAnnouncementSeeThrough.holeRect(for: peephole, scale: scale)
            for value in [rect.minX, rect.minY, rect.width, rect.height] {
                XCTAssertEqual((value * scale).rounded(), value * scale, accuracy: 1e-9, "\(value) at scale \(scale)")
            }
            XCTAssertGreaterThanOrEqual(rect.width, 60.4)
            XCTAssertEqual(rect.midX, 100.3, accuracy: 1 / scale)
            XCTAssertEqual(rect.midY, 40.7, accuracy: 1 / scale)
        }
    }

    /// The tiles and the hole cover the bounds once each: no gaps, which would let the
    /// background show through as a stray line, and no overlaps
    private func assertTilesCover(_ bounds: CGRect, around hole: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let tiles = TrackAnnouncementSeeThrough.maskTiles(around: hole, in: bounds)
        XCTAssertEqual(tiles.count, 4, file: file, line: line)
        let holeInside = hole.intersection(bounds)
        let covered = tiles.reduce(holeInside.isNull ? 0 : holeInside.width * holeInside.height) { $0 + $1.width * $1.height }
        XCTAssertEqual(covered, bounds.width * bounds.height, accuracy: 1e-6, "area", file: file, line: line)
        for (index, tile) in tiles.enumerated() {
            XCTAssertGreaterThanOrEqual(tile.width, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tile.height, 0, file: file, line: line)
            XCTAssertTrue(bounds.union(tile) == bounds || tile.isEmpty, "tile \(index) inside the bounds", file: file, line: line)
            let overlap = tile.intersection(hole)
            XCTAssertTrue(overlap.isNull || overlap.width * overlap.height == 0, "tile \(index) clear of the hole", file: file, line: line)
            for other in tiles[(index + 1)...] {
                let shared = tile.intersection(other)
                XCTAssertTrue(shared.isNull || shared.width * shared.height == 0, "tiles overlap", file: file, line: line)
            }
        }
    }

    func testTheTilesFillEverythingAroundTheHole() {
        let bounds = CGRect(x: 0, y: -8, width: 1000, height: 158)
        assertTilesCover(bounds, around: CGRect(x: 400, y: 20, width: 120, height: 120))
        // Hanging over the top edge, off the left end, off the bottom right corner, wholly above
        assertTilesCover(bounds, around: CGRect(x: 400, y: 100, width: 120, height: 120))
        assertTilesCover(bounds, around: CGRect(x: -50, y: 20, width: 120, height: 120))
        assertTilesCover(bounds, around: CGRect(x: 950, y: -60, width: 120, height: 120))
        assertTilesCover(bounds, around: CGRect(x: 400, y: 300, width: 120, height: 120))
    }

    func testTheHoleImageIsClearInTheMiddleAndSolidAtTheCorners() throws {
        let image = try XCTUnwrap(TrackAnnouncementPeepholeMask.holeImage(radius: 60, feather: 24, scale: 2))
        XCTAssertEqual(image.width, 240)
        XCTAssertEqual(image.height, 240)
        let rep = NSBitmapImageRep(cgImage: image)

        func alpha(_ x: Int, _ y: Int) -> CGFloat { return rep.colorAt(x: x, y: y)?.alphaComponent ?? -1 }
        XCTAssertEqual(alpha(120, 120), 0, accuracy: 0.01, "clear in the middle")
        XCTAssertEqual(alpha(120 + 70, 120), 0, accuracy: 0.01, "and out to radius less feather (36 points, 72 pixels)")
        XCTAssertEqual(alpha(0, 0), 1, accuracy: 0.01, "solid at the corners")
        XCTAssertEqual(alpha(239, 120), 1, accuracy: 0.02, "solid at the rim")
        let midEdge = alpha(120 + 96, 120)
        XCTAssertGreaterThan(midEdge, 0.2, "part way through the soft edge")
        XCTAssertLessThan(midEdge, 0.8)
    }

    func testTheMaskCoversItsBoundsAroundTheHole() {
        let mask = TrackAnnouncementPeepholeMask()
        let bounds = CGRect(x: 0, y: -12, width: 800, height: 162)
        mask.place(TrackAnnouncementPeephole(centre: CGPoint(x: 300, y: 70), radius: 50, feather: 20), in: bounds, scale: 2)

        XCTAssertEqual(mask.frame, bounds)
        let layers = mask.sublayers ?? []
        XCTAssertEqual(layers.count, 5)
        let hole = layers.last { $0.contents != nil }
        XCTAssertEqual(hole?.frame, CGRect(x: 250, y: 32, width: 100, height: 100), "centred on the pointer, in the mask's own coordinates")
        // The frame is in screen pixels; the image under it is coarse, and stretched
        let image = hole?.contents.map { $0 as! CGImage }
        XCTAssertEqual(image?.width, 50, "half a pixel per point, whatever the screen")
        let area = layers.reduce(CGFloat(0)) { $0 + $1.frame.width * $1.frame.height }
        XCTAssertEqual(area, bounds.width * bounds.height, accuracy: 1e-6)
    }

    // MARK: - The fade

    func testTheBackgroundLeavesQuicklyAndReturnsGently() {
        XCTAssertEqual(TrackAnnouncementSeeThrough.typingProgress(0, toward: 1, elapsed: 0.075), 0.5, accuracy: 1e-6, "opens over 0.15 s")
        XCTAssertEqual(TrackAnnouncementSeeThrough.typingProgress(0, toward: 1, elapsed: 0.2), 1)
        XCTAssertEqual(TrackAnnouncementSeeThrough.typingProgress(1, toward: 0, elapsed: 0.2), 0.5, accuracy: 1e-6, "closes over 0.4 s")
        XCTAssertEqual(TrackAnnouncementSeeThrough.typingProgress(1, toward: 0, elapsed: 1), 0)
        XCTAssertEqual(TrackAnnouncementSeeThrough.typingProgress(0.3, toward: 0.3, elapsed: 1), 0.3)
        XCTAssertEqual(TrackAnnouncementSeeThrough.typingProgress(0.3, toward: 1, elapsed: 0), 0.3, "no time, no change")
    }

    // MARK: - The typing window

    private let wide = CGRect(x: 0, y: 0, width: 2000, height: 150)

    func testTheTypingWindowIsCentredInTheStrip() throws {
        let window = try XCTUnwrap(TrackAnnouncementSeeThrough.typingWindow(in: wide, occupied: CGRect(x: 17, y: 20, width: 400, height: 110), radius: 360, feather: 144, centreHeight: 90, margin: 24, keepFeather: 48, progress: 0.25))

        XCTAssertEqual(window.hole.centre, CGPoint(x: 1000, y: 240), "across the middle, and 90 above the top edge")
        XCTAssertEqual(window.hole.radius, 360)
        XCTAssertEqual(window.hole.feather, 144)
        XCTAssertEqual(window.keepUntilX, 441, "the text's end plus the margin")
        XCTAssertEqual(window.keepFeather, 48)
        XCTAssertEqual(window.progress, 0.25)
    }

    func testTheTypingWindowCentreCanSitInsideTheStrip() throws {
        let window = try XCTUnwrap(TrackAnnouncementSeeThrough.typingWindow(in: wide, occupied: .null, radius: 360, feather: 144, centreHeight: -75, margin: 24, keepFeather: 48, progress: 1))
        XCTAssertEqual(window.hole.centre, CGPoint(x: 1000, y: 75), "a negative height puts it back in the strip's middle")
    }

    func testAClosedTypingWindowIsNone() {
        XCTAssertNil(TrackAnnouncementSeeThrough.typingWindow(in: wide, occupied: .zero, radius: 360, feather: 144, centreHeight: 90, margin: 24, keepFeather: 48, progress: 0))
        XCTAssertNil(TrackAnnouncementSeeThrough.typingWindow(in: wide, occupied: .zero, radius: 0, feather: 144, centreHeight: 90, margin: 24, keepFeather: 48, progress: 1))
    }

    func testTheKeptBackgroundStaysInsideTheStrip() throws {
        let long = try XCTUnwrap(TrackAnnouncementSeeThrough.typingWindow(in: wide, occupied: CGRect(x: 17, y: 20, width: 1990, height: 110), radius: 360, feather: 500, centreHeight: 90, margin: 24, keepFeather: 48, progress: 2))
        XCTAssertEqual(long.keepUntilX, 2000)
        XCTAssertEqual(long.hole.feather, 360, "the soft edge is never wider than the hole")
        XCTAssertEqual(long.progress, 1)

        let nothing = try XCTUnwrap(TrackAnnouncementSeeThrough.typingWindow(in: wide, occupied: .null, radius: 360, feather: 144, centreHeight: 90, margin: 24, keepFeather: 48, progress: 1))
        XCTAssertEqual(nothing.keepUntilX, 0, "nothing drawn, nothing kept")
    }

    func testTheTypingMaskClosesWithOneOpacity() throws {
        let mask = TrackAnnouncementTypingMask()
        let bounds = CGRect(x: 0, y: -12, width: 2000, height: 162)
        let window = TrackAnnouncementTypingWindow(
            hole: TrackAnnouncementPeephole(centre: CGPoint(x: 1000, y: 75), radius: 360, feather: 144),
            keepUntilX: 441.3, keepFeather: 48, progress: 0.25
        )

        mask.place(window, in: bounds, scale: 2)

        XCTAssertEqual(mask.frame, bounds)
        let layers = try XCTUnwrap(mask.sublayers)
        XCTAssertEqual(layers.count, 4)
        XCTAssertTrue(layers[0] is TrackAnnouncementPeepholeMask, "the hole")
        XCTAssertEqual(layers[0].frame, CGRect(origin: .zero, size: bounds.size))
        XCTAssertEqual(layers[1].frame, CGRect(x: 0, y: 0, width: 441.5, height: 162), "solid over the text, to a whole pixel")
        XCTAssertTrue(layers[2] is CAGradientLayer)
        XCTAssertEqual(layers[2].frame, CGRect(x: 441.5, y: 0, width: 48, height: 162), "then fading out")
        XCTAssertEqual(layers[3].frame, CGRect(origin: .zero, size: bounds.size))
        XCTAssertEqual(layers[3].opacity, 0.75, accuracy: 1e-6, "a quarter open: the fill is at three quarters")

        mask.place(TrackAnnouncementTypingWindow(hole: window.hole, keepUntilX: window.keepUntilX, keepFeather: 48, progress: 1), in: bounds, scale: 2)
        XCTAssertEqual(layers[3].opacity, 0, "fully open: no fill")
    }

    // MARK: - Typing

    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testAKeyPressedJustNowIsTyping() {
        var typing = TrackAnnouncementTyping()
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0.1, commandKeysHeld: false), at: start)

        XCTAssertTrue(typing.isTyping(at: start, pause: 1.5))
        XCTAssertTrue(typing.isTyping(at: start.addingTimeInterval(1.3), pause: 1.5))
        XCTAssertFalse(typing.isTyping(at: start.addingTimeInterval(1.5), pause: 1.5), "the pause runs from the key, not from when it was seen")
    }

    func testAKeyPressedLongBeforeTheStripIsNotTyping() {
        var typing = TrackAnnouncementTyping()
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 30, commandKeysHeld: false), at: start)

        XCTAssertFalse(typing.isTyping(at: start, pause: 1.5))
    }

    func testTheSameKeyReadAgainDoesNotRestartThePause() {
        var typing = TrackAnnouncementTyping()
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false), at: start)
        let first = typing.lastTypedAt

        // A frame later the same press reads a frame older, give or take a hair
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0.0167, commandKeysHeld: false), at: start.addingTimeInterval(0.0169))
        XCTAssertEqual(typing.lastTypedAt, first)
    }

    func testEachNewKeyRestartsThePause() {
        var typing = TrackAnnouncementTyping()
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false), at: start)
        let later = start.addingTimeInterval(1.2)
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0.01, commandKeysHeld: false), at: later)

        XCTAssertTrue(typing.isTyping(at: start.addingTimeInterval(2.5), pause: 1.5))
        XCTAssertFalse(typing.isTyping(at: start.addingTimeInterval(2.7), pause: 1.5))
    }

    func testAShortcutIsNotTyping() {
        var typing = TrackAnnouncementTyping()
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: true), at: start)
        XCTAssertFalse(typing.isTyping(at: start, pause: 1.5), "a rating shortcut must not clear the strip showing the rating")

        // The modifiers are let go while the same key's age keeps growing: still the shortcut
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0.1, commandKeysHeld: false), at: start.addingTimeInterval(0.1))
        XCTAssertFalse(typing.isTyping(at: start.addingTimeInterval(0.1), pause: 1.5))

        // A plain key after it is typing again
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0, commandKeysHeld: false), at: start.addingTimeInterval(0.5))
        XCTAssertTrue(typing.isTyping(at: start.addingTimeInterval(0.5), pause: 1.5))
    }

    func testAShortcutLetGoOfBeforeTheFirstReadingIsNotTyping() {
        // Command-Right Arrow in Music: the key went down 0.3 s ago, Command came up 0.1 s after
        // it, and by the time the strip reads the keyboard nothing is held
        var typing = TrackAnnouncementTyping()
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0.3, commandKeysHeld: false, secondsSinceModifierChange: 0.2), at: start)

        XCTAssertFalse(typing.isTyping(at: start, pause: 1.5))
    }

    func testAModifierPressedBeforeTheKeyStillTypes() {
        // Shift for a capital goes down before the letter, so it is older than the key
        var typing = TrackAnnouncementTyping()
        typing.observe(KeyboardActivity(secondsSinceKeyDown: 0.1, commandKeysHeld: false, secondsSinceModifierChange: 0.3), at: start)

        XCTAssertTrue(typing.isTyping(at: start, pause: 1.5))
    }

    func testOnlyCommandAndControlMakeAShortcut() {
        XCTAssertTrue(KeyboardActivity.isShortcut([.command]))
        XCTAssertTrue(KeyboardActivity.isShortcut([.control, .option]), "StarBar's own shortcuts")
        XCTAssertFalse(KeyboardActivity.isShortcut([.option]), "Option types characters: accents, and # on a British keyboard")
        XCTAssertFalse(KeyboardActivity.isShortcut([.shift]))
        XCTAssertFalse(KeyboardActivity.isShortcut([]))
    }

    func testANonsenseKeyAgeIsIgnored() {
        for age in [-1, TimeInterval.nan, TimeInterval.infinity] {
            var typing = TrackAnnouncementTyping()
            typing.observe(KeyboardActivity(secondsSinceKeyDown: age, commandKeysHeld: false), at: start)
            XCTAssertNil(typing.lastTypedAt, "\(age)")
            XCTAssertFalse(typing.isTyping(at: start, pause: 1.5), "\(age)")
        }
    }

    // MARK: - Knobs

    func testTheSeeThroughDefaults() {
        let knobs = TrackAnnouncementSeeThroughKnobs()
        XCTAssertTrue(knobs.peephole)
        XCTAssertEqual(knobs.radius, 270, "three times the first try, then half as big again, at Ross's request")
        XCTAssertEqual(knobs.feather, 108)
        XCTAssertTrue(knobs.typingWindow)
        XCTAssertEqual(knobs.typingRadius, 360, "bigger than the pointer's hole")
        XCTAssertEqual(knobs.typingFeather, 144)
        XCTAssertEqual(knobs.typingCentreHeight, 90, "above the strip, so the window scoops down into it")
        XCTAssertEqual(knobs.typingPause, 1.5)
    }

}
