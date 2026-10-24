//
//  RatingControlSpotifyTests.swift
//  StarBarTests
//
//  The strip the menu bar shows while a song plays in Spotify: Spotify's icon, its clear
//  space, then the green heart. Needs neither Music nor Spotify.
//

import XCTest
@testable import StarBar

final class RatingControlSpotifyTests: XCTestCase {

    // Default layout: 16pt glyphs, 4pt spacing. 4 | icon 16 | clear space 8 || heart 16:
    // the icon runs from 4 to 20, the heart from 28, and the strip is 44pt wide.
    private var control: RatingControl!

    override func setUp() {
        super.setUp()
        control = RatingControl(rating: 0)
        control.update(mode: .spotify)
    }

    override func tearDown() {
        control = nil
        super.tearDown()
    }

    // MARK: - Layout

    func testTheHeartFollowsTheIconAndItsClearSpace() {
        XCTAssertEqual(RatingControl.spotifyIconClearSpace(starSize: control.starSize), 8,
                       "Spotify asks for half the icon's height around it")
        XCTAssertEqual(control.favoriteMinX, control.spacing + control.starSize.width + 8)
        XCTAssertEqual(control.favoriteMinX + control.starSize.width, control.starsImage.size.width)
        XCTAssertEqual(control.starsImage.size.width, 44)
    }

    func testTheStripMatchesTheWidthTheModeReserves() {
        let strip = RatingControl.spotifyStrip(starSize: control.starSize, spacing: control.spacing)
        XCTAssertEqual(strip.size.width, control.starsImage.size.width)
        XCTAssertTrue(strip.isTemplate, "the menu bar must colour the icon, since it is neither black nor white")
    }

    func testTheStripIsNarrowerThanTheAppleMusicButtonAndTheStars() {
        let spotify = RatingControl.imageWidth(mode: .spotify, starSize: control.starSize, spacing: control.spacing)
        XCTAssertLessThan(spotify, RatingControl.imageWidth(mode: .addToLibrary, starSize: control.starSize, spacing: control.spacing))
        XCTAssertLessThan(spotify, RatingControl.imageWidth(mode: .rating, starSize: control.starSize, spacing: control.spacing))
    }

    // MARK: - Clicks

    func testEverythingLeftOfTheHeartOpensSpotify() {
        for x: CGFloat in [-2, 0, 4, 12, 20, 24, 25.9] {
            XCTAssertTrue(control.isSpotifyIconHit(positionX: x), "x = \(x)")
        }
    }

    func testTheHeartIsNotTheIcon() {
        for x: CGFloat in [26, 28, 36, 44, 48] {
            XCTAssertFalse(control.isSpotifyIconHit(positionX: x), "x = \(x)")
        }
        XCTAssertTrue(control.isFavoriteHit(positionX: 36))
    }

    func testEveryPositionBelongsToTheIconOrTheHeart() {
        // The icon's area stops where the heart's starts, with no dead gap between them
        let boundary = control.favoriteMinX - 0.5 * control.spacing
        XCTAssertTrue(control.isSpotifyIconHit(positionX: boundary - 0.01))
        XCTAssertFalse(control.isSpotifyIconHit(positionX: boundary))
        XCTAssertTrue(control.isFavoriteHit(positionX: boundary))
    }

    func testTheIconIsOnlyInSpotifyMode() {
        control.update(mode: .rating)
        XCTAssertFalse(control.isSpotifyIconHit(positionX: 10))
        control.update(mode: .addToLibrary)
        XCTAssertFalse(control.isSpotifyIconHit(positionX: 10))
    }

    func testNoStarRatingComesFromSpotifyMode() {
        XCTAssertNil(control.rating(atPositionX: 10, behavior: .full))
    }

    // MARK: - The icon

    func testTheIconParsesWhole() {
        // The circle and three waves: a parse that stopped early would draw a plain disc
        let path = SpotifyGlyph.outline
        var moves = 0
        for index in 0..<path.elementCount where path.element(at: index) == .moveTo {
            moves += 1
        }
        XCTAssertEqual(moves, 4)
        XCTAssertEqual(path.bounds.minX, 0, accuracy: 0.01)
        XCTAssertEqual(path.bounds.minY, 0, accuracy: 0.01)
        XCTAssertEqual(path.bounds.width, 24, accuracy: 0.01)
        XCTAssertEqual(path.bounds.height, 24, accuracy: 0.01)
    }

    func testTheWavesAreCutOutOfTheCircle() throws {
        // Draw it at 24 x 24 and look at a point on the middle wave and one beside it
        let size = 48
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill()
        SpotifyGlyph().draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        func alpha(svgX: CGFloat, svgY: CGFloat) -> CGFloat {
            // Bitmap rows run from the top, as SVG's y does
            return bitmap.colorAt(x: Int(svgX * 2), y: Int(svgY * 2))?.alphaComponent ?? -1
        }
        XCTAssertGreaterThan(alpha(svgX: 12, svgY: 2), 0.9, "inside the circle, above the waves")
        XCTAssertLessThan(alpha(svgX: 12, svgY: 11.6), 0.1, "on the middle wave, which must be a hole")
        XCTAssertGreaterThan(alpha(svgX: 12, svgY: 9.6), 0.9, "between the top and middle waves")
        XCTAssertLessThan(alpha(svgX: 0.3, svgY: 0.3), 0.1, "outside the circle")
    }

}
