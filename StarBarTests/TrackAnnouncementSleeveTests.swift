//
//  TrackAnnouncementSleeveTests.swift
//  StarBarTests
//
//  The break-out sleeve's rules: where it stands, that it fits the panel's headroom and
//  clears the text however it turns, which way the lean and the pointer turn it, and the
//  timing of its rise and of its following the pointer. The panel driving it is covered in
//  TrackAnnouncementPanelTests.
//

import XCTest
@testable import StarBar

final class TrackAnnouncementSleeveTests: XCTestCase {

    private typealias Sleeve = TrackAnnouncementSleeve
    private typealias Tilt = TrackAnnouncementSleeve.Tilt

    /// Every scale the strip is drawn at on real screens, and the cap
    private let scales: [CGFloat] = [1, 1.25, 1.44, 2]

    /// The pointer's turn at its extremes, each way about each axis and both together
    private var extremeTilts: [Tilt] {
        var tilts: [Tilt] = [.rest]
        for x in [-Sleeve.maxTilt, 0, Sleeve.maxTilt] {
            for y in [-Sleeve.maxTilt, 0, Sleeve.maxTilt] {
                tilts.append(Tilt(x: x, y: y, glare: 1))
            }
        }
        return tilts
    }

    /// The top of the rise's overshoot
    private var peakRise: CGFloat {
        return stride(from: 0.0, through: 1.0, by: 0.001).map { Sleeve.rise(elapsed: $0) }.max() ?? 1
    }

    /// The highest the rise takes the sleeve's scale
    private var riseScaleAtPeak: CGFloat {
        return Sleeve.riseScale(peakRise)
    }

    private func assertTransform(_ actual: CATransform3D, _ expected: CATransform3D, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let a = [actual.m11, actual.m12, actual.m13, actual.m14, actual.m21, actual.m22, actual.m23, actual.m24,
                 actual.m31, actual.m32, actual.m33, actual.m34, actual.m41, actual.m42, actual.m43, actual.m44]
        let e = [expected.m11, expected.m12, expected.m13, expected.m14, expected.m21, expected.m22, expected.m23, expected.m24,
                 expected.m31, expected.m32, expected.m33, expected.m34, expected.m41, expected.m42, expected.m43, expected.m44]
        for (index, pair) in zip(a, e).enumerated() {
            XCTAssertEqual(pair.0, pair.1, accuracy: 1e-6, "m\(index / 4 + 1)\(index % 4 + 1) \(message)", file: file, line: line)
        }
    }

    // MARK: - Where it stands

    func testTheSleeveStandsAboveTheStripAndFitsThePanel() {
        for scale in scales {
            let strip = TrackAnnouncementLayout.stripHeight(scale: scale)
            let panel = strip + TrackAnnouncementPlacement.panelHeadroom(scale: scale)
            let slot = Sleeve.slot(leadingX: 12 * scale, scale: scale)

            XCTAssertEqual(slot.minY, 12 * scale, accuracy: 0.001, "the flat artwork's gap below, at scale \(scale)")
            XCTAssertEqual(slot.width, 112 * scale, accuracy: 0.001)
            XCTAssertEqual(slot.height, slot.width, accuracy: 0.001)
            XCTAssertGreaterThan(slot.maxY, strip + 16 * scale, "it breaks out of the strip's top edge, at scale \(scale)")
            // The sleeve's view, margin and all, fits the panel: what spills over is clipped
            XCTAssertLessThanOrEqual(slot.maxY + Sleeve.margin * scale, panel + 0.001, "at scale \(scale)")
        }
    }

    func testTheSleeveTurnedAnyWayStaysInsideItsView() {
        for scale in scales {
            let size = CGSize(width: Sleeve.size * scale, height: Sleeve.size * scale)
            let room = Sleeve.margin * scale
            for tilt in extremeTilts {
                let turned = Sleeve.projectedBounds(of: size, tilt: tilt, scale: scale, riseScale: riseScaleAtPeak)
                // The rise's overshoot lifts it a little too
                let lift = -Sleeve.riseDrop(peakRise, scale: scale)
                XCTAssertGreaterThan(turned.minX, -size.width / 2 - room, "\(tilt) at scale \(scale)")
                XCTAssertLessThan(turned.maxX, size.width / 2 + room, "\(tilt) at scale \(scale)")
                XCTAssertGreaterThan(turned.minY, -size.height / 2 - room, "\(tilt) at scale \(scale)")
                XCTAssertLessThan(turned.maxY + lift, size.height / 2 + room, "\(tilt) at scale \(scale)")
            }
        }
    }

    func testTheTextClearsTheSleeveHoweverItTurns() {
        let stripSize = CGSize(width: 1600, height: 104)
        for scale in scales {
            let frames = TrackAnnouncementLayout.frames(in: CGSize(width: stripSize.width * scale, height: TrackAnnouncementLayout.stripHeight(scale: scale)), scale: scale, breakout: true)
            let size = CGSize(width: Sleeve.size * scale, height: Sleeve.size * scale)
            for tilt in extremeTilts {
                let turned = Sleeve.projectedBounds(of: size, tilt: tilt, scale: scale, riseScale: riseScaleAtPeak)
                let rightEdge = frames.artwork.midX + turned.maxX
                XCTAssertGreaterThanOrEqual(frames.title.minX - rightEdge, 8 * scale, "\(tilt) at scale \(scale)")
            }
        }
    }

    func testBreakoutMovesTheTextRightOfTheBiggerSleeve() {
        let size = CGSize(width: 1600, height: 104)
        let flat = TrackAnnouncementLayout.frames(in: size)
        let breakout = TrackAnnouncementLayout.frames(in: size, breakout: true)

        XCTAssertEqual(flat.artwork, CGRect(x: 12, y: 12, width: 80, height: 80))
        XCTAssertEqual(flat.title.minX, 12 + 80 + 16)
        XCTAssertEqual(breakout.artwork, CGRect(x: 12, y: 12, width: 112, height: 112))
        XCTAssertEqual(breakout.title.minX, 12 + 124)
        XCTAssertEqual(breakout.title.maxX, flat.title.maxX, "the text keeps its right end")

        // A Dock at the left and a bigger screen move both together
        let scaled = TrackAnnouncementLayout.frames(in: CGSize(width: 3200, height: 208), scale: 2, leadingInset: 30, breakout: true)
        XCTAssertEqual(scaled.artwork, CGRect(x: 30 + 24, y: 24, width: 224, height: 224))
        XCTAssertEqual(scaled.title.minX, 30 + 24 + 248)
    }

    // MARK: - Turning

    /// The corners of a turned sleeve, relative to its centre: bottom left, bottom right, top
    /// right, top left
    private func corners(_ tilt: Tilt) -> [CGPoint] {
        return Sleeve.projectedCorners(of: CGSize(width: Sleeve.size, height: Sleeve.size), tilt: tilt)
    }

    func testTheLeanFacesTheText() {
        let turned = corners(.rest)
        let leftEdge = turned[3].y - turned[0].y
        let rightEdge = turned[2].y - turned[1].y

        XCTAssertGreaterThan(leftEdge, rightEdge + 4, "the left edge is nearer, so the sleeve faces right, towards the text")
        XCTAssertLessThan(turned[1].x - turned[0].x, Sleeve.size, "and it is foreshortened")
    }

    func testThePointerNeverTurnsTheSleeveAwayFromTheText() {
        for tilt in extremeTilts {
            let turned = corners(tilt)
            XCTAssertGreaterThan(turned[3].y - turned[0].y, turned[2].y - turned[1].y, "\(tilt)")
        }
    }

    func testTheSleeveFacesThePointer() {
        let base = corners(.rest)

        // The pointer above: the top tips away, so the sleeve faces up and its top edge narrows
        let up = corners(Sleeve.tilt(pointerOffset: CGVector(dx: 0, dy: Sleeve.tiltSpan)))
        XCTAssertLessThan(up[2].x - up[3].x, base[2].x - base[3].x)
        XCTAssertGreaterThan(up[1].x - up[0].x, base[1].x - base[0].x)

        // The pointer to the right: it turns further right, and the right edge shrinks more
        let right = corners(Sleeve.tilt(pointerOffset: CGVector(dx: Sleeve.tiltSpan, dy: 0)))
        XCTAssertLessThan(right[2].y - right[1].y, base[2].y - base[1].y)
    }

    func testThePerspectiveLooksTheSameAtEveryScale() {
        let tilt = Tilt(x: 6, y: -4, glare: 1)
        let one = Sleeve.projectedBounds(of: CGSize(width: Sleeve.size, height: Sleeve.size), tilt: tilt)
        let two = Sleeve.projectedBounds(of: CGSize(width: Sleeve.size * 2, height: Sleeve.size * 2), tilt: tilt, scale: 2)

        XCTAssertEqual(two.width, one.width * 2, accuracy: 0.001)
        XCTAssertEqual(two.height, one.height * 2, accuracy: 0.001)
        XCTAssertEqual(two.minX, one.minX * 2, accuracy: 0.001)
    }

    // MARK: - Following the pointer

    func testAFarPointerLeavesTheSleeveAtRest() {
        XCTAssertEqual(Sleeve.tilt(pointerOffset: CGVector(dx: Sleeve.tiltReach, dy: 0)), .rest)
        XCTAssertEqual(Sleeve.tilt(pointerOffset: CGVector(dx: 0, dy: -400)), .rest)
        XCTAssertEqual(Sleeve.tilt(pointerOffset: CGVector(dx: 200, dy: 200)), .rest, "283 points off, past the reach")
    }

    func testThePointerTurnsTheSleeveAtMostTheMaximum() {
        let full = Sleeve.tilt(pointerOffset: CGVector(dx: Sleeve.tiltSpan, dy: 0))
        XCTAssertEqual(full.y, Sleeve.maxTilt, accuracy: 0.001)
        XCTAssertEqual(full.x, 0, accuracy: 0.001)
        XCTAssertEqual(full.glare, 1, accuracy: 0.001)

        let above = Sleeve.tilt(pointerOffset: CGVector(dx: 0, dy: Sleeve.tiltSpan))
        XCTAssertEqual(above.x, -Sleeve.maxTilt, accuracy: 0.001, "the top tips away from the viewer, to face up")

        for dx in stride(from: -300.0, through: 300.0, by: 25.0) {
            for dy in stride(from: -300.0, through: 300.0, by: 25.0) {
                let tilt = Sleeve.tilt(pointerOffset: CGVector(dx: dx, dy: dy))
                XCTAssertLessThanOrEqual(abs(tilt.x), Sleeve.maxTilt + 0.001)
                XCTAssertLessThanOrEqual(abs(tilt.y), Sleeve.maxTilt + 0.001)
                XCTAssertTrue((0...1).contains(tilt.glare))
                XCTAssertTrue((0...1).contains(tilt.glareCentre.x))
                XCTAssertTrue((0...1).contains(tilt.glareCentre.y))
            }
        }
    }

    func testTheTiltFadesOutBeforeThePointerLeaves() {
        let near = Sleeve.tilt(pointerOffset: CGVector(dx: 160, dy: 0))
        let farther = Sleeve.tilt(pointerOffset: CGVector(dx: 220, dy: 0))
        let edge = Sleeve.tilt(pointerOffset: CGVector(dx: 268, dy: 0))

        XCTAssertEqual(near.y, Sleeve.maxTilt, accuracy: 0.001)
        XCTAssertLessThan(farther.y, near.y)
        XCTAssertLessThan(edge.y, 0.5, "next to nothing just inside the reach, so leaving doesn't snap it")
    }

    func testTheGlareGoesToThePointersSide() {
        let right = Sleeve.tilt(pointerOffset: CGVector(dx: Sleeve.glareSpan, dy: 0))
        XCTAssertEqual(right.glareCentre.x, 1, accuracy: 0.001)
        XCTAssertEqual(right.glareCentre.y, 0.5, accuracy: 0.001)

        let belowLeft = Sleeve.tilt(pointerOffset: CGVector(dx: -45, dy: -45))
        XCTAssertEqual(belowLeft.glareCentre.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(belowLeft.glareCentre.y, 0.25, accuracy: 0.001)
    }

    func testFollowingThePointerIsTheSameAtAnyFrameRate() {
        let target = Tilt(x: 10, y: -10, glare: 1, glareCentre: CGPoint(x: 1, y: 0))

        let once = Sleeve.approach(.rest, toward: target, elapsed: 0.1)
        let twice = Sleeve.approach(Sleeve.approach(.rest, toward: target, elapsed: 0.05), toward: target, elapsed: 0.05)

        XCTAssertEqual(once.x, twice.x, accuracy: 0.0001)
        XCTAssertEqual(once.y, twice.y, accuracy: 0.0001)
        XCTAssertEqual(once.glare, twice.glare, accuracy: 0.0001)
        XCTAssertEqual(once.glareCentre.x, twice.glareCentre.x, accuracy: 0.0001)
        XCTAssertGreaterThan(once.x, 5, "most of the way in a tenth of a second")
        XCTAssertLessThan(once.x, 10)
    }

    func testFollowingThePointerComesToRest() {
        let target = Tilt(x: -7, y: 4, glare: 0.6, glareCentre: CGPoint(x: 0.2, y: 0.9))
        var tilt = Tilt.rest
        var frames = 0
        while tilt != target && frames < 600 {
            tilt = Sleeve.approach(tilt, toward: target, elapsed: 1.0 / 60.0)
            frames += 1
        }

        XCTAssertEqual(tilt, target, "it snaps the last fraction, so the panel can stop setting the transform")
        XCTAssertLessThan(frames, 60, "within a second")
        XCTAssertEqual(Sleeve.approach(tilt, toward: target, elapsed: 0), target)
        XCTAssertEqual(Sleeve.approach(.rest, toward: target, elapsed: 0), .rest, "no time, no move")
    }

    // MARK: - Rising

    func testTheRiseWaitsOvershootsAndLands() {
        XCTAssertEqual(Sleeve.rise(elapsed: 0), 0)
        XCTAssertEqual(Sleeve.rise(elapsed: Sleeve.riseDelay), 0, "sunk into the strip until the delay")
        XCTAssertEqual(Sleeve.rise(elapsed: Sleeve.riseDelay + Sleeve.riseDuration), 1)
        XCTAssertEqual(Sleeve.rise(elapsed: 5), 1)

        let samples = stride(from: Sleeve.riseDelay, through: Sleeve.riseDelay + Sleeve.riseDuration, by: 0.005).map { Sleeve.rise(elapsed: $0) }
        let peak = samples.max() ?? 0
        XCTAssertGreaterThan(peak, 1.03, "a little past its place")
        XCTAssertLessThan(peak, 1.1)
        let peakIndex = samples.firstIndex(of: peak) ?? 0
        XCTAssertEqual(samples[..<peakIndex].sorted(), Array(samples[..<peakIndex]), "up all the way to the peak")
    }

    func testTheRiseStartsSmallerAndLower() {
        XCTAssertEqual(Sleeve.riseScale(0), Sleeve.riseStartScale)
        XCTAssertEqual(Sleeve.riseScale(1), 1)
        XCTAssertEqual(Sleeve.riseDrop(1), 0)
        XCTAssertEqual(Sleeve.riseDrop(0), Sleeve.riseDistance)
        XCTAssertEqual(Sleeve.riseDrop(0, scale: 2), Sleeve.riseDistance * 2)
        XCTAssertLessThan(Sleeve.riseDrop(1.05), 0, "the overshoot lifts it above its place")
    }

    func testARiseFromPartWayStartsWhereTheSleeveIsAndLands() {
        XCTAssertEqual(Sleeve.rise(elapsed: 0, from: 0.4), 0.4, accuracy: 0.0001, "no jump when the strip turns round")
        XCTAssertEqual(Sleeve.rise(elapsed: Sleeve.riseDelay, from: 0.4), 0.4, accuracy: 0.0001)
        XCTAssertEqual(Sleeve.rise(elapsed: Sleeve.riseDelay + Sleeve.riseDuration, from: 0.4), 1, accuracy: 0.0001)
    }

    func testTheSinkFollowsTheSlideOut() {
        XCTAssertEqual(Sleeve.sink(from: 1, eased: 0), 1)
        XCTAssertEqual(Sleeve.sink(from: 1, eased: 0.5), 0.5)
        XCTAssertEqual(Sleeve.sink(from: 1, eased: 1), 0, "sunk all the way when the strip is out of sight")
        XCTAssertEqual(Sleeve.sink(from: 0.6, eased: 0.5), 0.3, accuracy: 0.0001, "from part way through a rise")
        XCTAssertEqual(Sleeve.sink(from: 1, eased: 1.2), 0)
    }

    /// The sleeve stands taller than the strip, so it has to sink into it on the way out:
    /// riding down with the strip alone left its top 27 points up the screen when the strip
    /// had gone, about 80% of the way down, until the panel was taken away
    func testASunkSleeveIsOutOfSightOnceTheStripIs() {
        for scale in scales {
            let strip = TrackAnnouncementLayout.stripHeight(scale: scale)
            for tilt in extremeTilts {
                XCTAssertLessThan(Sleeve.top(rise: 0, tilt: tilt, scale: scale), strip, "\(tilt) at scale \(scale)")
                XCTAssertGreaterThan(Sleeve.top(rise: 1, tilt: tilt, scale: scale), strip + 16 * scale, "it breaks out when up: \(tilt) at scale \(scale)")
            }
        }
    }

    // MARK: - The view

    /// A cover that draws, as one read from Music or downloaded does
    private func cover(width: CGFloat, height: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
    }

    func testTheViewDrawsTheCoverOverThePlaceholderAsItFades() {
        let view = TrackAnnouncementSleeveView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
        XCTAssertEqual(view.coverOpacity, 0, "no cover yet; the placeholder shows")
        XCTAssertEqual(view.placeholderOpacity, 1)

        view.artwork = cover(width: 600, height: 600)
        view.coverFade = 0
        XCTAssertEqual(view.coverOpacity, 0)
        XCTAssertEqual(view.placeholderOpacity, 1)
        view.coverFade = 0.4
        XCTAssertEqual(view.coverOpacity, 0.4, accuracy: 0.001)
        XCTAssertEqual(view.placeholderOpacity, 1, "whole under the cover, or the sleeve is see-through halfway")
        view.coverFade = 1
        XCTAssertEqual(view.coverOpacity, 1)
        XCTAssertEqual(view.placeholderOpacity, 0, "gone once the cover is all there")

        view.artwork = nil
        XCTAssertEqual(view.placeholderOpacity, 1, "back when the cover goes")
    }

    func testThePlaceholderIsOpaque() {
        // The sleeve stands above the strip, over whatever window is behind the panel
        let view = TrackAnnouncementSleeveView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
        XCTAssertEqual(view.placeholderFillAlphas.count, 2)
        XCTAssertTrue(view.placeholderFillAlphas.allSatisfy { $0 == 1 }, "\(view.placeholderFillAlphas)")
    }

    func testTheViewTurnsItsSleeveAndHidesTheGlareWhenAsked() {
        let view = TrackAnnouncementSleeveView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
        let tilt = Tilt(x: 5, y: -5, glare: 0.8)
        assertTransform(view.turnedLayer.transform, Sleeve.transform(.rest), "leaning even at rest")
        XCTAssertEqual(view.glareOpacity, 0)

        view.tilt = tilt
        assertTransform(view.turnedLayer.transform, Sleeve.transform(tilt))
        XCTAssertEqual(view.glareOpacity, 0.8, accuracy: 0.001)

        view.showsGlare = false
        XCTAssertEqual(view.glareOpacity, 0, "no translucent wash under Reduce Transparency")
        assertTransform(view.turnedLayer.transform, Sleeve.transform(tilt), "but it still turns")
    }

    func testTheViewsSleeveRisesAndShrinksWithTheRise() {
        let view = TrackAnnouncementSleeveView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
        XCTAssertEqual(view.turnedLayer.position, CGPoint(x: view.slot.midX, y: view.slot.midY), "in place")

        view.rise = 0
        XCTAssertEqual(view.turnedLayer.position.x, view.slot.midX)
        XCTAssertEqual(view.turnedLayer.position.y, view.slot.midY - Sleeve.riseDistance, accuracy: 0.001, "sunk")
        assertTransform(view.turnedLayer.transform, Sleeve.transform(.rest, riseScale: Sleeve.riseStartScale), "and smaller")

        view.scale = 2
        XCTAssertEqual(view.turnedLayer.position.y, view.sleeveRect.midY - Sleeve.riseDistance * 2, accuracy: 0.001, "by twice as much at twice the scale")

        view.rise = 1
        XCTAssertEqual(view.turnedLayer.position.y, view.sleeveRect.midY, accuracy: 0.001)
        assertTransform(view.turnedLayer.transform, Sleeve.transform(.rest, scale: 2), "and full size")
    }

    func testTheViewKeepsAWideCoverInsideTheSquare() {
        let view = TrackAnnouncementSleeveView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
        XCTAssertEqual(view.slot, CGRect(x: 28, y: 28, width: 112, height: 112))
        XCTAssertEqual(view.sleeveRect, view.slot)

        view.artwork = cover(width: 1200, height: 600)
        XCTAssertEqual(view.sleeveRect.width, 112, accuracy: 0.5)
        XCTAssertEqual(view.sleeveRect.height, 56, accuracy: 0.5)
        XCTAssertEqual(view.sleeveRect.midY, view.slot.midY, accuracy: 0.5)
    }

    /// AppKit hands the view's alpha, visibility and frame straight to its own root layer, which
    /// has no delegate, so once that layer is in a window's layer tree each change ran Core
    /// Animation's 0.25 s implicit animation: measured on macOS 27.2, a fade stepped at 60 Hz was
    /// drawn at 34% when it should have been fully in. A layer that has never been committed to a
    /// tree answers no action on any macOS, which is why asking a lone view, or one in the panel
    /// without turning the run loop, passed without the fix. So the view goes into a window and the
    /// transaction is committed first.
    func testTheSleevesOwnLayerRunsNoImplicitAnimations() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = NSView(frame: window.contentLayoutRect)
        content.wantsLayer = true
        window.contentView = content
        let view = TrackAnnouncementSleeveView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
        content.addSubview(view)
        CATransaction.flush()

        XCTAssertNotNil(view.layer?.superlayer, "the layer is in the window's tree, or the check below proves nothing")
        for key in ["opacity", "hidden", "position", "bounds"] {
            XCTAssertNil(view.layer?.action(forKey: key), "\(key) is stepped on the panel's clock, never animated by Core Animation")
        }
    }

    func testTheSleeveTakesNoClicks() {
        let view = TrackAnnouncementSleeveView(frame: NSRect(x: 0, y: 0, width: 168, height: 168))
        XCTAssertNil(view.hitTest(NSPoint(x: 84, y: 84)))
    }
}
