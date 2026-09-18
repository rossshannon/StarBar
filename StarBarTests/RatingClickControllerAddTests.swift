//
//  RatingClickControllerAddTests.swift
//  StarBarTests
//
//  Clicking the Apple Music button that replaces the stars for a track which isn't in the
//  library. Driven by a fake mouse, so no Music app is needed.
//  Positions are x inside the strip: the button spans 0 ..< 42, the heart 42 ... 64.
//

import XCTest
@testable import StarBar

final class RatingClickControllerAddTests: XCTestCase {

    private final class FakePointer: RatingPointer {
        var isLeftButtonHeld = false
        var imagePositionX: CGFloat?
    }

    /// Records any rating the control asks to save. In this mode there should never be one.
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
    private var favoriteToggles = 0
    private var addsToLibrary = 0

    override func setUp() {
        super.setUp()
        ratingControl = RatingControl(rating: 0)
        ratingControl.update(mode: .addToLibrary)
        pointer = FakePointer()
        recorder = SaveRecorder()
        ratingControl.delegate = recorder
        favoriteToggles = 0
        addsToLibrary = 0
        controller = RatingClickController(
            ratingControl: ratingControl,
            pointer: pointer,
            behavior: { .full },
            isStopped: { false },
            toggleFavorite: { [unowned self] in self.favoriteToggles += 1 }
        )
        controller.addToLibrary = { [unowned self] in self.addsToLibrary += 1 }
    }

    override func tearDown() {
        controller = nil
        ratingControl = nil
        pointer = nil
        recorder = nil
        super.tearDown()
    }

    /// Press at `x`. The menu bar's synthesised click arrives while the button is still down.
    @discardableResult
    private func press(at positionX: CGFloat, holding: Bool = false) -> Bool {
        pointer.imagePositionX = positionX
        pointer.isLeftButtonHeld = holding
        return controller.click()
    }

    // MARK: - The button

    func testPressingTheNoteAddsToTheLibrary() {
        press(at: 12)

        XCTAssertEqual(addsToLibrary, 1)
        XCTAssertEqual(recorder.savedRatings, [])
    }

    func testPressingThePlusAddsToTheLibrary() {
        press(at: 30)

        XCTAssertEqual(addsToLibrary, 1)
    }

    func testPressingTheGapBetweenThemAddsToTheLibrary() {
        // The two glyphs are one button, so the gap must not be dead
        press(at: 19)

        XCTAssertEqual(addsToLibrary, 1)
    }

    func testPressingAddsExactlyOnce() {
        press(at: 12)
        press(at: 30)

        XCTAssertEqual(addsToLibrary, 2)
    }

    // MARK: - The heart still works

    func testPressingTheHeartTogglesTheFavouriteAndDoesNotAdd() {
        press(at: 52)

        XCTAssertEqual(favoriteToggles, 1)
        XCTAssertEqual(addsToLibrary, 0)
    }

    // MARK: - No rating, no drag

    func testNothingIsEverSaved() {
        for positionX in stride(from: CGFloat(0), through: CGFloat(64), by: 2) {
            press(at: positionX)
        }

        XCTAssertEqual(recorder.savedRatings, [])
    }

    func testHoldingTheButtonDoesNotStartADrag() {
        let started = press(at: 12, holding: true)

        XCTAssertFalse(started)
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(addsToLibrary, 1, "a held press should still add, just once")
    }

    func testHoldingOutsideTheButtonDoesNotStartADrag() {
        // A press in the margin does nothing at all, and must not begin a drag either
        let started = press(at: -4, holding: true)

        XCTAssertFalse(started)
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(addsToLibrary, 0)
    }

    func testTickDoesNothingWhenNoDragBegan() {
        press(at: 12, holding: true)

        XCTAssertFalse(controller.tick())
    }

    // MARK: - Back to a ratable track

    func testDraggingWorksAgainOnceTheTrackCanBeRated() {
        ratingControl.update(mode: .rating)

        let started = press(at: 20, holding: true)

        XCTAssertTrue(started)
        XCTAssertTrue(controller.isDragging)
        XCTAssertEqual(addsToLibrary, 0)
    }

    func testClickingTheStarsSavesAgainOnceTheTrackCanBeRated() {
        ratingControl.update(mode: .rating)

        press(at: 20)

        XCTAssertEqual(recorder.savedRatings, [20])
        XCTAssertEqual(addsToLibrary, 0)
    }

}
