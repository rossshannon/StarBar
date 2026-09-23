//
//  RatingControlGeometryTests.swift
//  StarBarTests
//
//  Hit-testing for clicks on the menu bar stars and favorite heart.
//  Needs no Music app, so these run on any Mac.
//

import XCTest
@testable import StarBar

final class RatingControlGeometryTests: XCTestCase {

    // Default layout: 16pt stars, 4pt spacing, so a 20pt slot per star.
    // Star i spans x = 4 + 20i ... 20 + 20i; the heart spans x = 108 ... 124.
    private var control: RatingControl!

    override func setUp() {
        super.setUp()
        control = RatingControl(rating: 0)
    }

    override func tearDown() {
        control = nil
        super.tearDown()
    }

    // MARK: - Layout

    func testMenuBarStartsWithTheStoppedDotBeforeAnyPlayerOrWindowNotification() {
        let menuBar = MenuBarRatingControl()
        defer { NSStatusBar.system.removeStatusItem(menuBar.statusItem) }

        XCTAssertTrue(menuBar.isStop)
        XCTAssertEqual(menuBar.statusItem.length, 32)
        XCTAssertTrue(menuBar.statusItem.button?.image === menuBar.menuBarIcon.image)
        XCTAssertEqual(menuBar.statusItem.button?.accessibilityValue() as? String, "Not playing")
    }

    func testImageWidthMatchesDrawnStars() {
        XCTAssertEqual(control.starsImage.size.width, 124)
        for rating in stride(from: 0, through: 100, by: 10) {
            control.update(rating: rating)
            XCTAssertEqual(control.stars.image.size.width, control.starsImage.size.width, "rating \(rating)")
        }
    }

    func testHeartIsTheLastSlot() {
        XCTAssertEqual(control.favoriteMinX, 108)
        XCTAssertEqual(control.favoriteMinX + control.starSize.width, control.starsImage.size.width)
    }

    func testStarStylesForHalfStarRating() {
        control.update(rating: 70)
        XCTAssertEqual(control.stars.stars.map { $0.style }, [.full, .full, .full, .half, .dot])
    }

    func testFavoriteHeartStaysAtTheRightWhenTheImageShrinksBeforeTheButton() {
        let bounds = NSRect(x: 0, y: 0, width: 132, height: 24)
        let frame = MenuBarRatingControl.favoriteHeartFrame(in: bounds, size: NSSize(width: 16, height: 16))
        XCTAssertEqual(bounds.maxX - frame.maxX, 4)
    }

    func testFavoriteHeartStaysAtTheRightWhenAppKitResizesItsParentLater() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 132, height: 24))
        let heart = NSImageView(frame: NSRect(x: 112, y: 4, width: 16, height: 16))
        heart.autoresizingMask = MenuBarRatingControl.favoriteHeartAutoresizingMask
        parent.addSubview(heart)
        for image in [Stars.outlinedFavoriteHeartImage(size: heart.frame.size),
                      Stars.filledFavoriteHeartImage(size: heart.frame.size)] {
            heart.image = image
            for width: CGFloat in [120, 100, 80, 68, 132] {
                parent.setFrameSize(NSSize(width: width, height: 24))
                XCTAssertEqual(parent.bounds.maxX - heart.frame.maxX, 4, accuracy: 0.001)
            }
        }
    }

    func testMenuBarCanReserveAnEmptyHeartSlotForBothModesAndFavoriteStates() throws {
        let separateHeart = RatingControl(rating: 70, drawsFavorite: false)
        for mode: RatingControl.Mode in [.rating, .addToLibrary] {
            separateHeart.update(mode: mode)
            for favorite in [false, true] {
                separateHeart.updateFavorited(favorite)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(separateHeart.starsImage.tiffRepresentation)))
                let slotWidth = Int(CGFloat(bitmap.pixelsWide) * 16 / separateHeart.starsImage.size.width)
                for x in (bitmap.pixelsWide - slotWidth)..<bitmap.pixelsWide {
                    for y in 0..<bitmap.pixelsHigh {
                        XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent, 0,
                                       "The outline must not remain in the centred strip: \(mode), favourite \(favorite)")
                    }
                }
                XCTAssertEqual(separateHeart.isFavorited, favorite)
                XCTAssertEqual(separateHeart.favoriteMinX + 16, separateHeart.starsImage.size.width)
            }
        }
    }

    func testRightAlignedCompactControlsLeaveUnusedSpaceInactive() {
        let bounds = NSRect(x: 0, y: 0, width: 132, height: 22)
        control.update(mode: .addToLibrary)
        let origin = MenuBarStripLayout.contentOriginX(in: bounds, contentWidth: control.starsImage.size.width)
        XCTAssertEqual(origin, 68)
        for x in stride(from: CGFloat(0), to: 68, by: 0.5) {
            XCTAssertFalse(control.isAddToLibraryHit(positionX: x - origin))
            XCTAssertFalse(control.isFavoriteHit(positionX: x - origin))
        }
        XCTAssertTrue(control.isAddToLibraryHit(positionX: 80 - origin))
        XCTAssertTrue(control.isAddToLibraryHit(positionX: 100 - origin))
        XCTAssertTrue(control.isFavoriteHit(positionX: 120 - origin))

        control.update(mode: .rating)
        let ratingOrigin = MenuBarStripLayout.contentOriginX(in: bounds, contentWidth: control.starsImage.size.width)
        XCTAssertEqual(ratingOrigin, 4)
        XCTAssertEqual(control.rating(atPositionX: 16 - ratingOrigin, behavior: .full), 20)
        XCTAssertTrue(control.isFavoriteHit(positionX: 120 - ratingOrigin))
    }

    func testAddButtonFillsItsOwnNarrowItem() {
        // The settled add-button state: the item is only as wide as the badge and heart
        let bounds = NSRect(x: 0, y: 0, width: 68, height: 22)
        control.update(mode: .addToLibrary)
        XCTAssertEqual(control.starsImage.size.width + 8, 68)
        let origin = MenuBarStripLayout.contentOriginX(in: bounds, contentWidth: control.starsImage.size.width)
        XCTAssertEqual(origin, 4)
        XCTAssertTrue(control.isAddToLibraryHit(positionX: 16 - origin))
        XCTAssertTrue(control.isAddToLibraryHit(positionX: 36 - origin))
        XCTAssertTrue(control.isFavoriteHit(positionX: 56 - origin))
        let layout = MenuBarStripLayout(starSize: control.starSize, spacing: control.spacing)
        XCTAssertTrue(layout.image(containing: control.starsImage, allocation: 68) === control.starsImage,
                      "no padding when the item fits the content")
    }

    func testCompactImageIsRightAlignedAndRedrawsPendingChanges() throws {
        let compact = RatingControl(rating: 70, drawsFavorite: false)
        compact.update(mode: .addToLibrary)
        let layout = MenuBarStripLayout(starSize: compact.starSize, spacing: compact.spacing)
        let image = layout.image(containing: compact.starsImage)
        XCTAssertEqual(layout.statusItemWidth, 132)
        XCTAssertEqual(image.size.width, 124)
        let before = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: before))
        let blankWidth = Int(CGFloat(bitmap.pixelsWide) * 64 / 124)
        for x in 0..<blankWidth {
            for y in 0..<bitmap.pixelsHigh {
                XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent, 0)
            }
        }
        compact.update(isAddingToLibrary: true)
        let pendingImage = layout.image(containing: compact.starsImage)
        XCTAssertNotEqual(try XCTUnwrap(pendingImage.tiffRepresentation), before,
                          "Refreshing the canvas must show the pending state without the plus")
    }

    // MARK: - Favorite heart

    func testFavoriteHitEdges() {
        XCTAssertFalse(control.isFavoriteHit(positionX: 105.9))
        XCTAssertTrue(control.isFavoriteHit(positionX: 106))
        XCTAssertTrue(control.isFavoriteHit(positionX: 116))
        XCTAssertTrue(control.isFavoriteHit(positionX: 128))
        XCTAssertFalse(control.isFavoriteHit(positionX: 128.1))
    }

    // MARK: - Star rating

    func testLeftOfFirstStarClearsRating() {
        for x: CGFloat in [-10, 0, 3.9] {
            for behavior: RatingControl.Behavior in [.full, .both] {
                XCTAssertEqual(control.starRating(atPositionX: x, behavior: behavior), 0, "x \(x), \(behavior)")
            }
        }
    }

    func testEachStarCentreGivesItsOwnRating() {
        for i in 0..<5 {
            let centreX = CGFloat(12 + 20 * i)
            XCTAssertEqual(control.starRating(atPositionX: centreX, behavior: .full), 2 * (i + 1))
            XCTAssertEqual(control.starRating(atPositionX: centreX + 0.5, behavior: .both), 2 * (i + 1))
            XCTAssertEqual(control.starRating(atPositionX: centreX, behavior: .both), 2 * (i + 1) - 1)
        }
    }

    /// The original bug: every click landed between stars 3 and 4 and gave 3 stars.
    func testClicksBetweenStarsThreeAndFourSplitTheGap() {
        XCTAssertEqual(control.starRating(atPositionX: 61.9, behavior: .full), 6)
        XCTAssertEqual(control.starRating(atPositionX: 62, behavior: .full), 8)
    }

    func testBothBehaviorSplitsEachStarAtItsCentre() {
        XCTAssertEqual(control.starRating(atPositionX: 12, behavior: .both), 1)
        XCTAssertEqual(control.starRating(atPositionX: 12.5, behavior: .both), 2)
        XCTAssertEqual(control.starRating(atPositionX: 97, behavior: .both), 10)
    }

    /// The gap before a star belongs to that star's left half.
    func testGapBeforeStarGivesHalfStarWithBothBehavior() {
        XCTAssertEqual(control.starRating(atPositionX: 21, behavior: .both), 2)
        XCTAssertEqual(control.starRating(atPositionX: 23, behavior: .both), 3)
    }

    /// The heart and everything to its right give no rating; just left of the heart is 5 stars.
    func testRatingIsNilFromHeartRightwards() {
        XCTAssertEqual(control.rating(atPositionX: 105.9, behavior: .full), 100)
        XCTAssertNil(control.rating(atPositionX: 106, behavior: .full))
        XCTAssertNil(control.rating(atPositionX: 116, behavior: .full))
        XCTAssertNil(control.rating(atPositionX: 128.5, behavior: .full))
        XCTAssertNil(control.rating(atPositionX: 400, behavior: .both))
    }

    func testPositionsPastLastStarClampToFiveStars() {
        XCTAssertEqual(control.starRating(atPositionX: 100, behavior: .full), 10)
        XCTAssertEqual(control.starRating(atPositionX: 105, behavior: .full), 10)
        XCTAssertEqual(control.starRating(atPositionX: 200, behavior: .full), 10)
    }

    /// Sweep the whole image: every position is either the heart or a rating,
    /// and ratings never go down as the cursor moves right.
    func testEveryPositionIsHeartOrNonDecreasingRating() {
        for behavior: RatingControl.Behavior in [.full, .both] {
            var previous = 0
            for x in stride(from: CGFloat(0), through: control.starsImage.size.width, by: 0.5) where !control.isFavoriteHit(positionX: x) {
                let rating = control.starRating(atPositionX: x, behavior: behavior)
                XCTAssertTrue((0...10).contains(rating), "x \(x), \(behavior)")
                XCTAssertGreaterThanOrEqual(rating, previous, "x \(x), \(behavior)")
                previous = rating
            }
            XCTAssertEqual(previous, 10, "\(behavior)")
        }
    }

    // MARK: - Half-star round trips

    /// Every rating Music can store (0 to 100 in steps of 10) draws as stars that add back
    /// up to that rating: 20 per full star, 10 per half star.
    func testStarStylesAddBackUpToTheRating() {
        for rating in stride(from: 0, through: 100, by: 10) {
            let styles = Stars.styles(forRating: rating)
            XCTAssertEqual(styles.count, 5, "rating \(rating)")
            let drawn = styles.reduce(0) { total, style in
                switch style {
                case .full: return total + 20
                case .half: return total + 10
                case .dot, .outline: return total
                }
            }
            XCTAssertEqual(drawn, rating, "rating \(rating)")
            XCTAssertLessThanOrEqual(styles.filter { $0 == .half }.count, 1, "rating \(rating)")
        }
    }

    /// Clicking where the stars for a rating are drawn gives that rating back: the drawn
    /// image and the hit-test agree for every whole and half star.
    func testClickingTheDrawnStarsGivesTheSameRatingBack() {
        for rating in stride(from: 10, through: 100, by: 10) {
            control.update(rating: rating)
            let halfStars = rating / 10
            let lastStar = (halfStars - 1) / 2
            let slot = control.starSize.width + control.spacing
            let starMinX = control.spacing + CGFloat(lastStar) * slot
            // Left half of the last drawn star for a half star, right half for a full one
            let x = halfStars % 2 == 1 ? starMinX + 4 : starMinX + control.starSize.width - 4
            XCTAssertEqual(control.rating(atPositionX: x, behavior: .both), rating, "rating \(rating) at x \(x)")
            // Without half stars, the same click rounds up to the whole star
            XCTAssertEqual(control.rating(atPositionX: x, behavior: .full), 20 * (lastStar + 1), "rating \(rating) at x \(x)")
        }
    }

    /// What VoiceOver says for every storable rating, with and without the heart
    func testAccessibilityDescriptionCoversEveryRating() {
        let expected = ["No rating", "½ star", "1 star", "1½ stars", "2 stars", "2½ stars",
                        "3 stars", "3½ stars", "4 stars", "4½ stars", "5 stars"]
        for (halfStars, text) in expected.enumerated() {
            XCTAssertEqual(RatingControl.accessibilityDescription(rating: 10 * halfStars, isFavorited: false), text)
            XCTAssertEqual(RatingControl.accessibilityDescription(rating: 10 * halfStars, isFavorited: true), text + ", favourite")
        }
        // Out-of-range values clamp rather than crash
        XCTAssertEqual(RatingControl.accessibilityDescription(rating: -30, isFavorited: false), "No rating")
        XCTAssertEqual(RatingControl.accessibilityDescription(rating: 250, isFavorited: false), "5 stars")
    }

    /// `update(rating:)` clamps to Music's range, so a shortcut can't push past 5 stars or below 0
    func testUpdateClampsToMusicsRange() {
        control.update(rating: 130)
        XCTAssertEqual(control.rating, 100)
        control.update(rating: -20)
        XCTAssertEqual(control.rating, 0)
    }

}
