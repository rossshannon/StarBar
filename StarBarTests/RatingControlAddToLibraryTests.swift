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

    // Default layout: 16pt glyphs, 4pt spacing. In `.addToLibrary` the note and the plus
    // touch, so they read as one control: 4 | note 16 | plus 16 | 4 || 4 | heart 16.
    // That makes the strip 60pt wide against the stars' 124pt, and the heart starts at 44.
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
        XCTAssertEqual(control.starsImage.size.width, 60)
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
        XCTAssertEqual(control.favoriteMinX, 44)
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
        for positionX in stride(from: CGFloat(0), to: CGFloat(42), by: 1) {
            XCTAssertTrue(control.isAddToLibraryHit(positionX: positionX), "x = \(positionX)")
        }
    }

    func testTheButtonStopsWhereTheHeartBegins() {
        XCTAssertTrue(control.isAddToLibraryHit(positionX: 41.9))
        XCTAssertFalse(control.isAddToLibraryHit(positionX: 42))
        XCTAssertTrue(control.isFavoriteHit(positionX: 42))
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

        for positionX in stride(from: CGFloat(0), to: CGFloat(100), by: 4) {
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

    /// Total alpha between two x positions, in points. Counting pixels is not enough to
    /// show that something is dimmed: a glyph at 35% still has pixels everywhere it had them
    /// before, so only the weight of the ink changes.
    private func inkWeight(in image: NSImage, fromX: CGFloat, toX: CGFloat) -> CGFloat {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              image.size.width > 0 else { return 0 }

        let scale = CGFloat(bitmap.pixelsWide) / image.size.width
        let first = max(0, Int((fromX * scale).rounded()))
        let last = min(bitmap.pixelsWide, Int((toX * scale).rounded()))
        guard first < last else { return 0 }

        var total: CGFloat = 0
        for x in first..<last {
            for y in 0..<bitmap.pixelsHigh {
                total += bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
            }
        }
        return total
    }

    /// A wrong SF Symbol name draws nothing at all rather than failing, which would leave a
    /// blank space in the menu bar. Every slot must have ink in it.
    func testEverySlotIsActuallyDrawn() {
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)
        let image = badge.image

        XCTAssertGreaterThan(ink(in: image, fromX: 4, toX: 20), 0, "the music note")
        XCTAssertGreaterThan(ink(in: image, fromX: 20, toX: 36), 0, "the plus")
        XCTAssertGreaterThan(ink(in: image, fromX: 44, toX: 60), 0, "the heart")

    }

    func testAFavoritedTrackLeavesTheHeartSlotEmpty() {
        // `MenuBarRatingControl` draws the coloured heart over the top, so the outline would
        // show as an edge around it
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4, isFavorited: true)

        XCTAssertEqual(ink(in: badge.image, fromX: 44, toX: 60), 0)
        XCTAssertGreaterThan(ink(in: badge.image, fromX: 4, toX: 20), 0, "the note is still drawn")
    }

    func testTheGapBeforeTheHeartIsEmpty() {
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)

        // The spacing between the plus and the heart, so the two don't run together
        XCTAssertEqual(ink(in: badge.image, fromX: 37, toX: 43), 0)
    }

    // MARK: - While the song is being added

    func testThePlusMakesWayForTheSpinner() {
        // `MenuBarRatingControl` spins a real NSProgressIndicator in that slot, so the plus
        // must not be drawn underneath it
        let pending = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4, isPending: true)

        XCTAssertEqual(ink(in: pending.image, fromX: 21, toX: 35), 0, "the plus slot")
    }

    func testTheNoteStaysWhileTheAddIsInFlight() {
        let solid = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)
        let pending = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4, isPending: true)

        XCTAssertEqual(inkWeight(in: pending.image, fromX: 4, toX: 20),
                       inkWeight(in: solid.image, fromX: 4, toX: 20),
                       accuracy: 0.001,
                       "the note is untouched, only the plus goes")
    }

    func testTheHeartStaysWhileTheAddIsInFlight() {
        // Favouriting works whether or not the song is in the library, so the heart is
        // still live while we wait
        let solid = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)
        let pending = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4, isPending: true)

        XCTAssertEqual(inkWeight(in: pending.image, fromX: 44, toX: 60),
                       inkWeight(in: solid.image, fromX: 44, toX: 60),
                       accuracy: 0.001)
    }

    func testTheStripKeepsItsWidthWhileTheAddIsInFlight() {
        // Losing the plus must not resize the menu bar item mid-press
        let solid = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)
        let pending = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4, isPending: true)

        XCTAssertEqual(pending.image.size.width, solid.image.size.width)
    }

    func testTheNoteAndPlusTouch() {
        // Ross asked for no gap between them, so they read as one control
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)

        XCTAssertEqual(badge.plusMinX, badge.noteMinX + 16, "no spacing between the two glyphs")
    }

    func testTheSpinnerGoesWhereThePlusWas() {
        let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)

        XCTAssertEqual(badge.plusMinX, 20)
        XCTAssertEqual(control.addToLibraryPlusMinX, badge.plusMinX)
        // and it sits between the note and the heart
        XCTAssertLessThan(badge.plusMinX, control.favoriteMinX)
    }

    func testTheControlStartsNotAdding() {
        XCTAssertFalse(control.isAddingToLibrary)
    }

    func testTheControlRemembersThatItIsAdding() {
        control.update(isAddingToLibrary: true)

        XCTAssertTrue(control.isAddingToLibrary)
    }

    func testLeavingTheButtonEndsTheWait() {
        control.update(isAddingToLibrary: true)
        control.update(mode: .rating)

        XCTAssertFalse(control.isAddingToLibrary, "the stars must never come up still waiting")
    }

    func testTheButtonStillWorksWhileWaiting() {
        // A second press is refused further down, in iTunesRadioStation, so the hit test
        // itself stays live
        control.update(isAddingToLibrary: true)

        XCTAssertTrue(control.isAddToLibraryHit(positionX: 12))
    }

    // MARK: - Accessibility

    func testSpokenDescriptionSaysWhenItIsAdding() {
        XCTAssertEqual(
            RatingControl.accessibilityDescription(mode: .addToLibrary, rating: 0, isFavorited: false, isAddingToLibrary: true),
            "Adding to your library"
        )
    }

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
