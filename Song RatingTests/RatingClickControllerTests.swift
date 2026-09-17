//
//  RatingClickControllerTests.swift
//  Song RatingTests
//
//  Clicks and drags on the menu bar stars, driven by a fake mouse.
//  Positions are x inside the stars image: star i spans 4 + 20i ... 20 + 20i,
//  and the heart spans 108 ... 124.
//

import XCTest
@testable import Song_Rating

final class RatingClickControllerTests: XCTestCase {

    private final class FakePointer: RatingPointer {
        var isLeftButtonHeld = false
        var imagePositionX: CGFloat?
    }

    /// Records the ratings the control asks to save
    private final class SaveRecorder: RatingControlDelegate {
        var savedRatings: [Int] = []

        func ratingControl(_ ratingControl: RatingControl, shouldUpdateRating rating: Int) -> Bool {
            return true
        }

        func ratingControl(_ ratingControl: RatingControl, userDidUpdateRating rating: Int) {
            savedRatings.append(rating)
        }
    }

    private var ratingControl: RatingControl!
    private var pointer: FakePointer!
    private var recorder: SaveRecorder!
    private var controller: RatingClickController!
    private var behavior: RatingControl.Behavior = .full
    private var isStopped = false
    private var favoriteToggles = 0

    override func setUp() {
        super.setUp()
        ratingControl = RatingControl(rating: 40)
        pointer = FakePointer()
        recorder = SaveRecorder()
        ratingControl.delegate = recorder
        behavior = .full
        isStopped = false
        favoriteToggles = 0
        controller = RatingClickController(
            ratingControl: ratingControl,
            pointer: pointer,
            behavior: { [unowned self] in self.behavior },
            isStopped: { [unowned self] in self.isStopped },
            toggleFavorite: { [unowned self] in self.favoriteToggles += 1 }
        )
    }

    override func tearDown() {
        controller = nil
        ratingControl = nil
        pointer = nil
        recorder = nil
        super.tearDown()
    }

    /// Press at `x`; the menu bar's synthesised click arrives while the button is still down.
    private func press(at x: CGFloat) -> Bool {
        pointer.isLeftButtonHeld = true
        pointer.imagePositionX = x
        return controller.click()
    }

    /// A quick click: the button is already up when the click arrives.
    private func click(at x: CGFloat) {
        pointer.isLeftButtonHeld = false
        pointer.imagePositionX = x
        XCTAssertFalse(controller.click())
    }

    private func move(to x: CGFloat?) -> Bool {
        pointer.imagePositionX = x
        return controller.tick()
    }

    private func release(at x: CGFloat?) -> Bool {
        pointer.isLeftButtonHeld = false
        pointer.imagePositionX = x
        return controller.tick()
    }

    // MARK: - Clicks

    func testClickOnStarSavesItsRating() {
        click(at: 52)
        XCTAssertEqual(recorder.savedRatings, [60])
        XCTAssertEqual(ratingControl.rating, 60)
    }

    func testClickInGapBeforeStarGivesHalfStar() {
        behavior = .both
        click(at: 23)
        XCTAssertEqual(recorder.savedRatings, [30])
    }

    func testClickBetweenStarsWithoutHalfStarsGivesWholeStar() {
        click(at: 23)
        XCTAssertEqual(recorder.savedRatings, [40])
    }

    func testClickLeftOfStarsClearsRating() {
        click(at: 2)
        XCTAssertEqual(recorder.savedRatings, [0])
    }

    func testClickOnHeartTogglesFavoriteOnly() {
        click(at: 116)
        XCTAssertEqual(favoriteToggles, 1)
        XCTAssertEqual(recorder.savedRatings, [])
    }

    func testHeldClickOnHeartTogglesFavoriteWithoutDragging() {
        XCTAssertFalse(press(at: 116))
        XCTAssertEqual(favoriteToggles, 1)
        XCTAssertFalse(controller.isDragging)
    }

    func testClickWhileStoppedDoesNothing() {
        isStopped = true
        click(at: 52)
        click(at: 116)
        XCTAssertEqual(recorder.savedRatings, [])
        XCTAssertEqual(favoriteToggles, 0)
    }

    func testClickWithUnknownCursorPositionDoesNothing() {
        click(at: 52)
        recorder.savedRatings = []
        pointer.imagePositionX = nil
        XCTAssertFalse(controller.click())
        XCTAssertEqual(recorder.savedRatings, [])
    }

    // MARK: - Drags

    func testDragPreviewsStarsWithoutSaving() {
        XCTAssertTrue(press(at: 12))
        XCTAssertEqual(ratingControl.rating, 20)
        XCTAssertTrue(move(to: 52))
        XCTAssertEqual(ratingControl.rating, 60)
        XCTAssertTrue(move(to: 97))
        XCTAssertEqual(ratingControl.rating, 100)
        XCTAssertEqual(recorder.savedRatings, [])
    }

    func testReleaseSavesOnceAtReleasePosition() {
        XCTAssertTrue(press(at: 12))
        XCTAssertTrue(move(to: 97))
        XCTAssertFalse(release(at: 97))
        XCTAssertEqual(recorder.savedRatings, [100])

        XCTAssertFalse(controller.tick())
        XCTAssertEqual(recorder.savedRatings, [100])
    }

    /// Today's bug: the rating must come from where the mouse is released, not where it was pressed.
    func testReleaseRatingComesFromReleaseNotPress() {
        XCTAssertTrue(press(at: 97))
        XCTAssertTrue(move(to: 30))
        XCTAssertFalse(release(at: 32))
        XCTAssertEqual(recorder.savedRatings, [40])
    }

    func testDragShowsHalfStarsWhenTheyAreOn() {
        behavior = .both
        XCTAssertTrue(press(at: 97))
        XCTAssertTrue(move(to: 43))
        XCTAssertEqual(ratingControl.rating, 50)
        XCTAssertFalse(release(at: 43))
        XCTAssertEqual(recorder.savedRatings, [50])
    }

    func testReleaseOverHeartKeepsLastStarRating() {
        XCTAssertTrue(press(at: 52))
        XCTAssertTrue(move(to: 97))
        XCTAssertTrue(move(to: 116))
        XCTAssertEqual(ratingControl.rating, 100)
        XCTAssertFalse(release(at: 116))
        XCTAssertEqual(recorder.savedRatings, [100])
        XCTAssertEqual(favoriteToggles, 0)
    }

    func testDragLeftOfStarsSavesNoStars() {
        XCTAssertTrue(press(at: 52))
        XCTAssertTrue(move(to: 0))
        XCTAssertEqual(ratingControl.rating, 0)
        XCTAssertFalse(release(at: 0))
        XCTAssertEqual(recorder.savedRatings, [0])
    }

    func testMusicStoppingEndsDragWithoutSaving() {
        XCTAssertTrue(press(at: 12))
        XCTAssertTrue(move(to: 97))
        isStopped = true
        XCTAssertFalse(move(to: 97))
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(recorder.savedRatings, [])
    }

    func testLostCursorPositionKeepsLastRating() {
        XCTAssertTrue(press(at: 12))
        XCTAssertTrue(move(to: 72))
        XCTAssertTrue(move(to: nil))
        XCTAssertEqual(ratingControl.rating, 80)
        XCTAssertFalse(release(at: nil))
        XCTAssertEqual(recorder.savedRatings, [80])
    }

    func testNewClickStartsFreshDrag() {
        XCTAssertTrue(press(at: 97))
        click(at: 52)
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(recorder.savedRatings, [60])
    }

    // MARK: - Accessibility

    func testAccessibilityDescriptions() {
        let cases: [(Int, Bool, String)] = [
            (0, false, "No rating"),
            (10, false, "½ star"),
            (20, false, "1 star"),
            (30, false, "1½ stars"),
            (70, false, "3½ stars"),
            (100, true, "5 stars, favourite"),
        ]
        for (rating, isFavorited, expected) in cases {
            XCTAssertEqual(RatingControl.accessibilityDescription(rating: rating, isFavorited: isFavorited), expected)
        }
    }

}
