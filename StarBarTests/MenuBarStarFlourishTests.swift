//
//  MenuBarStarFlourishTests.swift
//  StarBarTests
//
//  The menu bar's stars after a rating is saved: the flourish drawn over them and its colour
//  over that, the stars put back at rest when it ends, and what ends it early. Driven by a
//  fake clock and a fake mouse, onto fake tracks, with Reduce Motion and the flourish's look
//  set by each test rather than read from the Mac.
//

import XCTest
@testable import StarBar

final class MenuBarStarFlourishTests: XCTestCase {

    /// The mouse, where each test puts it. Positions are x inside the stars image: star i
    /// spans 4 + 20i to 20 + 20i. The tests press in a star's right half, which is the whole
    /// star whether or not half stars are on.
    private final class FakePointer: RatingPointer {
        var isLeftButtonHeld = false
        var imagePositionX: CGFloat?
    }

    private var clock: FakeClock!
    private var pointer: FakePointer!
    private var menu: MenuBarRatingControl!
    private var readReduceMotion: (() -> Bool)!
    private var readLook: (() -> StarFlourish.Look)!

    override func setUp() {
        super.setUp()
        iTunesRadioStation.shared.flushHeldRatingWrite()
        readReduceMotion = MenuBarRatingControl.reduceMotion
        MenuBarRatingControl.reduceMotion = { false }
        readLook = MenuBarRatingControl.starFlourishLook
        MenuBarRatingControl.starFlourishLook = { .afterglow }
        clock = FakeClock()
        pointer = FakePointer()
        menu = MenuBarRatingControl(widthClock: clock, pointer: pointer)
    }

    override func tearDown() {
        NSStatusBar.system.removeStatusItem(menu.statusItem)
        menu = nil
        pointer = nil
        clock = nil
        MenuBarRatingControl.reduceMotion = readReduceMotion
        MenuBarRatingControl.starFlourishLook = readLook
        // The shortcut and click tests save ratings through the real station, onto fake tracks:
        // leave none held for the next test, and no fake song as what is playing
        iTunesRadioStation.shared.flushHeldRatingWrite()
        iTunesPlayer.shared.update(nil, broadcast: false)
        super.tearDown()
    }

    /// Show a song as the one playing and let its stars roll out, so they are at rest. Time
    /// passes a frame at a time: one long step would be a held main thread, which pauses the
    /// rollout rather than finishing it.
    @discardableResult
    private func showSong(rating: Int, id: String = "00000000000000F1") -> FakeTrack {
        let song = FakeTrack(name: "Stars \(id)", persistentID: id, rating: rating)
        iTunesPlayer.shared.update(song, broadcast: false)
        menu.applyTrackDisplay(PlayingTrack(track: song), isStopped: false, musicIsRunning: true)
        clock.fireRepeating()
        clock.runFrames(for: StarRollout.settleDuration + StarRollout.duration + 0.05)
        XCTAssertTrue(clock.pendingRepeating.isEmpty, "the rollout has finished")
        XCTAssertEqual(menu.ratingControl.rating, rating)
        XCTAssertFalse(menu.isAnimating)
        XCTAssertTrue(showsStarsAtRest, "the stars at rest")
        return song
    }

    /// Rate the song on show as a click would, without Music: the stars take the rating, and
    /// the menu bar is told it was saved
    private func save(_ rating: Int) {
        let before = menu.ratingControl.rating
        menu.ratingControl.update(rating: rating)
        menu.flourishStars(saving: rating, from: before, showing: before)
    }

    /// The station sends a rating at once or holds it a moment, depending on how long ago the
    /// last one went, which another test decides: send whatever is held before counting writes
    private func sendHeldRating() {
        iTunesRadioStation.shared.flushHeldRatingWrite()
    }

    private var image: NSImage? { return menu.statusItem.button?.image }

    /// The button shows the control's own stars image, not a frame of a flourish
    private var showsStarsAtRest: Bool {
        return image === menu.ratingControl.starsImage && menu.starTintView.isHidden
    }

    private let flourishSize = StarFlourish.imageSize(starSize: NSSize(width: 16, height: 16), spacing: 4)

    // MARK: - A rating saved

    func testARaisedRatingPlaysTheFlourishOverTheStarsAndPutsThemBack() throws {
        showSong(rating: 40)

        save(80)

        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.kind, .raise)
        XCTAssertEqual(flourish.look, .afterglow)
        XCTAssertEqual(flourish.from, Stars.styles(forRating: 40))
        XCTAssertEqual(flourish.to, Stars.styles(forRating: 80))
        XCTAssertTrue(menu.isAnimating, "Music's re-reads wait while it plays")
        XCTAssertEqual(image?.size, flourishSize, "its own frame, drawn at once")
        XCTAssertEqual(image?.isTemplate, true)
        XCTAssertTrue(menu.starTintView.isHidden, "no colour on the first frame")
        XCTAssertEqual(clock.pendingRepeating.count, 1)

        // The colour goes over the stars exactly: the same size, against the button's right
        // edge inset and centred, where the button draws the stars
        clock.runFrames(for: 0.1)
        let button = try XCTUnwrap(menu.statusItem.button)
        XCTAssertFalse(menu.starTintView.isHidden)
        XCTAssertEqual(menu.starTintView.image?.isTemplate, false)
        XCTAssertEqual(menu.starTintView.frame.size, flourishSize)
        XCTAssertEqual(menu.starTintView.frame.maxX, button.bounds.maxX - 4, accuracy: 0.001)
        XCTAssertEqual(menu.starTintView.frame.midY, button.bounds.midY, accuracy: 0.001)
        XCTAssertEqual(image?.size, flourishSize)

        clock.runFrames(for: flourish.duration)
        XCTAssertNil(menu.starFlourishInPlay)
        XCTAssertFalse(menu.isAnimating)
        XCTAssertTrue(showsStarsAtRest)
        XCTAssertEqual(menu.ratingControl.rating, 80)
        XCTAssertTrue(clock.pendingRepeating.isEmpty, "and its timer has gone")
    }

    func testALoweredRatingFoldsBackWithNoColour() throws {
        showSong(rating: 80)

        save(20)

        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.kind, .lower)
        var frames = 0
        while menu.starFlourishInPlay != nil, frames < 60 {
            XCTAssertTrue(menu.starTintView.isHidden, "never a flash for stars taken away")
            clock.runFrames(for: 1.0 / 60.0)
            frames += 1
        }
        XCTAssertLessThan(frames, 16, "a quiet change, over in a quarter of a second")
        XCTAssertTrue(showsStarsAtRest)
    }

    func testReduceMotionCrossFadesTheStars() throws {
        showSong(rating: 40)
        MenuBarRatingControl.reduceMotion = { true }

        save(80)

        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.kind, .fade)
        clock.runFrames(for: StarFlourish.fadeDuration / 2)
        XCTAssertTrue(menu.starTintView.isHidden)
        XCTAssertNotNil(menu.starFlourishInPlay)
        clock.runFrames(for: StarFlourish.fadeDuration)
        XCTAssertTrue(showsStarsAtRest)
    }

    func testTheSameStarsSavedUnderReduceMotionChangeNothing() {
        showSong(rating: 60)
        MenuBarRatingControl.reduceMotion = { true }

        save(60)

        XCTAssertNil(menu.starFlourishInPlay, "nothing to fade")
        XCTAssertTrue(showsStarsAtRest)
        XCTAssertTrue(clock.pendingRepeating.isEmpty)
    }

    func testTheLookIsReadAtEachRating() throws {
        showSong(rating: 40)
        MenuBarRatingControl.starFlourishLook = { .pop }

        save(80)

        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.look, .pop)
        var frames = 0
        while menu.starFlourishInPlay != nil, frames < 60 {
            XCTAssertTrue(menu.starTintView.isHidden, "the plain pop has no colour")
            clock.runFrames(for: 1.0 / 60.0)
            frames += 1
        }
        XCTAssertTrue(showsStarsAtRest)
    }

    /// The flourish is stepped, so a held main thread pauses it where it was drawn rather than
    /// finishing it unseen
    func testAStallPausesTheFlourish() throws {
        showSong(rating: 40)
        save(80)
        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        clock.runFrames(for: 0.05)

        // Longer than the whole flourish with no frame, then one late frame
        clock.advance(by: flourish.duration + 0.5)
        clock.fireRepeating()

        XCTAssertNotNil(menu.starFlourishInPlay, "not finished unseen")
        XCTAssertEqual(image?.size, flourishSize)
        clock.runFrames(for: flourish.duration)
        XCTAssertTrue(showsStarsAtRest)
    }

    // MARK: - What ends it

    func testAnotherRatingEndsTheFlourishAndStartsItsOwn() throws {
        showSong(rating: 40)
        save(80)
        clock.runFrames(for: 0.1)

        menu.ratingControl.update(rating: 100)
        XCTAssertNil(menu.starFlourishInPlay, "the stars have moved on from what it was drawn towards")
        XCTAssertTrue(showsStarsAtRest)

        menu.flourishStars(saving: 100, from: 80, showing: 80)
        let next = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(next.to, Stars.styles(forRating: 100))
        XCTAssertEqual(clock.pendingRepeating.count, 1, "one flourish, one timer")
    }

    func testANewSongEndsTheFlourish() {
        showSong(rating: 40)
        save(80)
        clock.runFrames(for: 0.1)
        XCTAssertFalse(menu.starTintView.isHidden)

        let next = FakeTrack(name: "Next", persistentID: "00000000000000F2", rating: 20)
        iTunesPlayer.shared.update(next, broadcast: false)
        menu.applyTrackDisplay(PlayingTrack(track: next), isStopped: false, musicIsRunning: true)

        XCTAssertNil(menu.starFlourishInPlay, "it was for the last song's rating")
        XCTAssertTrue(menu.starTintView.isHidden)
        XCTAssertEqual(menu.ratingControl.rating, 20)
    }

    func testPlaybackStoppingEndsTheFlourish() {
        showSong(rating: 40)
        save(80)
        clock.runFrames(for: 0.1)

        // Music has quit
        menu.applyTrackDisplay(nil, isStopped: true, musicIsRunning: false)

        XCTAssertNil(menu.starFlourishInPlay)
        XCTAssertTrue(menu.starTintView.isHidden)
        XCTAssertTrue(image === menu.menuBarIcon.image, "the stopped icon, not a frame of the stars")
    }

    // MARK: - Through the shortcuts and the mouse

    /// A shortcut redraws the menu bar after its rating, and Music's next update for the same
    /// song agrees with the stars: neither may put the stars at rest under the flourish
    func testAShortcutsFlourishOutlivesItsOwnRedrawAndAnUpdateThatAgrees() throws {
        let song = showSong(rating: 40)

        menu.setRating(stars: 4)

        sendHeldRating()
        XCTAssertEqual(song.ratingsWritten, [80])
        XCTAssertEqual(menu.ratingControl.rating, 80)
        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.kind, .raise)
        XCTAssertEqual(flourish.from, Stars.styles(forRating: 40), "from the stars the song had")
        XCTAssertEqual(image?.size, flourishSize, "still the flourish after the shortcut's own redraw")

        clock.runFrames(for: 0.1)
        menu.applyTrackDisplay(PlayingTrack(track: song), isStopped: false, musicIsRunning: true)
        XCTAssertNotNil(menu.starFlourishInPlay)
        XCTAssertEqual(image?.size, flourishSize)
        XCTAssertFalse(menu.starTintView.isHidden)

        clock.runFrames(for: flourish.duration)
        XCTAssertTrue(showsStarsAtRest)
    }

    func testAShortcutThatLowersTheRatingIsQuiet() throws {
        let song = showSong(rating: 80)

        menu.setRating(stars: 1)

        sendHeldRating()
        XCTAssertEqual(song.ratingsWritten, [20])
        XCTAssertEqual(try XCTUnwrap(menu.starFlourishInPlay).kind, .lower)
    }

    /// On macOS 27 the click arrives as the mouse goes down: the stars follow the mouse while
    /// the button is held, each change drawn quickly, and the flourish plays at the release
    /// from what they showed then
    func testAHeldPressChangesTheStarsQuicklyAndTheReleasePlaysTheFlourishFromWhatTheyShowed() throws {
        let song = showSong(rating: 40)

        // Down on the fifth star, which spans 84 to 100 in the stars image
        pointer.isLeftButtonHeld = true
        pointer.imagePositionX = 97
        XCTAssertTrue(menu.clickController.click(), "the press began a drag")
        XCTAssertEqual(menu.ratingControl.rating, 100)
        let following = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(following.kind, .preview)
        XCTAssertEqual(following.from, Stars.styles(forRating: 40))
        XCTAssertEqual(following.to, Stars.styles(forRating: 100))
        clock.runFrames(for: StarFlourish.previewDuration + 0.05)
        XCTAssertTrue(showsStarsAtRest, "five stars, at rest under the mouse")
        XCTAssertEqual(song.ratingsWritten, [], "nothing saved while the button is held")

        // Let go on the third star, 44 to 60
        pointer.isLeftButtonHeld = false
        pointer.imagePositionX = 57
        XCTAssertFalse(menu.clickController.tick())

        sendHeldRating()
        XCTAssertEqual(song.ratingsWritten, [60])
        XCTAssertEqual(menu.ratingControl.rating, 60)
        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.kind, .raise, "three stars for a song that had two")
        XCTAssertEqual(flourish.from, Stars.styles(forRating: 100), "from the five on show, not the two the drag began on")
        XCTAssertEqual(flourish.to, Stars.styles(forRating: 60))

        clock.runFrames(for: flourish.duration + 0.05)
        XCTAssertTrue(showsStarsAtRest)
        XCTAssertTrue(clock.pendingRepeating.isEmpty)
    }

    func testADragCarryingOnReplacesTheLastQuickChangeWithItsOwn() throws {
        showSong(rating: 40)
        pointer.isLeftButtonHeld = true
        pointer.imagePositionX = 77
        XCTAssertTrue(menu.clickController.click())
        XCTAssertEqual(try XCTUnwrap(menu.starFlourishInPlay).to, Stars.styles(forRating: 80))

        pointer.imagePositionX = 97
        XCTAssertTrue(menu.clickController.tick())

        let following = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(following.from, Stars.styles(forRating: 80))
        XCTAssertEqual(following.to, Stars.styles(forRating: 100))
        XCTAssertEqual(clock.pendingRepeating.count, 1)
    }

    func testAHeldPressUnderReduceMotionSwitchesTheStarsAsItAlwaysDid() {
        showSong(rating: 40)
        MenuBarRatingControl.reduceMotion = { true }
        pointer.isLeftButtonHeld = true
        pointer.imagePositionX = 97

        XCTAssertTrue(menu.clickController.click())

        XCTAssertEqual(menu.ratingControl.rating, 100)
        XCTAssertNil(menu.starFlourishInPlay)
        XCTAssertTrue(showsStarsAtRest)
    }

}
