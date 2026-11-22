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

    // MARK: - A new song while the last one's sound goes on

    /// Spotify announces a song started on another device before this Mac's sound for the
    /// song before has stopped: measured 2026-11-21, “Fairytale of New York” started on an
    /// Alexa was announced 0.86 s before the sound of the song this Mac had been playing
    /// stopped, and reached the strip
    func testANewSongStartedElsewhereWhileThisMacStillSoundsIsHidden() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 23)

        XCTAssertFalse(place.heard(.playing, song: "b", position: 0.252, duration: 272), "held until the sound says")
        XCTAssertEqual(place.waiting, .afterNewSong)
        XCTAssertEqual(clock.pendingOneShot?.seconds, SpotifyPlaybackPlace.confirmWait)

        clock.advance(by: 0.86)
        sound(false)
        XCTAssertEqual(place.waiting, .afterNewSong, "the wait decides, so a gap between songs isn't taken for another device")
        XCTAssertEqual(decisions, 0)

        clock.fireAllOneShots()

        XCTAssertEqual(place.place, .elsewhere)
        XCTAssertEqual(decisions, 1, "the held notification goes out, hidden")
    }

    func testANewSongChosenOnThisMacShowsOnceItsSoundGoesOn() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 40)

        XCTAssertFalse(place.heard(.playing, song: "b", position: 0, duration: 272), "a skip looks the same at first")
        clock.fireAllOneShots()

        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(decisions, 1, "the held notification goes out, shown")
    }

    func testTheNextSongInTheQueueNeedsNoWait() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 190, duration: 210))
        clock.advance(by: 20)

        XCTAssertTrue(place.heard(.playing, song: "b", position: 0, duration: 272))
        XCTAssertEqual(place.place, .here)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testTheNextSongAfterACrossfadeNeedsNoWait() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 100, duration: 210))
        clock.advance(by: 98)  // 12 s left: the longest crossfade Spotify offers

        XCTAssertTrue(place.heard(.playing, song: "b", position: 0, duration: 272))
        XCTAssertNil(clock.pendingOneShot)
    }

    func testASongWhoseLengthIsUnknownIsHeld() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a"))
        clock.advance(by: 300)

        XCTAssertFalse(place.heard(.playing, song: "b"), "it can't be known to be the next in the queue")
    }

    /// The time left counts only while the song before was playing
    func testASongPausedNearItsEndThenFollowedNeedsNoWait() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 30)
        XCTAssertTrue(place.heard(.paused, song: "a", position: 200, duration: 210))
        clock.advance(by: 60)

        XCTAssertTrue(place.heard(.playing, song: "b", position: 0, duration: 272))
    }

    /// Measured 2026-11-21: a song started on this Mac began sending sound 26 ms before
    /// Spotify announced it
    func testASongWhoseSoundJustStartedNeedsNoWait() {
        XCTAssertTrue(place.heard(.paused, song: "a", position: 30, duration: 210))
        clock.advance(by: 60)

        sound(true)
        clock.advance(by: 0.026)

        XCTAssertTrue(place.heard(.playing, song: "b", position: 0, duration: 272))
        XCTAssertEqual(place.place, .here)
        XCTAssertNil(clock.pendingOneShot)
    }

    /// Core Audio's listener may be late: a sound read with the notification that wasn't
    /// going out before started for this song
    func testASoundFirstReadWithTheNotificationIsThisSongs() {
        XCTAssertTrue(place.heard(.paused, song: "a", position: 30, duration: 210))
        clock.advance(by: 60)
        output = true  // started, with no call yet

        XCTAssertTrue(place.heard(.playing, song: "b", position: 0, duration: 272))
        XCTAssertNil(clock.pendingOneShot)
    }

    func testTheFirstSongHeardNeedsNoWait() {
        output = true
        place.reset()
        clock.advance(by: 30)

        XCTAssertTrue(place.heard(.playing, song: "a", position: 30, duration: 210), "nothing says the sound is another song's")
    }

    func testTheSameSongAgainNeedsNoWait() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 30)

        XCTAssertTrue(place.heard(.paused, song: "a", position: 30, duration: 210))
        XCTAssertTrue(place.heard(.playing, song: "a", position: 30, duration: 210))
        XCTAssertNil(clock.pendingOneShot)
    }

    func testSpotifySayingTheHeldSongAgainKeepsTheWait() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 40)
        XCTAssertFalse(place.heard(.playing, song: "b", position: 0, duration: 272))
        clock.advance(by: 0.5)

        XCTAssertFalse(place.heard(.playing, song: "b", position: 0.5, duration: 272))
        XCTAssertEqual(clock.pendingOneShots.count, 1, "the wait runs on from the first")

        clock.fireAllOneShots()
        XCTAssertEqual(decisions, 1)
    }

    func testAnotherSkipDuringTheWaitWaitsAgain() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 40)
        XCTAssertFalse(place.heard(.playing, song: "b", position: 0, duration: 272))
        clock.advance(by: 1)

        XCTAssertFalse(place.heard(.playing, song: "c", position: 0, duration: 190))
        XCTAssertEqual(clock.pendingOneShots.count, 1, "the first wait was replaced")
        clock.fireAllOneShots()
        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(decisions, 1)
    }

    func testAGapBetweenSongsOnThisMacShowsAsTheSoundReturns() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 40)
        XCTAssertFalse(place.heard(.playing, song: "b", position: 0, duration: 272))

        sound(false)
        sound(true)

        XCTAssertEqual(place.place, .here)
        XCTAssertEqual(decisions, 1, "the held notification goes out without waiting the rest")
        XCTAssertNil(clock.pendingOneShot)
    }

    func testAPlayingWithNoSoundDuringTheWaitLeavesItToTheWait() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 40)
        XCTAssertFalse(place.heard(.playing, song: "b", position: 0.25, duration: 272))
        sound(false)

        XCTAssertFalse(place.heard(.playing, song: "b", position: 1, duration: 272))
        XCTAssertEqual(clock.pendingOneShot?.seconds, SpotifyPlaybackPlace.confirmWait, "not a fresh, longer wait")
        clock.fireAllOneShots()
        XCTAssertEqual(place.place, .elsewhere)
    }

    func testAPauseOnceTheSoundStoppedDuringTheWaitIsElsewhere() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 40)
        XCTAssertFalse(place.heard(.playing, song: "b", position: 0.25, duration: 272))
        sound(false)

        XCTAssertTrue(place.heard(.paused, song: "b", position: 2, duration: 272))

        XCTAssertEqual(place.place, .elsewhere)
        XCTAssertNil(clock.pendingOneShot)
    }

    func testAQuitDuringTheNewSongsWaitEndsIt() {
        output = true
        XCTAssertTrue(place.heard(.playing, song: "a", position: 0, duration: 210))
        clock.advance(by: 40)
        XCTAssertFalse(place.heard(.playing, song: "b", position: 0, duration: 272))

        place.reset()

        XCTAssertNil(clock.pendingOneShot)
        XCTAssertEqual(place.waiting, .none)
        XCTAssertEqual(decisions, 0)
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
