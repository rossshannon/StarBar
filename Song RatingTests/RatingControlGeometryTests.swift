//
//  RatingControlGeometryTests.swift
//  Song RatingTests
//
//  Hit-testing for clicks on the menu bar stars and favorite heart.
//  Needs no Music app, so these run on any Mac.
//

import XCTest
@testable import Song_Rating

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

}
