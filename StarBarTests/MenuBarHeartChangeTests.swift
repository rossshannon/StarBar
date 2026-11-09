//
//  MenuBarHeartChangeTests.swift
//  StarBarTests
//
//  The menu bar's heart changing after a click: popping through the outline with a burst
//  over the menu bar when it is set, dipping when it is cleared, a cross-fade under Reduce
//  Motion, and back at rest when the song changes. Driven by a fake clock, with Reduce Motion
//  set by each test rather than read from the Mac.
//

import XCTest
@testable import StarBar

final class MenuBarHeartChangeTests: XCTestCase {

    private var clock: FakeClock!
    private var menu: MenuBarRatingControl!
    private var readReduceMotion: (() -> Bool)!

    override func setUp() {
        super.setUp()
        readReduceMotion = MenuBarRatingControl.reduceMotion
        MenuBarRatingControl.reduceMotion = { false }
        clock = FakeClock()
        menu = MenuBarRatingControl(widthClock: clock, burstClock: clock)
    }

    override func tearDown() {
        menu.burstWindow?.stop()
        NSStatusBar.system.removeStatusItem(menu.statusItem)
        menu = nil
        clock = nil
        MenuBarRatingControl.reduceMotion = readReduceMotion
        super.tearDown()
    }

    /// Show a song and let the stars roll out, so the heart is at rest in its slot. Under the
    /// Mac's own Reduce Motion, which CI's runners have on, there is no rollout and the heart is
    /// at rest at once; the heart's change reads `reduceMotion`, which each test sets, so these
    /// tests run either way.
    private func showSong(favorited: Bool, id: String = "00000000000000E1") throws -> NSRect {
        let song = FakeTrack(name: "Heart \(id)", persistentID: id, rating: 60, favorited: favorited)
        menu.applyTrackDisplay(PlayingTrack(track: song), isStopped: false, musicIsRunning: true)
        clock.fireRepeating()
        clock.advance(by: StarRollout.duration + 0.01)
        clock.fireRepeating()
        XCTAssertEqual(menu.ratingControl.isFavorited, favorited)
        XCTAssertFalse(menu.favoriteHeartView.isHidden)
        XCTAssertTrue(menu.outgoingHeartView.isHidden, "one heart at rest")
        return menu.favoriteHeartView.frame
    }

    private var heart: NSImageView { return menu.favoriteHeartView }
    private var outgoing: NSImageView { return menu.outgoingHeartView }

    func testSettingTheHeartPopsItThroughTheOutline() throws {
        let slot = try showSong(favorited: false)
        let outline = heart.image

        menu.showChosenFavorite(true)

        XCTAssertTrue(menu.ratingControl.isFavorited)
        XCTAssertNotEqual(heart.image, outline, "the filled heart")
        XCTAssertEqual(heart.frame.width, 0, "not yet popped")
        XCTAssertFalse(outgoing.isHidden)
        XCTAssertEqual(outgoing.image, outline)
        XCTAssertEqual(outgoing.frame, slot, "the outline is all there on the first frame")

        clock.runFrames(for: 0.15)
        XCTAssertTrue(outgoing.isHidden, "the outline has shrunk away")

        clock.runFrames(for: HeartBurst.popStart + 0.16 - 0.15)
        XCTAssertGreaterThan(heart.frame.width, slot.width * 1.2, "the pop overshoots")
        XCTAssertEqual(heart.frame.midX, slot.midX, accuracy: 0.001, "about the heart's own centre")
        XCTAssertEqual(heart.frame.midY, slot.midY, accuracy: 0.001)

        clock.runFrames(for: HeartBurst.duration)
        XCTAssertEqual(heart.frame, slot, "at rest again")
        XCTAssertEqual(heart.alphaValue, 1)
        XCTAssertTrue(outgoing.isHidden)
    }

    /// The burst is drawn over the menu bar, in a window of its own, unless the item isn't on
    /// screen, where it would float in mid-air
    func testSettingTheHeartBurstsOverTheMenuBarWhenTheItemIsOnScreen() throws {
        _ = try showSong(favorited: false)

        menu.showChosenFavorite(true)

        XCTAssertEqual(menu.burstWindow?.isPlaying ?? false, menu.heartOnScreen != nil)
        guard let window = menu.burstWindow, let heart = menu.heartOnScreen else { return }
        XCTAssertEqual(window.frame.minX + window.burstView.centre!.x, heart.midX, accuracy: 0.001)
        XCTAssertEqual(window.frame.minY + window.burstView.centre!.y, heart.midY, accuracy: 0.001)
        XCTAssertNil(window.burstView.hearts, "the heart itself stays in the menu bar")

        clock.runFrames(for: HeartBurst.duration + 0.05)
        XCTAssertFalse(window.isVisible, "and the window goes when the burst is over")
    }

    func testClearingTheHeartDipsItWithNoBurst() throws {
        let slot = try showSong(favorited: true)
        let filled = heart.image

        menu.showChosenFavorite(false)

        XCTAssertFalse(menu.burstWindow?.isPlaying ?? false, "never a burst for a heart taken away")
        XCTAssertEqual(outgoing.image, filled)
        var smallest = CGFloat.infinity
        var frames = 0
        while frames < 30 {
            clock.runFrames(for: 1.0 / 60.0)
            frames += 1
            XCTAssertLessThanOrEqual(heart.frame.width, slot.width + 0.001, "it never grows")
            smallest = min(smallest, heart.frame.width)
        }
        XCTAssertEqual(smallest, slot.width * HeartChange.dipScale, accuracy: 0.5)
        XCTAssertEqual(heart.frame, slot)
        XCTAssertEqual(heart.alphaValue, 1)
        XCTAssertTrue(outgoing.isHidden)
    }

    func testUnderReduceMotionTheHeartCrossFadesInPlace() throws {
        MenuBarRatingControl.reduceMotion = { true }
        let slot = try showSong(favorited: false)

        menu.showChosenFavorite(true)

        XCTAssertFalse(menu.burstWindow?.isPlaying ?? false, "no dots under Reduce Motion")
        XCTAssertEqual(heart.frame, slot)
        XCTAssertEqual(heart.alphaValue, 0, accuracy: 0.001)
        XCTAssertFalse(outgoing.isHidden)
        clock.runFrames(for: HeartChange.fadeDuration / 2)
        XCTAssertEqual(heart.frame, slot, "the same size throughout")
        XCTAssertEqual(outgoing.frame, slot)
        XCTAssertEqual(heart.alphaValue, 0.5, accuracy: 0.05)
        clock.runFrames(for: HeartChange.fadeDuration)
        XCTAssertEqual(heart.alphaValue, 1)
        XCTAssertTrue(outgoing.isHidden)
    }

    func testANewSongPutsTheHeartBackAtRest() throws {
        let slot = try showSong(favorited: false)
        menu.showChosenFavorite(true)
        clock.runFrames(for: 0.05)

        let next = FakeTrack(name: "Next", persistentID: "00000000000000E2", rating: 20, favorited: true)
        menu.applyTrackDisplay(PlayingTrack(track: next), isStopped: false, musicIsRunning: true)
        clock.runFrames(for: 1.0 / 60.0)

        XCTAssertEqual(heart.frame, slot)
        XCTAssertEqual(heart.alphaValue, 1)
        XCTAssertTrue(outgoing.isHidden)
        XCTAssertFalse(menu.burstWindow?.isPlaying ?? false, "the burst goes with it")
    }

    func testAHeartChangedAgainBeforeItHasFinishedStartsAfresh() throws {
        let slot = try showSong(favorited: false)
        menu.showChosenFavorite(true)
        clock.runFrames(for: 0.3)

        menu.showChosenFavorite(false)

        XCTAssertFalse(menu.burstWindow?.isPlaying ?? false, "the burst is put away")
        clock.runFrames(for: HeartChange.dipDuration + 0.02)
        XCTAssertEqual(heart.frame, slot)
        XCTAssertTrue(outgoing.isHidden)
        XCTAssertFalse(menu.ratingControl.isFavorited)
    }

}
