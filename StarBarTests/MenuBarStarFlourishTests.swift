//
//  MenuBarStarFlourishTests.swift
//  StarBarTests
//
//  The menu bar's stars after a rating is saved: the flourish drawn over them and its colour
//  over that, the stars put back at rest when it ends, what ends it early, and the five-star
//  finale thrown over the menu bar with it. Driven by a fake clock and a fake mouse, onto
//  fake tracks, with Reduce Motion and the flourish's look set by each test rather than read
//  from the Mac.
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
        // A status item made in a test is never on screen. Say so, whatever the Mac running
        // the tests makes of it, so the finale's window goes up only where a test puts the
        // item on screen (`putItemOnScreen`).
        menu.heartOnScreenInTests = { nil }
    }

    override func tearDown() {
        menu.finaleWindow?.stop()
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

    // MARK: - The five-star finale

    /// Say where the item's heart is on screen, as `MenuBarHeartChangeTests` does: 12 points
    /// below the top of the main screen, as on a 24 point menu bar
    @discardableResult
    private func putItemOnScreen() -> NSRect {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let heart = NSRect(x: screen.midX.rounded(), y: screen.maxY - 12 - 8, width: 16, height: 16)
        menu.heartOnScreenInTests = { heart }
        return heart
    }

    private var finaleIsPlaying: Bool {
        return menu.finaleWindow?.isPlaying ?? false
    }

    func testASongGivenFiveStarsThrowsTheFinaleOverTheMenuBar() throws {
        MenuBarRatingControl.starFlourishLook = { .run }
        let heart = putItemOnScreen()
        showSong(rating: 60)

        save(100)

        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.look, .run)
        XCTAssertTrue(flourish.hasFinale)
        let window = try XCTUnwrap(menu.finaleWindow)
        XCTAssertTrue(window.isPlaying)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.finaleView.finale, StarFinale.menuBar(starSize: 16, spacing: 4, stagger: 0.05))
        XCTAssertEqual(window.finaleView.elapsed, 0, "its first frame, which is empty")
        // The first star is five stars, their gaps and the gap before the heart to the left
        // of the heart, and its centre a little under its slot's
        let centre = NSPoint(x: window.frame.minX + window.finaleView.origin.x, y: window.frame.minY + window.finaleView.origin.y)
        XCTAssertEqual(centre.x, heart.midX - (5 * 20 + 4), accuracy: 0.001)
        XCTAssertEqual(centre.y, heart.midY - 0.764, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(menu.firstStarOnScreen).x, centre.x, accuracy: 0.001)

        clock.runFrames(for: 0.3)
        XCTAssertEqual(window.finaleView.elapsed, 0.3, accuracy: 0.001, "stepped with the stars")
        XCTAssertEqual(image?.size, flourishSize, "which are still popping")

        // The run is over by now, and the small stars are still in the air
        clock.runFrames(for: 0.3)
        XCTAssertLessThan(flourish.starsDuration, 0.6)
        XCTAssertTrue(showsStarsAtRest, "the stars have landed, and are at rest under the small stars")
        XCTAssertNotNil(menu.starFlourishInPlay, "the flourish lasts as long as its finale")
        XCTAssertTrue(menu.isAnimating, "so Music's re-reads wait for the finale too")
        XCTAssertTrue(window.isPlaying)
        XCTAssertEqual(window.finaleView.elapsed, 0.6, accuracy: 0.001)

        clock.runFrames(for: flourish.duration - 0.6 + 0.05)
        XCTAssertNil(menu.starFlourishInPlay)
        XCTAssertFalse(menu.isAnimating)
        XCTAssertFalse(window.isVisible, "the window goes with the last small star")
        XCTAssertFalse(window.isPlaying)
        XCTAssertTrue(showsStarsAtRest)
        XCTAssertTrue(clock.pendingRepeating.isEmpty)
    }

    /// The small stars leave as the look in use reaches each star: one after another for the
    /// runs, all together for the plain pop
    func testTheFinaleKeepsTimeWithTheLookInUse() throws {
        putItemOnScreen()
        showSong(rating: 60)
        for look in StarFlourish.Look.allCases {
            MenuBarRatingControl.starFlourishLook = { look }

            save(100)

            let window = try XCTUnwrap(menu.finaleWindow)
            XCTAssertTrue(window.isPlaying, "\(look)")
            XCTAssertEqual(window.finaleView.finale?.stagger, look.stagger, "\(look)")
            let flourish = try XCTUnwrap(menu.starFlourishInPlay)
            XCTAssertGreaterThanOrEqual(flourish.duration, StarFinale.duration(stagger: look.stagger), "\(look)")
            clock.runFrames(for: flourish.duration + 0.05)
            XCTAssertFalse(window.isPlaying, "\(look)")
            XCTAssertTrue(showsStarsAtRest, "\(look)")

            // Back to three stars, quietly, for the next look
            save(60)
            clock.runFrames(for: 0.5)
            XCTAssertNil(menu.starFlourishInPlay, "\(look)")
        }
    }

    func testFiveStarsChosenAgainAndEveryOtherRatingHaveNoFinale() throws {
        putItemOnScreen()
        showSong(rating: 100)

        save(100)
        let again = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(again.kind, .raise, "the stars still pop")
        XCTAssertFalse(again.hasFinale, "the song already had five")
        XCTAssertFalse(finaleIsPlaying)
        clock.runFrames(for: again.duration + 0.05)

        save(80)
        XCTAssertEqual(try XCTUnwrap(menu.starFlourishInPlay).kind, .lower)
        XCTAssertFalse(finaleIsPlaying)
        clock.runFrames(for: 0.5)

        save(90)
        let nearly = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(nearly.kind, .raise)
        XCTAssertFalse(nearly.hasFinale, "four and a half isn't five")
        XCTAssertFalse(finaleIsPlaying)
    }

    /// Where the item isn't on screen, small stars would fly out of nothing, so only the
    /// stars pop
    func testNoFinaleWindowWhenTheItemIsntOnScreen() throws {
        showSong(rating: 60)

        save(100)

        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertTrue(flourish.hasFinale)
        XCTAssertNil(menu.firstStarOnScreen)
        XCTAssertFalse(finaleIsPlaying)
        XCTAssertEqual(image?.size, flourishSize, "the stars still pop in the menu bar")
        clock.runFrames(for: flourish.duration + 0.05)
        XCTAssertTrue(showsStarsAtRest)
    }

    func testReduceMotionHasNoFinale() throws {
        putItemOnScreen()
        showSong(rating: 60)
        MenuBarRatingControl.reduceMotion = { true }

        save(100)

        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        XCTAssertEqual(flourish.kind, .fade)
        XCTAssertFalse(flourish.hasFinale)
        XCTAssertFalse(finaleIsPlaying, "nothing may move")
    }

    func testAnotherRatingOrANewSongTakesTheFinaleDown() throws {
        putItemOnScreen()
        showSong(rating: 60)
        save(100)
        clock.runFrames(for: 0.2)
        let window = try XCTUnwrap(menu.finaleWindow)
        XCTAssertTrue(window.isPlaying)

        // The user thinks again: four stars
        menu.ratingControl.update(rating: 80)
        XCTAssertFalse(window.isPlaying, "it was for five stars, which the song no longer shows")
        XCTAssertFalse(window.isVisible)
        menu.flourishStars(saving: 80, from: 100, showing: 100)
        XCTAssertFalse(window.isPlaying, "and a rating lowered is quiet")
        clock.runFrames(for: 0.5)

        // Five again, and the next song starts while the small stars are in the air
        save(100)
        XCTAssertTrue(window.isPlaying, "the same window, put up again")
        XCTAssertEqual(window.finaleView.elapsed, 0)
        clock.runFrames(for: 0.2)
        let next = FakeTrack(name: "Next", persistentID: "00000000000000F2", rating: 20)
        iTunesPlayer.shared.update(next, broadcast: false)
        menu.applyTrackDisplay(PlayingTrack(track: next), isStopped: false, musicIsRunning: true)
        XCTAssertNil(menu.starFlourishInPlay)
        XCTAssertFalse(window.isPlaying, "they were for the last song")
        XCTAssertFalse(window.isVisible)
    }

    /// The stars and their finale share one timeline, so a held main thread pauses both alike
    func testAStallPausesTheFinaleWithTheStars() throws {
        putItemOnScreen()
        showSong(rating: 60)
        save(100)
        clock.runFrames(for: 0.1)

        // Longer than the whole finale with no frame, then one late frame
        clock.advance(by: 1.5)
        clock.fireRepeating()

        let window = try XCTUnwrap(menu.finaleWindow)
        XCTAssertTrue(window.isPlaying, "not finished unseen")
        XCTAssertNotNil(menu.starFlourishInPlay)
        XCTAssertEqual(window.finaleView.elapsed, 0.1 + SteppedTimeline.maxStep, accuracy: 0.001, "where the stars are")
    }

    /// The shortcut redraws the menu bar after its own rating, and Music's next update agrees
    /// with the stars: neither takes the finale down
    func testAShortcutToFiveStarsThrowsTheFinaleAndItOutlivesTheRedraw() throws {
        putItemOnScreen()
        let song = showSong(rating: 60)

        menu.setRating(stars: 5)

        sendHeldRating()
        XCTAssertEqual(song.ratingsWritten, [100])
        XCTAssertTrue(try XCTUnwrap(menu.starFlourishInPlay).hasFinale)
        XCTAssertTrue(finaleIsPlaying)

        clock.runFrames(for: 0.1)
        menu.applyTrackDisplay(PlayingTrack(track: song), isStopped: false, musicIsRunning: true)
        XCTAssertNotNil(menu.starFlourishInPlay)
        XCTAssertTrue(finaleIsPlaying)
        XCTAssertEqual(try XCTUnwrap(menu.finaleWindow).finaleView.elapsed, 0.1, accuracy: 0.001)
    }

    /// The stars land before their small stars do. From then on the button shows the stars at
    /// rest, and a redraw that changes nothing, as after a shortcut or an update from Music
    /// that agrees with the stars, leaves them so and the small stars flying.
    func testARedrawAfterTheStarsHaveLandedLeavesThemAtRestUnderTheFinale() throws {
        MenuBarRatingControl.starFlourishLook = { .run }
        putItemOnScreen()
        let song = showSong(rating: 60)

        menu.setRating(stars: 5)

        sendHeldRating()
        XCTAssertEqual(song.ratingsWritten, [100])
        let flourish = try XCTUnwrap(menu.starFlourishInPlay)
        let window = try XCTUnwrap(menu.finaleWindow)
        clock.runFrames(for: flourish.starsDuration - 0.1)
        XCTAssertEqual(image?.size, flourishSize, "the stars are still popping")

        clock.runFrames(for: 0.2)
        XCTAssertTrue(showsStarsAtRest, "landed")
        XCTAssertNotNil(menu.starFlourishInPlay)
        XCTAssertTrue(window.isPlaying)

        menu.applyTrackDisplay(PlayingTrack(track: song), isStopped: false, musicIsRunning: true)
        XCTAssertTrue(showsStarsAtRest)
        XCTAssertNotNil(menu.starFlourishInPlay, "the flourish isn't over")
        XCTAssertTrue(menu.isAnimating)
        XCTAssertTrue(window.isPlaying)

        clock.runFrames(for: 0.1)
        XCTAssertTrue(showsStarsAtRest, "not drawn again as the small stars are stepped")
        XCTAssertEqual(window.finaleView.elapsed, flourish.starsDuration + 0.2, accuracy: 0.001)

        clock.runFrames(for: flourish.duration)
        XCTAssertNil(menu.starFlourishInPlay)
        XCTAssertFalse(window.isPlaying)
        XCTAssertTrue(showsStarsAtRest)
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
