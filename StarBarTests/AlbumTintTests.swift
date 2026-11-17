//
//  AlbumTintTests.swift
//  StarBarTests
//
//  The strip's album tint: the OKLab conversions, the "vivid" picker, the rule that keeps
//  white text readable on the colour, and the premultiplied mix the fades step through.
//  Pure, so it runs anywhere.
//

import XCTest
@testable import StarBar

final class AlbumTintTests: XCTestCase {

    private let red = OKLab(red: 1, green: 0, blue: 0)
    private let blue = OKLab(red: 0, green: 0, blue: 1)
    private let black = OKLab(red: 0, green: 0, blue: 0)
    private let white = OKLab(red: 1, green: 1, blue: 1)
    private let grey = OKLab(red: 0.5, green: 0.5, blue: 0.5)

    // MARK: OKLab

    /// Björn Ottosson's own figures for sRGB red, white and black
    func testOKLabMatchesThePublishedValues() {
        XCTAssertEqual(red.l, 0.628, accuracy: 0.001)
        XCTAssertEqual(red.a, 0.225, accuracy: 0.001)
        XCTAssertEqual(red.b, 0.126, accuracy: 0.001)
        XCTAssertEqual(white.l, 1, accuracy: 0.0001)
        XCTAssertEqual(white.chroma, 0, accuracy: 0.0001)
        XCTAssertEqual(black.l, 0, accuracy: 0.0001)
        XCTAssertEqual(grey.chroma, 0, accuracy: 0.0001, "a grey has no colour")
    }

    func testOKLabRoundTripsSRGB() {
        let colours: [(Double, Double, Double)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (0.2, 0.4, 0.6), (0.9, 0.8, 0.1), (0.5, 0.5, 0.5), (0, 0, 0), (1, 1, 1)]
        for (r, g, b) in colours {
            let back = OKLab(red: r, green: g, blue: b).sRGB
            XCTAssertEqual(back.red, r, accuracy: 0.0001, "\((r, g, b))")
            XCTAssertEqual(back.green, g, accuracy: 0.0001, "\((r, g, b))")
            XCTAssertEqual(back.blue, b, accuracy: 0.0001, "\((r, g, b))")
            XCTAssertTrue(OKLab(red: r, green: g, blue: b).isInSRGB)
        }
        XCTAssertFalse(OKLab(l: 0.5, a: 0.4, b: 0).isInSRGB, "far more red than a screen shows")
    }

    func testContrastWithWhiteIsWCAGs() {
        XCTAssertEqual(black.contrastWithWhite, 21, accuracy: 0.01)
        XCTAssertEqual(white.contrastWithWhite, 1, accuracy: 0.01)
        XCTAssertEqual(OKLab(l: 0.5, a: 0, b: 0).contrastWithWhite, 6, accuracy: 0.01, "OKLab's grey at 0.5 is 12.5% luminance")
    }

    // MARK: The vivid picker

    private func cover(_ parts: (OKLab, Int)...) -> [OKLab] {
        return parts.flatMap { Array(repeating: $0.0, count: $0.1) }
    }

    func testACoverWithNoColourGivesNoTint() {
        XCTAssertNil(AlbumTint.vivid([]))
        XCTAssertNil(AlbumTint.vivid(cover((grey, 1024))))
        XCTAssertNil(AlbumTint.vivid(cover((black, 512), (white, 512))), "black and white")
        XCTAssertNil(AlbumTint.vivid(cover((OKLab(red: 0.6, green: 0.57, blue: 0.52), 1024))), "a pale sepia is too little colour")
    }

    func testASmallAccentOnBlackCountsOnceThereIsEnoughOfIt() throws {
        let accent = try XCTUnwrap(AlbumTint.vivid(cover((red, 51), (black, 973))), "a red 5% of a black cover")
        XCTAssertEqual(accent.hue, red.hue, accuracy: 0.001)
        XCTAssertNil(AlbumTint.vivid(cover((red, 20), (black, 1004))), "2% is a speck, not the cover's colour")
    }

    func testGreysAndWhitesDontOutvoteTheColour() throws {
        let picked = try XCTUnwrap(AlbumTint.vivid(cover((white, 717), (red, 307))))
        XCTAssertEqual(picked.l, red.l, accuracy: 0.001, "the red, not a mix with the white border")
        XCTAssertEqual(picked.hue, red.hue, accuracy: 0.001)
    }

    func testAVividColourBeatsALargerDullOne() throws {
        let dull = OKLab(l: 0.6, a: -0.02, b: -0.045)
        XCTAssertGreaterThan(dull.chroma, AlbumTint.minimumChroma)
        let picked = try XCTUnwrap(AlbumTint.vivid(cover((dull, 512), (red, 205), (black, 307))))
        XCTAssertEqual(picked.hue, red.hue, accuracy: 0.001, "a fifth of the cover in red beats half in a dusty blue")
    }

    func testAColourSplitAcrossTwoSlicesIsNotHalved() throws {
        // 29° and 31° fall in neighbouring 15° slices; either alone is less than the green
        let angle = { (degrees: Double) in OKLab(l: 0.6, a: 0.15 * cos(degrees * .pi / 180), b: 0.15 * sin(degrees * .pi / 180)) }
        let green = OKLab(red: 0.3, green: 0.7, blue: 0.3)
        let picked = try XCTUnwrap(AlbumTint.vivid(cover((angle(29), 250), (angle(31), 250), (green, 300), (black, 224))))
        XCTAssertEqual(picked.hue * 180 / .pi, 30, accuracy: 0.5, "the two halves together outweigh the green")
    }

    // MARK: Legibility

    func testEveryTintKeepsWhiteTextReadableAndItsHue() {
        for degrees in stride(from: 0.0, to: 360, by: 5) {
            for l in [0.05, 0.2, 0.3, 0.45, 0.6, 0.8, 0.95] {
                for chroma in [0.05, 0.1, 0.2, 0.35] {
                    let hue = degrees * .pi / 180
                    let colour = OKLab(l: l, a: chroma * cos(hue), b: chroma * sin(hue))
                    let tint = AlbumTint.legible(colour)
                    let context = "hue \(degrees)°, L \(l), C \(chroma)"
                    XCTAssertTrue(tint.isInSRGB, context)
                    XCTAssertTrue(AlbumTint.lightness.contains(tint.l), context)
                    XCTAssertLessThanOrEqual(tint.chroma, AlbumTint.maximumChroma + 1e-9, context)
                    XCTAssertGreaterThanOrEqual(tint.contrastWithWhite, 4.5, context)
                    XCTAssertGreaterThan(tint.chroma, 0, context)
                    let turned = abs(remainder(tint.hue - colour.hue, 2 * .pi))
                    XCTAssertLessThan(turned, 1e-6, "the hue is kept: \(context)")
                }
            }
        }
    }

    func testADarkColourIsLiftedButAGreyIsOnlyCapped() {
        XCTAssertEqual(AlbumTint.legible(OKLab(l: 0.18, a: -0.02, b: -0.1)).l, AlbumTint.lightness.lowerBound, accuracy: 1e-9, "navy reads as navy, not black")
        XCTAssertEqual(AlbumTint.legible(OKLab(l: 0.1, a: 0, b: 0)).l, 0.1, accuracy: 1e-9, "a near-black stays near black")
        XCTAssertEqual(AlbumTint.legible(OKLab(l: 0.9, a: 0, b: 0)).l, AlbumTint.lightness.upperBound, accuracy: 1e-9, "a pale grey is darkened for the white text")
        XCTAssertEqual(AlbumTint.legible(red).l, AlbumTint.lightness.upperBound, accuracy: 1e-9)
    }

    // MARK: Covers

    /// A `size` by `size` sRGB image filled by `fill`, as a cover read from Music would be
    private func image(size: Int = 40, _ fill: (CGContext) -> Void) throws -> NSImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        fill(context)
        let cgImage = try XCTUnwrap(context.makeImage())
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    func testTheColourOfACover() throws {
        let redAndBlack = try image { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            context.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 16))
        }
        let tint = try XCTUnwrap(AlbumTint.colour(of: redAndBlack))
        XCTAssertEqual(tint.hue, OKLab(red: 0.8, green: 0.1, blue: 0.1).hue, accuracy: 0.02, "the red band's hue")
        XCTAssertGreaterThanOrEqual(tint.contrastWithWhite, 4.5)

        let greyCover = try image { context in
            context.setFillColor(CGColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        XCTAssertNil(AlbumTint.colour(of: greyCover))
    }

    /// The Preview's cover is the app icon, with see-through corners: they are not black
    func testSeeThroughPartsOfACoverDontCount() throws {
        let halfClear = try image { context in
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 20, y: 0, width: 20, height: 40))
        }
        let tint = try XCTUnwrap(AlbumTint.colour(of: halfClear))
        XCTAssertEqual(tint.hue, OKLab(red: 0.1, green: 0.3, blue: 0.9).hue, accuracy: 0.02)
        XCTAssertNil(AlbumTint.colour(of: try image { _ in }), "nothing drawn, no colour")
    }

    // MARK: Mixing

    func testAMixIsPremultiplied() {
        let blackWash = TrackAnnouncementWash(colour: .black, alpha: 0.6)
        let redWash = TrackAnnouncementWash(colour: red, alpha: 0.6)

        let half = TrackAnnouncementWash.mix(blackWash, redWash, progress: 0.5)
        XCTAssertEqual(half.alpha, 0.6, accuracy: 1e-9)
        XCTAssertEqual(half.colour.l, red.l / 2, accuracy: 1e-9, "half way in OKLab")
        XCTAssertEqual(half.colour.hue, red.hue, accuracy: 1e-9)

        XCTAssertEqual(TrackAnnouncementWash.mix(blackWash, redWash, progress: 0), blackWash)
        XCTAssertEqual(TrackAnnouncementWash.mix(blackWash, redWash, progress: 1).colour.l, red.l, accuracy: 1e-9)
    }

    /// Liquid Glass untinted is black at alpha 0: the cover's colour comes in as itself,
    /// growing stronger, never through a grey
    func testAColourComingInFromNothingKeepsItsOwnHue() {
        let none = TrackAnnouncementWash(colour: .black, alpha: 0)
        let redWash = TrackAnnouncementWash(colour: red, alpha: 0.5)

        let quarter = TrackAnnouncementWash.mix(none, redWash, progress: 0.25)
        XCTAssertEqual(quarter.alpha, 0.125, accuracy: 1e-9)
        XCTAssertEqual(quarter.colour.l, red.l, accuracy: 1e-9)
        XCTAssertEqual(quarter.colour.a, red.a, accuracy: 1e-9)
        XCTAssertEqual(quarter.colour.b, red.b, accuracy: 1e-9)

        XCTAssertEqual(TrackAnnouncementWash.mix(none, none, progress: 0.5).alpha, 0)
    }

    // MARK: The glow

    func testWhiteOnATranslucentColourIsMixedAsTheScreenMixesIt() {
        XCTAssertEqual(red.contrastWithWhite(atAlpha: 1), red.contrastWithWhite, accuracy: 1e-9)
        XCTAssertEqual(red.contrastWithWhite(atAlpha: 0), 21, accuracy: 0.01, "nothing over black")
        XCTAssertEqual(white.contrastWithWhite(atAlpha: 0.5), 1.05 / (OKLab.linear(0.5) + 0.05), accuracy: 0.001, "half of white over black is sRGB's 50% grey, not half the light")
        XCTAssertGreaterThan(white.contrastWithWhite(atAlpha: 0.5), 1.05 / (0.5 + 0.05))
    }

    func testTheLightIsTheTintsHueMadeBright() {
        let tint = AlbumTint.legible(OKLab(red: 0.1, green: 0.3, blue: 0.9))
        let light = AlbumTint.light(tint)
        XCTAssertEqual(light.l, AlbumTint.lightLightness, accuracy: 1e-9)
        XCTAssertEqual(light.hue, tint.hue, accuracy: 1e-6)
        XCTAssertGreaterThan(light.chroma, tint.chroma, "a little more colourful than the tint")
        XCTAssertLessThanOrEqual(light.chroma, AlbumTint.lightChroma + 1e-9)
        XCTAssertTrue(light.isInSRGB)
    }

    /// The title starts 12 points past the sleeve: the light there leaves white text at 4.5 : 1
    /// or more over black, whatever the colour, while the light is as strong as that allows
    func testTheGlowKeepsTheTitleReadableAtEveryHue() {
        let atTitle = AlbumTint.Glow.sleeve().strength(beyondEdge: AlbumTint.Glow.titleGap)
        XCTAssertGreaterThan(atTitle, 0.5, "the title sits in the glow, not past it")
        for degrees in stride(from: 0.0, to: 360, by: 10) {
            for chroma in [0.05, 0.1, 0.14] {
                let hue = degrees * .pi / 180
                let light = AlbumTint.light(OKLab(l: 0.45, a: chroma * cos(hue), b: chroma * sin(hue)))
                let context = "hue \(degrees)°, C \(chroma)"
                XCTAssertTrue(light.isInSRGB, context)
                XCTAssertEqual(light.l, AlbumTint.lightLightness, accuracy: 1e-9, context)
                for most: CGFloat in [1, 0.9, 0.75] {
                    let peak = AlbumTint.Glow.peak(for: light, most: most)
                    XCTAssertLessThanOrEqual(peak, most, context)
                    XCTAssertGreaterThan(peak, 0.5, "still a glow: \(context)")
                    XCTAssertGreaterThanOrEqual(light.contrastWithWhite(atAlpha: Double(peak * atTitle)), 4.5 - 1e-6, context)
                    if peak < most {
                        XCTAssertLessThan(light.contrastWithWhite(atAlpha: Double(min(most, peak + 0.01) * atTitle)), 4.5, "no weaker than it need be: \(context)")
                    }
                }
            }
        }
    }

    func testTheGlowFallsAwayFromTheSleevesEdge() {
        let glow = AlbumTint.Glow(centre: CGPoint(x: 68, y: 36), core: 56, reach: 480, halo: 10)
        XCTAssertEqual(glow.strength(beyondEdge: 0), 1)
        XCTAssertEqual(glow.strength(beyondEdge: -20), 1, "behind the sleeve: all of it")
        XCTAssertEqual(glow.strength(beyondEdge: 480 - 56), 0, "gone by the reach")
        var last: CGFloat = 2
        for distance in stride(from: CGFloat(0), through: 424, by: 2) {
            let strength = glow.strength(beyondEdge: distance)
            XCTAssertLessThan(strength, last, "at \(distance)")
            last = strength
        }
        XCTAssertLessThan(glow.strength(beyondEdge: 20), 0.75, "a halo: it drops quickly near the sleeve")
        XCTAssertGreaterThan(glow.strength(beyondEdge: 150), 0.2, "and a spill: some is left a long way out")

        let stops = glow.stops
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.first?.strength, 1)
        XCTAssertEqual(Double(stops[1].location), 56.0 / 480, accuracy: 1e-9, "full strength out to the sleeve's edge")
        XCTAssertEqual(stops[1].strength, 1)
        XCTAssertEqual(stops.last?.location, 1)
        XCTAssertEqual(stops.last?.strength, 0)
        XCTAssertEqual(stops.map { $0.location }, stops.map { $0.location }.sorted(), "in order")
        XCTAssertEqual(Set(stops.map { $0.location }).count, stops.count, "no two stops in one place")
    }

    func testAnOldCheckboxSettingReadsAsTheWholeStripTint() {
        XCTAssertEqual(TrackAnnouncementAlbumTint(storedValue: "1"), .strip)
        XCTAssertEqual(TrackAnnouncementAlbumTint(storedValue: "0"), .off)
        XCTAssertEqual(TrackAnnouncementAlbumTint(storedValue: nil), .off)
        XCTAssertEqual(TrackAnnouncementAlbumTint(storedValue: "glow"), .glow)
        XCTAssertEqual(TrackAnnouncementAlbumTint(storedValue: "sparkles"), .off)
    }

}
