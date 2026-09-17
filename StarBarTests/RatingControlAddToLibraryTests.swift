//
//  RatingControlAddToLibraryTests.swift
//  StarBarTests
//
//  The narrower strip the menu bar shows for an Apple Music track that isn't in the library:
//  the Apple Music button and the heart, with no stars. Needs no Music app.
//

import XCTest
@testable import StarBar

final class RatingControlAddToLibraryTests: XCTestCase {

    // Default layout: 16pt glyphs, 4pt spacing. In `.addToLibrary` there are two glyphs
    // before the heart instead of five, so the strip is 64pt wide rather than 124pt:
    // 4 | note 16 | 4 | plus 16 | 4 || 4 | heart 16. The heart starts at x = 48.
    private var control: RatingControl!

    override func setUp() {
        super.setUp()
        control = RatingControl(rating: 0)
        control.update(mode: .addToLibrary)
    }

    override func tearDown() {
        control = nil
        super.tearDown()
    }

    // MARK: - Layout

    func testStripIsNarrowerThanTheStars() {
        XCTAssertEqual(control.starsImage.size.width, 64)
        XCTAssertLessThan(
            RatingControl.imageWidth(mode: .addToLibrary, starSize: control.starSize, spacing: control.spacing),
            RatingControl.imageWidth(mode: .rating, starSize: control.starSize, spacing: control.spacing)
        )
    }

    func testImageWidthMatchesTheDrawnBadge() {
        let badge = AddToLibraryBadge(glyphSize: control.starSize, spacing: control.spacing)
        XCTAssertEqual(badge.image.size.width, control.starsImage.size.width)
    }

    func testHeartIsStillTheLastSlot() {
        XCTAssertEqual(control.favoriteMinX, 48)
        XCTAssertEqual(control.favoriteMinX + control.starSize.width, control.starsImage.size.width)
    }

    func testSwitchingBackToRatingRestoresTheFullWidth() {
        control.update(mode: .rating)

        XCTAssertEqual(control.starsImage.size.width, 124)
        XCTAssertEqual(control.favoriteMinX, 108)
    }

    func testUpdatingToTheSameModeKeepsTheSameImage() {
        let image = control.starsImage
        control.update(mode: .addToLibrary)

        XCTAssertTrue(control.starsImage === image)
    }

    // MARK: - The button is one button

    func testEverythingLeftOfTheHeartAddsToTheLibrary() {
        // Both glyphs and the gap between them, with no dead space anywhere
        for positionX in stride(from: CGFloat(0), to: CGFloat(46), by: 1) {
            XCTAssertTrue(control.isAddToLibraryHit(positionX: positionX), "x = \(positionX)")
        }
    }

    func testTheButtonStopsWhereTheHeartBegins() {
        XCTAssertTrue(control.isAddToLibraryHit(positionX: 45.9))
        XCTAssertFalse(control.isAddToLibraryHit(positionX: 46))
        XCTAssertTrue(control.isFavoriteHit(positionX: 46))
    }

    func testEveryPositionBelongsToExactlyOneControl() {
        for tenths in 0...700 {
            let positionX = CGFloat(tenths) / 10
            let isAdd = control.isAddToLibraryHit(positionX: positionX)
            let isHeart = control.isFavoriteHit(positionX: positionX)
            XCTAssertFalse(isAdd && isHeart, "x = \(positionX) hits both")
        }
    }

    func testAPositionLeftOfTheStripIsNotTheButton() {
        XCTAssertFalse(control.isAddToLibraryHit(positionX: -1))
    }

    // MARK: - No rating in this mode

    func testNoPositionGivesARating() {
        for tenths in 0...700 {
            let positionX = CGFloat(tenths) / 10
            XCTAssertNil(control.rating(atPositionX: positionX, behavior: .full), "x = \(positionX)")
            XCTAssertNil(control.rating(atPositionX: positionX, behavior: .both), "x = \(positionX)")
        }
    }

    func testRatingComesBackAfterSwitchingToRating() {
        control.update(mode: .rating)

        XCTAssertEqual(control.rating(atPositionX: 20, behavior: .full), 20)
    }

    func testTheStarsAreNotTheAddButton() {
        control.update(mode: .rating)

        for positionX in stride(from: CGFloat(0), to: CGFloat(104), by: 4) {
            XCTAssertFalse(control.isAddToLibraryHit(positionX: positionX), "x = \(positionX)")
        }
    }

    // MARK: - What actually gets drawn

    /// Non-transparent pixels between two x positions of the drawn strip, given in points.
    ///
    /// The bitmap is not the same size as the image: on a retina Mac `tiffRepresentation`
    /// comes back at 2 pixels per point, so the range has to be scaled or it lands on the
    /// wrong glyph entirely.
    private func ink(in image: NSImage, fromX: CGFloat, toX: CGFloat) -> Int {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              image.size.width > 0 else { return 0 }

        let scale = CGFloat(bitmap.pixelsWide) / image.size.width
        let first = max(0, Int((fromX * scale).rounded()))
        let last = min(bitmap.pixelsWide, Int((toX * scale).rounded()))
        guard first < last else { return 0 }

        var count = 0
        for x in first..<last {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                count += 1
            }
        }
        return count
    }

    /// A wrong SF Symbol name draws nothing at all rather than failing, which would leave a
    /// blank space in the menu bar. Every slot must have ink in it.
    func testEverySlotIsActuallyDrawn() {
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)
        let image = badge.image

        XCTAssertGreaterThan(ink(in: image, fromX: 4, toX: 20), 0, "the music note")
        XCTAssertGreaterThan(ink(in: image, fromX: 24, toX: 40), 0, "the plus")
        XCTAssertGreaterThan(ink(in: image, fromX: 48, toX: 64), 0, "the heart")

    }

    func testAFavoritedTrackLeavesTheHeartSlotEmpty() {
        // `MenuBarRatingControl` draws the coloured heart over the top, so the outline would
        // show as an edge around it
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4, isFavorited: true)

        XCTAssertEqual(ink(in: badge.image, fromX: 48, toX: 64), 0)
        XCTAssertGreaterThan(ink(in: badge.image, fromX: 4, toX: 20), 0, "the note is still drawn")
    }

    func testTheGapBeforeTheHeartIsEmpty() {
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)

        // The spacing between the plus and the heart, so the two don't run together
        XCTAssertEqual(ink(in: badge.image, fromX: 41, toX: 47), 0)
    }

    // MARK: - Accessibility

    func testSpokenDescriptionSaysWhyThereAreNoStars() {
        XCTAssertEqual(
            RatingControl.accessibilityDescription(mode: .addToLibrary, rating: 0, isFavorited: false),
            "Not in your library, add to rate"
        )
    }

    func testSpokenDescriptionStillMentionsTheFavourite() {
        XCTAssertEqual(
            RatingControl.accessibilityDescription(mode: .addToLibrary, rating: 0, isFavorited: true),
            "Not in your library, add to rate, favourite"
        )
    }

    func testSpokenDescriptionIsUnchangedForRatableTracks() {
        XCTAssertEqual(
            RatingControl.accessibilityDescription(mode: .rating, rating: 70, isFavorited: true),
            RatingControl.accessibilityDescription(rating: 70, isFavorited: true)
        )
    }

}
