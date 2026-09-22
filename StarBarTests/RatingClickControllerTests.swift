//
//  RatingClickControllerTests.swift
//  StarBarTests
//
//  Clicks and drags on the menu bar stars, driven by a fake mouse.
//  Positions are x inside the stars image: star i spans 4 + 20i ... 20 + 20i,
//  and the heart spans 108 ... 124.
//

import XCTest
@testable import StarBar

final class RatingClickControllerTests: XCTestCase {

    private final class FakePointer: RatingPointer {
        var isLeftButtonHeld = false
        var imagePositionX: CGFloat?
    }

    /// Records the ratings the control asks to save
    private final class SaveRecorder: RatingControlDelegate {
        var savedRatings: [Int] = []
        var shouldSave: (RatingControl) -> Bool = { _ in true }

        func ratingControl(_ ratingControl: RatingControl, shouldUpdateRating rating: Int) -> Bool {
            return shouldSave(ratingControl)
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
    private var dragEnds: [Bool] = []

    override func setUp() {
        super.setUp()
        ratingControl = RatingControl(rating: 40)
        pointer = FakePointer()
        recorder = SaveRecorder()
        ratingControl.delegate = recorder
        behavior = .full
        isStopped = false
        favoriteToggles = 0
        dragEnds = []
        controller = RatingClickController(
            ratingControl: ratingControl,
            pointer: pointer,
            behavior: { [unowned self] in self.behavior },
            isStopped: { [unowned self] in self.isStopped },
            toggleFavorite: { [unowned self] in self.favoriteToggles += 1 }
        )
        controller.didEndDrag = { [unowned self] saved in self.dragEnds.append(saved) }
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
        XCTAssertEqual(dragEnds, [], "a plain click is not a drag")
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
        pointer.imagePositionX = nil
        XCTAssertFalse(controller.click())
        pointer.isLeftButtonHeld = true
        XCTAssertFalse(controller.click())
        XCTAssertEqual(recorder.savedRatings, [])
        XCTAssertEqual(favoriteToggles, 0)
        XCTAssertEqual(ratingControl.rating, 40)
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
        XCTAssertEqual(dragEnds, [true])

        XCTAssertFalse(controller.tick())
        XCTAssertEqual(recorder.savedRatings, [100])
        XCTAssertEqual(dragEnds, [true])
    }

    /// On macOS 27 the click arrives when the mouse goes down. The saved rating must come from
    /// where the mouse is released: not the press position (100) or the last tick (40).
    func testReleaseRatingComesFromReleasePosition() {
        XCTAssertTrue(press(at: 97))
        XCTAssertTrue(move(to: 30))
        XCTAssertEqual(ratingControl.rating, 40)
        XCTAssertFalse(release(at: 52))
        XCTAssertEqual(recorder.savedRatings, [60])
    }

    func testRejectedDragRestoresOriginalRatingWhenRefreshHasNoTrack() {
        XCTAssertTrue(press(at: 97))
        recorder.shouldSave = { control in
            XCTAssertEqual(control.rating, 40, "a missing-track refresh must retain the original stars")
            return false
        }

        XCTAssertFalse(release(at: 97))

        XCTAssertEqual(ratingControl.rating, 40)
        XCTAssertTrue(recorder.savedRatings.isEmpty)
        XCTAssertEqual(dragEnds, [false])
    }

    func testRejectedDragPreservesRatingReturnedBySynchronousRefresh() {
        XCTAssertTrue(press(at: 97))
        recorder.shouldSave = { control in
            control.update(rating: 60)
            return false
        }

        XCTAssertFalse(release(at: 97))

        XCTAssertEqual(ratingControl.rating, 60, "do not overwrite a fresh track with the old rating")
        XCTAssertTrue(recorder.savedRatings.isEmpty)
        XCTAssertEqual(dragEnds, [false])
    }

    func testRejectedDragPreservesCatalogModeReturnedBySynchronousRefresh() {
        XCTAssertTrue(press(at: 97))
        recorder.shouldSave = { control in
            control.update(mode: .addToLibrary)
            control.update(rating: 0)
            return false
        }

        XCTAssertFalse(release(at: 97))

        XCTAssertEqual(ratingControl.mode, .addToLibrary)
        XCTAssertEqual(ratingControl.rating, 0)
        XCTAssertTrue(recorder.savedRatings.isEmpty)
        XCTAssertEqual(dragEnds, [false])
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

    func testReleasePastHeartKeepsLastStarRating() {
        XCTAssertTrue(press(at: 12))
        XCTAssertTrue(move(to: 72))
        XCTAssertTrue(move(to: 200))
        XCTAssertEqual(ratingControl.rating, 80)
        XCTAssertFalse(release(at: 200))
        XCTAssertEqual(recorder.savedRatings, [80])
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
        XCTAssertEqual(ratingControl.rating, 40, "the unsaved preview is replaced by the original rating")
        XCTAssertEqual(dragEnds, [false], "the owner is told nothing was saved, so it can refresh from Music")
    }

    /// A press just right of the heart's hit area (x > 128) starts a drag with no rating.
    /// Released there, nothing is saved and the rating is unchanged.
    func testDragThatNeverReachesStarsSavesNothing() {
        XCTAssertTrue(press(at: 130))
        XCTAssertEqual(ratingControl.rating, 40)
        XCTAssertFalse(release(at: 130))
        XCTAssertEqual(recorder.savedRatings, [])
        XCTAssertEqual(dragEnds, [false])
        XCTAssertEqual(ratingControl.rating, 40)
        XCTAssertEqual(favoriteToggles, 0)
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
