//
//  RatingClickControllerTests.swift
//  StarBarTests
//
//  Clicks and drags on the menu bar stars, driven by a fake mouse.
//  Positions are x inside the stars image: star i spans 4 + 20i ... 20 + 20i,
//  and the heart spans 108 ... 124.
//

import XCTest
import Cocoa
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

    /// The song on show changed while the button was down. Let go of, the drag would rate
    /// the new song, so it is dropped: nothing is saved then or on release.
    func testACancelledDragSavesNothingWhenLetGo() {
        XCTAssertTrue(press(at: 12))
        XCTAssertTrue(move(to: 97))
        controller.cancelDrag()
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(ratingControl.rating, 40, "the preview goes, for the new song's rating to replace")
        XCTAssertFalse(release(at: 97))
        XCTAssertEqual(recorder.savedRatings, [])
        XCTAssertEqual(dragEnds, [], "the owner already shows the new song, so it isn't asked to refresh")
    }

    func testCancellingWithNoDragChangesNothing() {
        controller.cancelDrag()
        XCTAssertEqual(ratingControl.rating, 40)
        XCTAssertEqual(dragEnds, [])
    }

    func testNewClickStartsFreshDrag() {
        XCTAssertTrue(press(at: 97))
        click(at: 52)
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(recorder.savedRatings, [60])
    }

    // MARK: - In the menu bar

    func testASongChangeInTheMenuBarDropsTheDragAndSavesNothing() {
        // The click controller's own test above shows what cancelling does; this one shows
        // the menu bar cancels, which a test of the controller alone can't
        let menu = MenuBarRatingControl(widthClock: FakeClock(), pointer: pointer)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        let first = FakeTrack(name: "First", persistentID: "00000000000000A1", rating: 40)
        let second = FakeTrack(name: "Second", persistentID: "00000000000000B2", rating: 80)
        menu.applyTrackDisplay(PlayingTrack(track: first), isStopped: false, musicIsRunning: true)
        XCTAssertEqual(menu.ratingControl.rating, 40)

        XCTAssertTrue(press(at: 97, in: menu), "the press began a drag")
        XCTAssertEqual(menu.ratingControl.rating, 100, "the stars follow the drag")
        menu.applyTrackDisplay(PlayingTrack(track: second), isStopped: false, musicIsRunning: true)

        XCTAssertFalse(menu.isDragging)
        XCTAssertEqual(menu.ratingControl.rating, 80, "the new song's stars, not the drag's")
        pointer.isLeftButtonHeld = false
        XCTAssertFalse(menu.clickController.tick())
        XCTAssertEqual(first.ratingsWritten, [])
        XCTAssertEqual(second.ratingsWritten, [])
        XCTAssertEqual(menu.ratingControl.rating, 80)
    }

    func testAReadMusicDidNotAnswerKeepsTheHeartJustCleared() {
        // A failed read answers false, which agreed with a heart just cleared and so ended
        // the hold, and Music's next answer, still the old heart, put it back (the fourth
        // review, 2026-10-29)
        let menu = MenuBarRatingControl(widthClock: FakeClock(), pointer: pointer)
        let station = iTunesRadioStation.shared
        defer {
            NSStatusBar.system.removeStatusItem(menu.statusItem)
            iTunesPlayer.shared.update(nil, broadcast: false)
        }
        let id = "00000000000000D4"
        let song = FakeTrack(name: "Song", persistentID: id, rating: 40, favorited: true)
        iTunesPlayer.shared.update(song, broadcast: false)
        menu.applyTrackDisplay(PlayingTrack(track: song), isStopped: false, musicIsRunning: true)
        XCTAssertTrue(menu.ratingControl.isFavorited)

        menu.toggleFavorite()
        XCTAssertEqual(song.favoritesWritten, [false])
        XCTAssertFalse(menu.ratingControl.isFavorited)

        // Music doesn't answer: Scripting Bridge reports the failure and answers false
        let unanswered = FakeTrack(name: "Song", persistentID: id, rating: 0, favorited: false)
        unanswered.whenRead = {
            _ = station.eventDidFail(NSAppleEventDescriptor.appleEvent(
                withEventClass: AEEventClass(0x636F7265), eventID: AEEventID(0x67657464), targetDescriptor: nil,   // core/getd
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)).aeDesc!,
                withError: NSError(domain: NSOSStatusErrorDomain, code: -1712, userInfo: nil))
        }
        menu.applyTrackDisplay(PlayingTrack(track: unanswered), isStopped: false, musicIsRunning: true)
        XCTAssertFalse(menu.ratingControl.isFavorited)
        XCTAssertEqual(menu.ratingControl.rating, 40, "no answer is not unrated: the stars on show stay")

        // Music answers, before it has applied the write
        let stale = FakeTrack(name: "Song", persistentID: id, rating: 40, favorited: true)
        menu.applyTrackDisplay(PlayingTrack(track: stale), isStopped: false, musicIsRunning: true)
        XCTAssertFalse(menu.ratingControl.isFavorited, "still held: the read that failed didn't end it")
    }

    /// Press at `x` on the menu bar's own stars
    private func press(at x: CGFloat, in menu: MenuBarRatingControl) -> Bool {
        pointer.isLeftButtonHeld = true
        pointer.imagePositionX = x
        return menu.clickController.click()
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
