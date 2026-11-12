//
//  HeartBurstTests.swift
//  StarBarTests
//
//  The heart's change after a click, as pure timing: the burst when it is set, the dip when it
//  is cleared, the cross-fade under Reduce Motion, and where the burst's ring and dots go.
//

import XCTest
@testable import StarBar

final class HeartBurstTests: XCTestCase {

    private let menuBar = HeartBurst.menuBar(heartSize: 16)
    private let strip = HeartBurst.strip(heartSize: 12)

    /// Every frame of a change at 60 Hz, and one past its end
    private func frames(over duration: TimeInterval) -> [TimeInterval] {
        return stride(from: 0, through: duration + 1.0 / 60.0, by: 1.0 / 60.0).map { $0 }
    }

    // MARK: - Which change

    func testASetHeartBurstsAndAClearedOneDips() {
        XCTAssertEqual(HeartChange(favorited: true, reduceMotion: false), .burst)
        XCTAssertEqual(HeartChange(favorited: false, reduceMotion: false), .dip, "never a burst for taking a heart away")
    }

    func testReduceMotionCrossFadesEitherWay() {
        XCTAssertEqual(HeartChange(favorited: true, reduceMotion: true), .fade)
        XCTAssertEqual(HeartChange(favorited: false, reduceMotion: true), .fade)
    }

    func testEachChangeEndsWithTheNewHeartAtRestAndTheOldOneGone() {
        for change in [HeartChange.burst, .dip, .fade] {
            XCTAssertEqual(change.incoming(at: change.duration), .rest, "\(change)")
            XCTAssertFalse(change.outgoing(at: change.duration).isVisible, "\(change)")
        }
        XCTAssertEqual(HeartChange.burst.duration, 0.8, accuracy: 0.0001)
        XCTAssertLessThan(HeartChange.dip.duration, 0.3, "a quiet change for a heart taken away")
        XCTAssertLessThan(HeartChange.fade.duration, 0.2)
    }

    // MARK: - The burst

    func testTheOutlineShrinksAwayBeforeTheFilledHeartPops() {
        XCTAssertEqual(HeartChange.burst.outgoing(at: 0), .rest, "the outline is all there on the first frame")
        XCTAssertFalse(HeartChange.burst.outgoing(at: HeartChange.outlineShrinkDuration).isVisible)
        XCTAssertFalse(HeartChange.burst.incoming(at: 0).isVisible)
        XCTAssertFalse(HeartChange.burst.incoming(at: HeartBurst.popStart).isVisible, "nothing until the ring has hollowed")
        for elapsed in frames(over: HeartBurst.popStart) {
            XCTAssertFalse(HeartChange.burst.outgoing(at: elapsed).isVisible && HeartChange.burst.incoming(at: elapsed).isVisible,
                           "never both at once, at \(elapsed) s")
        }
    }

    func testThePopOvershootsThenSettles() {
        let scales = frames(over: HeartBurst.duration).map { HeartChange.burst.incoming(at: $0).scale }
        let peak = scales.max() ?? 0
        XCTAssertGreaterThan(peak, 1.2, "a pop, not a grow")
        XCTAssertLessThan(peak, 1.35, "or it would leave the menu bar item, which clips it")
        XCTAssertEqual(HeartBurst.popScale(at: HeartBurst.popStart + 0.16), 1.28, accuracy: 0.001)
        XCTAssertLessThan(HeartBurst.popScale(at: HeartBurst.popStart + 0.3), 1, "and back under")
        XCTAssertEqual(HeartBurst.popScale(at: 0.74), 1, accuracy: 0.001, "settled before the dots have gone")
    }

    func testTheRingSwellsHollowsAndHasGoneWellBeforeTheEnd() throws {
        XCTAssertNil(menuBar.ring(at: 0))
        let early = try XCTUnwrap(menuBar.ring(at: 0.1))
        XCTAssertEqual(early.innerRadius, 0, "a disc at first")
        XCTAssertGreaterThan(early.outerRadius, 0)
        let later = try XCTUnwrap(menuBar.ring(at: 0.25))
        XCTAssertGreaterThan(later.innerRadius, 0, "then a ring")
        XCTAssertGreaterThan(later.colourMix, early.colourMix, "turning from the heart's colour")
        XCTAssertNil(menuBar.ring(at: 0.4))
        for elapsed in frames(over: HeartBurst.duration) {
            guard let ring = menuBar.ring(at: elapsed) else { continue }
            XCTAssertLessThanOrEqual(ring.innerRadius, ring.outerRadius)
            XCTAssertLessThanOrEqual(ring.outerRadius, HeartBurst.ringScale * 16 + 0.001)
        }
    }

    func testSevenPairsOfDotsFlyOutAndShrinkAway() throws {
        XCTAssertTrue(menuBar.dots(at: 0.1).isEmpty, "not before the ring has swollen")
        let midway = menuBar.dots(at: 0.5)
        XCTAssertEqual(midway.count, 2 * HeartBurst.pairCount)
        XCTAssertEqual(midway.filter { $0.isLead }.count, HeartBurst.pairCount)
        XCTAssertTrue(menuBar.dots(at: HeartBurst.duration).isEmpty)

        func distance(_ dot: HeartBurst.Dot) -> CGFloat { return hypot(dot.offset.dx, dot.offset.dy) }
        let lead = { (elapsed: TimeInterval) in self.menuBar.dots(at: elapsed).first { $0.isLead && $0.pair == 3 } }
        let a = try XCTUnwrap(lead(0.3)), b = try XCTUnwrap(lead(0.5)), c = try XCTUnwrap(lead(0.75))
        XCTAssertLessThan(distance(a), distance(b), "outwards")
        XCTAssertLessThan(distance(b), distance(c))
        XCTAssertEqual(distance(c), menuBar.reach, accuracy: 0.5, "to their reach")
        XCTAssertLessThan(c.radius, b.radius, "shrinking as they go")
    }

    func testNothingIsDrawnBeyondTheExtentSoAViewCanBeSizedToIt() {
        for burst in [menuBar, strip] {
            for elapsed in frames(over: HeartBurst.duration) {
                if let ring = burst.ring(at: elapsed) {
                    XCTAssertLessThanOrEqual(ring.outerRadius, burst.extent)
                }
                for dot in burst.dots(at: elapsed) {
                    XCTAssertLessThanOrEqual(hypot(dot.offset.dx, dot.offset.dy) + dot.radius, burst.extent + 0.001)
                }
            }
        }
    }

    /// The screen's top edge is 12 points above the heart on a 24 point menu bar, and nothing
    /// can be drawn above it
    func testTheMenuBarsDotsStayUnderTheScreensTopEdge() {
        var highest: CGFloat = -.infinity
        for elapsed in frames(over: HeartBurst.duration) {
            for dot in menuBar.dots(at: elapsed) {
                highest = max(highest, dot.offset.dy + dot.radius)
            }
        }
        XCTAssertLessThan(highest, 12)
        XCTAssertGreaterThan(highest, 0, "but the fan still reaches up the sides")
    }

    /// The strip's panel ends at the strip's bottom edge, so its dots fly up and to the sides
    func testTheStripsDotsStayAboveItsBottomEdgeAndInsideThePanel() {
        let size = CGSize(width: 1280, height: TrackAnnouncementLayout.height)
        let panelHeight = TrackAnnouncementLayout.height + TrackAnnouncementPlacement.panelHeadroom(scale: 1)
        for (hasArtist, hasAlbum) in [(true, true), (false, false)] {
            let rating = TrackAnnouncementLayout.frames(in: size, hasArtist: hasArtist, hasAlbum: hasAlbum, breakout: true).rating
            for elapsed in frames(over: HeartBurst.duration) {
                for dot in strip.dots(at: elapsed) {
                    XCTAssertGreaterThan(rating.midY + dot.offset.dy - dot.radius, 0)
                    XCTAssertLessThan(rating.midY + dot.offset.dy + dot.radius, panelHeight)
                }
            }
        }
    }

    func testTheStripsBurstIsBiggerForItsSize() {
        XCTAssertGreaterThan(strip.reach / strip.heartSize, menuBar.reach / menuBar.heartSize)
        XCTAssertGreaterThan(strip.leadDotRadius / strip.heartSize, menuBar.leadDotRadius / menuBar.heartSize)
    }

    // MARK: - The dip and the fade

    func testTheDipShrinksBothHeartsAndBringsTheNewOneBackWithoutGrowing() {
        let scales = frames(over: HeartChange.dipDuration).map { HeartChange.dip.incoming(at: $0).scale }
        XCTAssertLessThanOrEqual(scales.max() ?? 2, 1)
        XCTAssertEqual(scales.min() ?? 0, HeartChange.dipScale, accuracy: 0.01)
        for elapsed in frames(over: HeartChange.dipDuration) {
            XCTAssertEqual(HeartChange.dip.outgoing(at: elapsed).scale, HeartChange.dip.incoming(at: elapsed).scale,
                           "one heart dipping, the colour draining out of it")
        }
        XCTAssertEqual(HeartChange.dip.outgoing(at: 0).opacity, 1)
        XCTAssertEqual(HeartChange.dip.incoming(at: 0).opacity, 0)
    }

    func testTheFadeKeepsTheHeartsSize() {
        for elapsed in frames(over: HeartChange.fadeDuration) {
            XCTAssertEqual(HeartChange.fade.incoming(at: elapsed).scale, 1)
            XCTAssertEqual(HeartChange.fade.outgoing(at: elapsed).scale, 1)
            XCTAssertEqual(HeartChange.fade.incoming(at: elapsed).opacity + HeartChange.fade.outgoing(at: elapsed).opacity, 1, accuracy: 0.001)
        }
    }

    func testAGlyphScalesItsSlotAboutTheCentre() {
        let slot = NSRect(x: 10, y: 20, width: 16, height: 16)
        XCTAssertEqual(HeartGlyph.rest.frame(for: slot), slot)
        let half = HeartGlyph(scale: 0.5, opacity: 1).frame(for: slot)
        XCTAssertEqual(half, NSRect(x: 14, y: 24, width: 8, height: 8))
    }

    // MARK: - Colours

    func testTheRingStartsInTheHeartsOwnColour() {
        XCTAssertEqual(HeartBurstPalette.music.ringStart, Stars.favoriteHeartColor)
        XCTAssertEqual(HeartBurstPalette.spotify.ringStart, Stars.spotifyHeartColor)
        XCTAssertEqual(HeartBurstPalette.music.pairs.count, HeartBurst.pairCount)
        XCTAssertEqual(HeartBurstPalette.spotify.pairs.count, HeartBurst.pairCount)
    }

}
