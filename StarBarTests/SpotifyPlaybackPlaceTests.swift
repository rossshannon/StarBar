//
//  SpotifyPlaybackPlaceTests.swift
//  StarBarTests
//
//  Created by Ross Shannon on 2026-11-21.
//

import XCTest
@testable import StarBar

/// The rule that tells Spotify playing on this Mac from Spotify playing on another device,
/// from what Spotify says and whether its sound is going out
final class SpotifyPlaybackPlaceTests: XCTestCase {

    private var clock: FakeClock!
    /// What Core Audio answers when asked: true, false, or nil for "can't tell"
    private var output: Bool?
    private var place: SpotifyPlaybackPlace!
    private var decisions = 0

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        output = false
        decisions = 0
        place = SpotifyPlaybackPlace(clock: clock, readOutput: { [unowned self] in self.output })
        place.didDecide = { [unowned self] in self.decisions += 1 }
        place.reset()
    }

    /// The sound changes, as Core Audio would report it
    private func sound(_ isRunning: Bool?) {
        output = isRunning
        place.outputChanged(isRunning)
    }

    // MARK: - Playing

    func testPlayingWithItsSoundGoingOutIsHere() {
        output = true

        XCTAssertTrue(place.heard(.playing))
        XCTAssertEqual(place.place, .here)
        XCTAssertNil(clock.pendingOneShot, "nothing to wait for")
    }

    func testPlayingWhenThisMacCannotTellIsHere() {
        output = nil

        XCTAssertTrue(place.heard(.playing), "as StarBar did before it could tell")
        XCTAssertEqual(place.place, .here)
    }

    func testPlayingWithNoSoundWaitsAndThenIsElsewhere() {
        XCTAssertFalse(place.heard(.playing), "held until the sound comes or the wait ends")
        XCTAssertEqual(place.waiting, .afterPlaying)
        XCTAssertEqual(clock.pendingOneShot?.seconds, SpotifyPlaybackPlace.outputWait)

        clock.fireAllOneShots()

        XCTAssertEqual(place.place, .elsewhere)
        XCTAssertEqual(place.waiting, .none)
        XCTAssertEqual(decisions, 1, "the held notification goes out, hidden")
    }

    func testSoundThatComesDuringTheWaitIsHere() {
        XCTAssertFalse(place.heard(.playing))

        sound(true)

        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(decisions, 1, "the held notification goes out at once")
        XCTAssertNil(clock.pendingOneShot, "the wait is over")
    }

    /// A Core Audio listener that is never called (reported for macOS 15.0.1) must not leave
    /// a song playing here hidden
    func testTheWaitReadsTheSoundAgainWhenItEnds() {
        XCTAssertFalse(place.heard(.playing))
        output = true  // started, with no call

        clock.fireAllOneShots()

        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(decisions, 1)
    }

    func testANewSongOnTheOtherDeviceNeedsNoWait() {
        XCTAssertFalse(place.heard(.playing))
        clock.fireAllOneShots()

        XCTAssertTrue(place.heard(.playing), "still on the other device")
        XCTAssertEqual(place.place, .elsewhere)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testASecondPlayingDuringTheWaitWaitsOnce() {
        XCTAssertFalse(place.heard(.playing))
        XCTAssertFalse(place.heard(.playing))

        XCTAssertEqual(clock.pendingOneShots.count, 1, "the first wait was replaced")
        clock.fireAllOneShots()
        XCTAssertEqual(decisions, 1)
    }

    // MARK: - Moving between devices

    func testPlaybackMovedToThisMacIsHereAtOnce() {
        XCTAssertFalse(place.heard(.playing))
        clock.fireAllOneShots()
        decisions = 0

        sound(true)

        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(decisions, 1, "the song shows without waiting for Spotify to say anything")
    }

    func testPlaybackMovedAwayInTheMiddleOfASongIsElsewhereAfterTheWait() {
        output = true
        XCTAssertTrue(place.heard(.playing))

        sound(false)

        XCTAssertEqual(place.place, .here, "not yet: a pause stops the sound too")
        XCTAssertEqual(place.waiting, .afterSilence)
        clock.fireAllOneShots()
        XCTAssertEqual(place.place, .elsewhere)
        XCTAssertEqual(decisions, 1)
    }

    func testAPauseOnThisMacStaysHereWhicheverComesFirst() {
        output = true
        XCTAssertTrue(place.heard(.playing))

        sound(false)
        XCTAssertTrue(place.heard(.paused))

        XCTAssertEqual(place.place, .here)
        XCTAssertNil(clock.pendingOneShot, "the pause ended the wait")
        XCTAssertEqual(decisions, 0)

        // And with the notification first
        output = true
        XCTAssertTrue(place.heard(.playing))
        XCTAssertTrue(place.heard(.paused))
        sound(false)
        XCTAssertEqual(place.place, .here)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testABriefSilenceBetweenSongsStaysHere() {
        output = true
        XCTAssertTrue(place.heard(.playing))

        sound(false)
        sound(true)

        XCTAssertEqual(place.place, .here)
        XCTAssertNil(clock.pendingOneShot)
        XCTAssertEqual(decisions, 0, "nothing changed")
    }

    // MARK: - Paused and stopped

    func testAPauseOnTheOtherDeviceStaysThere() {
        XCTAssertFalse(place.heard(.playing))
        clock.fireAllOneShots()

        XCTAssertTrue(place.heard(.paused))

        XCTAssertEqual(place.place, .elsewhere, "a pause has no sound anywhere, so it says nothing")
    }

    /// A song the other device skips to and pauses before the wait ends would otherwise reach
    /// the strip as a new song chosen while paused, which it announces
    func testPlayingThenPausedWithNoSoundIsElsewhere() {
        XCTAssertFalse(place.heard(.playing))

        XCTAssertTrue(place.heard(.paused))

        XCTAssertEqual(place.place, .elsewhere)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testAPauseHereStaysHere() {
        output = true
        XCTAssertTrue(place.heard(.playing))
        output = false

        XCTAssertTrue(place.heard(.paused))
        XCTAssertTrue(place.heard(.stopped))

        XCTAssertEqual(place.place, .here)
    }

    // MARK: - Launch and quit

    func testAQuitForgetsTheOtherDevice() {
        XCTAssertFalse(place.heard(.playing))
        clock.fireAllOneShots()

        place.reset()

        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(place.waiting, .none)
    }

    func testAQuitDuringTheWaitEndsIt() {
        XCTAssertFalse(place.heard(.playing))

        place.reset()

        XCTAssertNil(clock.pendingOneShot)
        XCTAssertEqual(decisions, 0)
    }

    func testLosingCoreAudioPutsSpotifyBackHere() {
        XCTAssertFalse(place.heard(.playing))
        clock.fireAllOneShots()
        decisions = 0

        sound(nil)

        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(decisions, 1)
    }

}
