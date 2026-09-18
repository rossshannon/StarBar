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
