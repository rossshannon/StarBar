//
//  RatingControlDragTests.swift
//  Song RatingTests
//
//  What the menu bar stars show, and what gets saved, while dragging across them.
//

import XCTest
@testable import Song_Rating

final class RatingControlDragTests: XCTestCase {

    func testStarsFollowTheCursor() {
        var drag = RatingControl.Drag(originalRating: 40)
        XCTAssertEqual(drag.move(to: 60), 60)
        XCTAssertEqual(drag.move(to: 70), 70)
        XCTAssertEqual(drag.move(to: 20), 20)
    }

    func testReleaseSavesTheRatingUnderTheCursor() {
        var drag = RatingControl.Drag(originalRating: 40)
        _ = drag.move(to: 60)
        XCTAssertEqual(drag.releaseRating(at: 70), 70)
    }

    func testReleaseLeftOfTheStarsSavesNoStars() {
        var drag = RatingControl.Drag(originalRating: 40)
        _ = drag.move(to: 30)
        XCTAssertEqual(drag.releaseRating(at: 0), 0)
    }

    /// Dragging past the last star onto the heart keeps the last rating, not the favorite.
    func testOverTheHeartTheStarsKeepTheLastRating() {
        var drag = RatingControl.Drag(originalRating: 40)
        _ = drag.move(to: 100)
        XCTAssertEqual(drag.move(to: nil), 100)
        XCTAssertEqual(drag.releaseRating(at: nil), 100)
    }

    /// A drag that never reaches the stars, such as one that starts right of the heart,
    /// has no rating to save.
    func testDragOnlyOverTheHeartSavesNothing() {
        var drag = RatingControl.Drag(originalRating: 40)
        XCTAssertEqual(drag.move(to: nil), 40)
        XCTAssertNil(drag.releaseRating(at: nil))
    }

    func testOriginalRatingIsKeptForCancel() {
        var drag = RatingControl.Drag(originalRating: 40)
        _ = drag.move(to: 90)
        XCTAssertEqual(drag.originalRating, 40)
    }

}
