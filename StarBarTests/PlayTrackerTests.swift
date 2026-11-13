//
//  PlayTrackerTests.swift
//  StarBarTests
//
//  When a play counts for Last.fm. Pure, so it runs anywhere. Every test drives the tracker
//  with explicit uptimes and wall-clock times, which are kept apart on purpose (the uptime
//  starts at 5000 s, the wall clock somewhere else), so a mix-up between the two clocks shows.
//

import XCTest
@testable import StarBar

final class PlayTrackerTests: XCTestCase {

    private typealias Effect = PlayTracker.Effect

    /// What a run of timer firings emitted, and when
    private struct FiredEffect: Equatable {
        let time: TimeInterval
        let effect: PlayTracker.Effect
    }

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let base: TimeInterval = 5000
    private let song = PlayTracker.Song.test("Song")
    private let other = PlayTracker.Song.test("Other")

    /// The wall clock `seconds` into the test
    private func at(_ seconds: TimeInterval) -> Date {
        return start.addingTimeInterval(seconds)
    }

    /// The uptime `seconds` into the test
    private func up(_ seconds: TimeInterval) -> TimeInterval {
        return base + seconds
    }

    /// The player says it is playing `song`
    private func update(_ tracker: inout PlayTracker, _ song: PlayTracker.Song?, position: TimeInterval? = nil, at seconds: TimeInterval) -> [Effect] {
        return update(&tracker, .playing, song, position: position, at: seconds)
    }

    // Two functions, not one with a default state: Swift matches unlabelled arguments by
    // place, so a default in the middle can't be left out
    private func update(_ tracker: inout PlayTracker, _ state: PlayTracker.PlayerState, _ song: PlayTracker.Song?, position: TimeInterval? = nil, at seconds: TimeInterval) -> [Effect] {
        return tracker.playerDidUpdate(state: state, song: song, position: position, uptime: up(seconds), now: at(seconds))
    }

    private func fire(_ tracker: inout PlayTracker, at seconds: TimeInterval) -> [Effect] {
        return tracker.timerFired(uptime: up(seconds), now: at(seconds))
    }

    private func read(_ tracker: inout PlayTracker, _ reading: PlayTracker.PositionReading, at seconds: TimeInterval) -> [Effect] {
        return tracker.positionRead(reading, uptime: up(seconds), now: at(seconds))
    }

    private func reading(_ position: TimeInterval?, playing: Bool? = true, sameSong: Bool? = true) -> PlayTracker.PositionReading {
        return PlayTracker.PositionReading(position: position, isPlaying: playing, isSameSong: sameSong)
    }

    /// Fires the timer at each `nextDeadline` up to `seconds`, as the scrobbler does, and
    /// answers each `.checkPosition` with `answer` when one is given. Fails if the tracker
    /// asks to be fired again and again without anything falling due, which is what a
    /// deadline that `timerFired` doesn't agree with would do to the owner.
    private func runTimers(_ tracker: inout PlayTracker, until seconds: TimeInterval, answer: ((TimeInterval) -> PlayTracker.PositionReading)? = nil) -> [FiredEffect] {
        var fired: [FiredEffect] = []
        var firings = 0
        while let deadline = tracker.nextDeadline, deadline - base <= seconds {
            firings += 1
            guard firings < 100 else {
                XCTFail("nextDeadline kept asking to be fired with nothing falling due")
                break
            }
            let time = deadline - base
            for effect in tracker.timerFired(uptime: deadline, now: at(time)) {
                fired.append(FiredEffect(time: time, effect: effect))
                if case .checkPosition = effect, let answer = answer {
                    for next in tracker.positionRead(answer(time), uptime: deadline, now: at(time)) {
                        fired.append(FiredEffect(time: time, effect: next))
                    }
                }
            }
        }
        return fired
    }

    private func scrobbles(in fired: [FiredEffect]) -> [Date] {
        return fired.compactMap { if case .scrobble(_, let startedAt) = $0.effect { return startedAt } else { return nil } }
    }

    private func checks(in fired: [FiredEffect]) -> Int {
        return fired.filter { if case .checkPosition = $0.effect { return true } else { return false } }.count
    }

    /// A Music tracker that has played `song` from 0, sent its now playing at 2 and its
    /// scrobble at 120, and been asked to check the position at 243
    private func musicTrackerAtTheEnd() -> PlayTracker {
        var tracker = PlayTracker(checksPosition: true)
        _ = update(&tracker, song, at: 0)
        let fired = runTimers(&tracker, until: 243)
        XCTAssertEqual(fired.last, FiredEffect(time: 243, effect: .checkPosition(song)), "The check should come 3 s past the song's end")
        return tracker
    }

    // MARK: - Threshold

    func testThresholdIsHalfTheLengthUpToFourMinutes() {
        XCTAssertEqual(PlayTracker.threshold(for: 240), 120)
        XCTAssertEqual(PlayTracker.threshold(for: 600), 240, "Four minutes is enough for a long song")
        XCTAssertEqual(PlayTracker.threshold(for: 31), 15.5)
    }

    func testSongsOfThirtySecondsOrLessAreNeverScrobbled() {
        XCTAssertNil(PlayTracker.threshold(for: 30), "Last.fm wants longer than 30 s, not 30 s")
        XCTAssertNil(PlayTracker.threshold(for: 10))
    }

    func testASongWithNoLengthWaitsFourMinutes() {
        XCTAssertEqual(PlayTracker.threshold(for: nil), 240)
        XCTAssertEqual(PlayTracker.threshold(for: 0), 240, "A stream reports 0, which is no length, not a short song")
        XCTAssertEqual(PlayTracker.threshold(for: -1), 240)
    }

    // MARK: - One play

    func testASongPlayedStraightThrough() {
        var tracker = PlayTracker(checksPosition: false)
        XCTAssertEqual(update(&tracker, song, at: 0), [], "Nothing is announced the moment a song starts")
        XCTAssertEqual(tracker.nextDeadline, up(2))
        XCTAssertEqual(fire(&tracker, at: 1), [], "An early timer emits nothing")
        XCTAssertEqual(fire(&tracker, at: 2), [.nowPlaying(song)])
        XCTAssertEqual(tracker.nextDeadline, up(120))
        XCTAssertEqual(fire(&tracker, at: 119.5), [])
        XCTAssertEqual(fire(&tracker, at: 120), [.scrobble(song, startedAt: at(0))], "The scrobble carries the wall-clock start, not the uptime")
        XCTAssertTrue(tracker.hasScrobbled)
        XCTAssertNil(tracker.nextDeadline, "Without position checks nothing is left to do")
        XCTAssertEqual(fire(&tracker, at: 239), [], "A play scrobbles once")
    }

    func testAMusicPlayAsksForThePositionPastTheEnd() {
        var tracker = PlayTracker(checksPosition: true)
        _ = update(&tracker, song, at: 0)
        XCTAssertEqual(tracker.nextDeadline, up(2))
        XCTAssertEqual(fire(&tracker, at: 2), [.nowPlaying(song)])
        XCTAssertEqual(tracker.nextDeadline, up(120))
        XCTAssertEqual(fire(&tracker, at: 120), [.scrobble(song, startedAt: at(0))])
        XCTAssertEqual(tracker.nextDeadline, up(243), "The check is due rolloverSlack past the end")
        XCTAssertEqual(fire(&tracker, at: 243), [.checkPosition(song)])
        XCTAssertNil(tracker.nextDeadline, "No second check while the first waits for its answer")
    }

    func testALateTimerStillScrobblesOnce() {
        // A Mac asleep or a busy main thread: what fell due is all emitted together
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        XCTAssertEqual(fire(&tracker, at: 300), [.nowPlaying(song), .scrobble(song, startedAt: at(0))])
        XCTAssertEqual(fire(&tracker, at: 301), [], "A late timer must not scrobble twice")
    }

    func testPausedTimeDoesNotCount() {
        // Counting wall time rather than time played would scrobble a song paused at 50 s
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, .paused, song, at: 50), [])
        XCTAssertNil(tracker.nextDeadline, "Nothing is due while paused")
        XCTAssertEqual(fire(&tracker, at: 500), [], "A timer while paused emits nothing")

        XCTAssertEqual(update(&tracker, song, at: 1000), [], "A resume announces after the delay, not at once")
        XCTAssertEqual(tracker.nextDeadline, up(1002))
        XCTAssertEqual(fire(&tracker, at: 1002), [.nowPlaying(song)], "Now playing is sent again after a resume")
        XCTAssertEqual(tracker.nextDeadline, up(1070), "50 s played before the pause, 70 to go")
        XCTAssertEqual(fire(&tracker, at: 1069), [])
        XCTAssertEqual(fire(&tracker, at: 1070), [.scrobble(song, startedAt: at(0))])
    }

    func testMusicsBareStoppedKeepsThePlay() {
        // Music sends a Stopped naming no song between songs and a second into a streamed one
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, .stopped, nil, at: 60), [])
        XCTAssertEqual(tracker.song, song, "A bare Stopped keeps the play")
        XCTAssertEqual(update(&tracker, song, at: 61), [], "The same song again is not a new play announced at once")
        XCTAssertEqual(tracker.startedAt, at(0), "Still the first play")
        XCTAssertEqual(fire(&tracker, at: 62.5), [])
        XCTAssertEqual(fire(&tracker, at: 63), [.nowPlaying(song)])
        XCTAssertEqual(tracker.nextDeadline, up(121), "The 60 s played carries over")
    }

    func testARepeatedPlayingUpdateChangesNothing() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        XCTAssertEqual(update(&tracker, song, at: 1), [])
        XCTAssertEqual(tracker.nextDeadline, up(2), "A repeat must not restart the now-playing delay")
        _ = fire(&tracker, at: 2)
        _ = update(&tracker, song, at: 50)
        XCTAssertEqual(tracker.nextDeadline, up(120), "A repeat must not restart the count")
    }

    func testANewerTrackForTheSameSongIsKept() {
        // The player can fill in a length later; a song first seen with none would otherwise
        // wait four minutes
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, PlayTracker.Song.test("Song", duration: nil), at: 0)
        XCTAssertEqual(tracker.nextDeadline, up(2))
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(tracker.nextDeadline, up(240))
        _ = update(&tracker, song, at: 10)
        XCTAssertEqual(tracker.song, song)
        XCTAssertEqual(tracker.nextDeadline, up(120))
        XCTAssertEqual(tracker.startedAt, at(0), "The same identity is the same play")
    }

    // MARK: - Songs replacing each other

    func testANewSongReplacesThePlay() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, other, at: 100), [], "The skipped song hadn't reached its threshold")
        XCTAssertEqual(tracker.song, other)
        XCTAssertEqual(tracker.startedAt, at(100))
        let fired = runTimers(&tracker, until: 400)
        XCTAssertEqual(fired, [
            FiredEffect(time: 102, effect: .nowPlaying(other)),
            FiredEffect(time: 220, effect: .scrobble(other, startedAt: at(100)))
        ], "The first song, skipped at 100 s, never scrobbles")
    }

    func testANewSongAfterTheThresholdScrobblesTheOldOneFirst() {
        // The update for the next song arrives before the timer did: the old song's scrobble
        // must come from the play as it was, not be lost with it
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, other, at: 130), [.scrobble(song, startedAt: at(0))], "Nothing for the new song yet")
        XCTAssertEqual(tracker.song, other)
        XCTAssertFalse(tracker.hasScrobbled)
        XCTAssertEqual(tracker.nextDeadline, up(132))
    }

    func testASkipBurstAnnouncesOnlyTheLastSong() {
        var tracker = PlayTracker(checksPosition: false)
        let songs = (1...5).map { PlayTracker.Song.test("Song \($0)") }
        var emitted: [Effect] = []
        for (index, next) in songs.enumerated() {
            emitted += update(&tracker, next, at: Double(index) * 0.5)
        }
        XCTAssertEqual(emitted, [], "No song skipped through is announced")
        let fired = runTimers(&tracker, until: 10)
        XCTAssertEqual(fired, [FiredEffect(time: 4, effect: .nowPlaying(songs[4]))])
    }

    func testPausedOrStoppedOnAnotherSongDropsThePlay() {
        for state in [PlayTracker.PlayerState.paused, .stopped] {
            var tracker = PlayTracker(checksPosition: false)
            _ = update(&tracker, song, at: 0)
            _ = fire(&tracker, at: 2)
            XCTAssertEqual(update(&tracker, state, other, at: 50), [], "\(state)")
            XCTAssertNil(tracker.song, "\(state) naming another song drops the play")
            XCTAssertNil(tracker.nextDeadline)
            XCTAssertEqual(runTimers(&tracker, until: 400), [], "Neither song counts while nothing plays")

            // Music announces a song paused at 0.0 before it plays it
            _ = update(&tracker, other, at: 400)
            XCTAssertEqual(tracker.startedAt, at(400), "The other song starts counting when it plays")
            XCTAssertEqual(fire(&tracker, at: 402), [.nowPlaying(other)])
        }
    }

    func testPlayingWithNoSongPausesThePlay() {
        // A Spotify ad has no Track ID: whatever is playing isn't known to be the song
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, .playing, nil, at: 50), [])
        XCTAssertEqual(tracker.song, song, "The play is kept")
        XCTAssertNil(tracker.nextDeadline, "And paused")
        _ = update(&tracker, song, at: 100)
        XCTAssertEqual(tracker.startedAt, at(0))
        XCTAssertEqual(tracker.nextDeadline, up(102))
        _ = fire(&tracker, at: 102)
        XCTAssertEqual(tracker.nextDeadline, up(170), "The 50 s of the ad didn't count")
    }

    // MARK: - Songs that never scrobble

    func testAShortSongIsAnnouncedButNeverScrobbled() {
        for duration in [30.0, 10.0] {
            var tracker = PlayTracker(checksPosition: true)
            let short = PlayTracker.Song.test("Short", duration: duration)
            _ = update(&tracker, short, at: 0)
            XCTAssertEqual(runTimers(&tracker, until: 1000), [FiredEffect(time: 2, effect: .nowPlaying(short))], "\(duration) s: now playing only, no scrobble and no check")
        }
    }

    func testASongWithNoLengthScrobblesAtFourMinutesAndIsNeverChecked() {
        var tracker = PlayTracker(checksPosition: true)
        let stream = PlayTracker.Song.test("Stream", duration: nil)
        _ = update(&tracker, stream, at: 0)
        XCTAssertEqual(runTimers(&tracker, until: 2000), [
            FiredEffect(time: 2, effect: .nowPlaying(stream)),
            FiredEffect(time: 240, effect: .scrobble(stream, startedAt: at(0)))
        ], "With no length there is no end to check for")
    }

    func testASongThatIsntScrobblableEmitsNothing() {
        var tracker = PlayTracker(checksPosition: true)
        let episode = PlayTracker.Song.test("Episode", isScrobblable: false)
        XCTAssertEqual(update(&tracker, episode, at: 0), [])
        XCTAssertEqual(tracker.song, episode, "It is still tracked, so its identity is known")
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(fire(&tracker, at: 500), [], "Not even now playing")
        XCTAssertEqual(tracker.songRestarted(uptime: up(510), now: at(510)), [], "A restart of it emits nothing either")

        _ = update(&tracker, song, at: 600)
        XCTAssertEqual(runTimers(&tracker, until: 720), [
            FiredEffect(time: 602, effect: .nowPlaying(song)),
            FiredEffect(time: 720, effect: .scrobble(song, startedAt: at(600)))
        ], "The next song behaves normally")
    }

    // MARK: - The play before StarBar last quit

    func testTheSamePassStillPlayingAtLaunchIsNotScrobbledAgain() {
        // StarBar quit after scrobbling a song 100 s in and opened again while it played on
        let earlier = PlayTracker.Earlier(identity: song.identity, startedAt: at(-100), duration: 240)
        var tracker = PlayTracker(checksPosition: false, earlier: earlier)
        _ = update(&tracker, song, at: 0)
        XCTAssertTrue(tracker.hasScrobbled)
        XCTAssertEqual(runTimers(&tracker, until: 1000), [FiredEffect(time: 2, effect: .nowPlaying(song))], "No second scrobble of the same pass")
    }

    func testTheSameSongAfterTheEarlierPassCouldHaveEndedIsANewPlay() {
        // 240 s long, started 300 s ago: it could have ended 60 s ago, so this is another pass
        let earlier = PlayTracker.Earlier(identity: song.identity, startedAt: at(-300), duration: 240)
        var tracker = PlayTracker(checksPosition: false, earlier: earlier)
        _ = update(&tracker, song, at: 0)
        XCTAssertFalse(tracker.hasScrobbled)
        XCTAssertEqual(fire(&tracker, at: 120), [.nowPlaying(song), .scrobble(song, startedAt: at(0))])
    }

    func testAnEarlierPassWithNoLengthIsGivenTwiceTheLongestWait() {
        let earlier = PlayTracker.Earlier(identity: song.identity, startedAt: at(-400), duration: nil)
        var counted = PlayTracker(checksPosition: false, earlier: earlier)
        _ = update(&counted, song, at: 82)
        XCTAssertTrue(counted.hasScrobbled, "-400 + 480 + 3 = 83 s, still within")

        var notCounted = PlayTracker(checksPosition: false, earlier: earlier)
        _ = update(&notCounted, song, at: 84)
        XCTAssertFalse(notCounted.hasScrobbled)
    }

    func testEarlierIsConsultedByTheFirstPlayOnly() {
        let earlier = PlayTracker.Earlier(identity: song.identity, startedAt: at(-10), duration: 240)

        // A different song first uses it up
        var differentFirst = PlayTracker(checksPosition: false, earlier: earlier)
        _ = update(&differentFirst, other, at: 0)
        XCTAssertFalse(differentFirst.hasScrobbled)
        _ = update(&differentFirst, song, at: 10)
        XCTAssertFalse(differentFirst.hasScrobbled, "Only the first play is compared with earlier")

        // The same song played again after another is a new pass, though inside the window
        var again = PlayTracker(checksPosition: false, earlier: earlier)
        _ = update(&again, song, at: 0)
        XCTAssertTrue(again.hasScrobbled)
        _ = update(&again, other, at: 10)
        _ = update(&again, song, at: 20)
        XCTAssertFalse(again.hasScrobbled, "Played again is a new pass, not the one before the quit")
    }

    // MARK: - Music's position check

    func testARolloverReadingStartsANewPlay() {
        var tracker = musicTrackerAtTheEnd()
        XCTAssertEqual(read(&tracker, reading(3), at: 243), [.nowPlaying(song)], "A restart announces at once")
        XCTAssertEqual(tracker.startedAt, at(240), "Started 3 s before the reading")
        XCTAssertFalse(tracker.hasScrobbled, "A new play can scrobble again")
        XCTAssertEqual(tracker.nextDeadline, up(360), "3 s already played, 117 to go")
    }

    func testThreeLoopsGiveThreeScrobbles() {
        // Repeat One: Music posts nothing as the song begins again
        var tracker = PlayTracker(checksPosition: true)
        _ = update(&tracker, song, at: 0)
        let fired = runTimers(&tracker, until: 800, answer: { _ in self.reading(3) })
        XCTAssertEqual(scrobbles(in: fired), [at(0), at(240), at(480)])
        XCTAssertEqual(checks(in: fired), 3)
        XCTAssertEqual(fired.filter { $0.effect == .checkPosition(song) }.map { $0.time }, [243, 483, 723])
    }

    func testALateCheckIsStillARestart() {
        // Position 8 is past restartPosition, but the play overran the end by 8 s: a reading
        // judged only against restartPosition would take the loop for a seek and lose it
        var tracker = PlayTracker(checksPosition: true)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        _ = fire(&tracker, at: 120)
        XCTAssertEqual(fire(&tracker, at: 248), [.checkPosition(song)])
        XCTAssertEqual(read(&tracker, reading(8), at: 248), [.nowPlaying(song)])
        XCTAssertEqual(tracker.startedAt, at(240))
    }

    func testAReadingThatIsOnlyASeekReanchors() {
        var tracker = musicTrackerAtTheEnd()
        XCTAssertEqual(read(&tracker, reading(150), at: 243), [], "A seek back to 150 s is no restart")
        XCTAssertEqual(tracker.startedAt, at(0))
        XCTAssertTrue(tracker.hasScrobbled, "Still the play that scrobbled")
        XCTAssertEqual(tracker.nextDeadline, up(336), "The song should end 90 s from 150, plus the slack")
    }

    func testTheNextCheckAfterASeekIsNoSoonerThanTheRetry() {
        var tracker = musicTrackerAtTheEnd()
        XCTAssertEqual(read(&tracker, reading(230), at: 243), [])
        XCTAssertEqual(tracker.nextDeadline, up(273), "The end from 230 s is 13 s away, but the retry is 30")
    }

    func testAReadingOfAnotherSongDropsThePlay() {
        var tracker = musicTrackerAtTheEnd()
        XCTAssertEqual(read(&tracker, reading(3, sameSong: false), at: 243), [])
        XCTAssertNil(tracker.song)
        XCTAssertNil(tracker.nextDeadline)
    }

    func testAReadingOfAPlayerNotPlayingPausesThePlay() {
        var tracker = musicTrackerAtTheEnd()
        XCTAssertEqual(read(&tracker, reading(3, playing: false), at: 243), [])
        XCTAssertEqual(tracker.song, song, "The play is kept")
        XCTAssertEqual(tracker.startedAt, at(0), "Not a restart")
        XCTAssertNil(tracker.nextDeadline, "Paused")
    }

    func testAnUnansweredReadIsAskedAgainAfterTheRetry() {
        var tracker = musicTrackerAtTheEnd()
        XCTAssertEqual(read(&tracker, .unanswered, at: 243), [])
        XCTAssertEqual(tracker.song, song)
        XCTAssertEqual(tracker.nextDeadline, up(273))
        XCTAssertEqual(fire(&tracker, at: 272), [])
        XCTAssertEqual(fire(&tracker, at: 273), [.checkPosition(song)])
    }

    func testAPositionIsTrustedWhenTheRestIsUnanswered() {
        var tracker = musicTrackerAtTheEnd()
        XCTAssertEqual(read(&tracker, reading(2, playing: nil, sameSong: nil), at: 243), [.nowPlaying(song)])
        XCTAssertEqual(tracker.startedAt, at(241))
    }

    func testThreeUnsettledReadsStopTheAskingUntilThePlayerSpeaks() {
        // A player stuck saying "playing" must never be polled
        var tracker = musicTrackerAtTheEnd()
        _ = read(&tracker, .unanswered, at: 243)
        XCTAssertEqual(fire(&tracker, at: 273), [.checkPosition(song)])
        _ = read(&tracker, reading(150), at: 273)
        XCTAssertEqual(fire(&tracker, at: 366), [.checkPosition(song)], "150 s at 273 should end at 363, retry allowing")
        _ = read(&tracker, .unanswered, at: 366)
        XCTAssertNil(tracker.nextDeadline, "Three reads settled nothing")
        XCTAssertEqual(checks(in: runTimers(&tracker, until: 5000)), 0, "However long it plays")

        // The player names the song again: one more read is allowed
        let effects = update(&tracker, song, at: 5000) + fire(&tracker, at: 5000)
        XCTAssertEqual(effects, [.checkPosition(song)])
    }

    func testAReadingWithNoCheckWaitingChangesNothing() {
        var tracker = PlayTracker(checksPosition: true)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(read(&tracker, reading(3), at: 100), [], "A stray answer is no restart")
        XCTAssertEqual(tracker.startedAt, at(0))
        XCTAssertEqual(tracker.nextDeadline, up(120))
    }

    func testWithoutPositionChecksThereIsNeverACheck() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        XCTAssertEqual(checks(in: runTimers(&tracker, until: 5000)), 0, "Spotify is never asked for its position")
    }

    // MARK: - Positions in the payload (Spotify)

    func testAPositionNearTheStartAfterGoingBackIsARestart() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, position: 0, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, song, position: 2, at: 100), [.nowPlaying(song)])
        XCTAssertEqual(tracker.startedAt, at(98))
        XCTAssertEqual(tracker.nextDeadline, up(218), "2 s already played, 118 to go")
    }

    func testARestartAfterAScrobbleScrobblesAgain() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, position: 0, at: 0)
        _ = fire(&tracker, at: 2)
        _ = fire(&tracker, at: 120)
        XCTAssertEqual(update(&tracker, song, position: 1, at: 150), [.nowPlaying(song)])
        XCTAssertFalse(tracker.hasScrobbled)
        XCTAssertEqual(fire(&tracker, at: 269), [.scrobble(song, startedAt: at(149))])
    }

    func testASeekBackIsNoRestartAndAddsNothing() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, position: 0, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, song, position: 60, at: 100), [])
        XCTAssertEqual(tracker.startedAt, at(0))
        XCTAssertEqual(tracker.nextDeadline, up(120), "Played time is time spent playing, not the position")
    }

    func testASeekForwardAddsNothing() {
        // Taking the position for time played would scrobble a song skimmed through
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, position: 0, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, song, position: 200, at: 100), [])
        XCTAssertEqual(tracker.nextDeadline, up(120))
        XCTAssertEqual(fire(&tracker, at: 120), [.scrobble(song, startedAt: at(0))])
    }

    func testAPausedUpdateNearTheStartRestartsAndStaysPaused() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, position: 0, at: 0)
        _ = fire(&tracker, at: 2)
        XCTAssertEqual(update(&tracker, .paused, song, position: 1, at: 100), [], "Nothing is announced while paused")
        XCTAssertEqual(tracker.startedAt, at(99))
        XCTAssertNil(tracker.nextDeadline)

        _ = update(&tracker, song, position: 1, at: 200)
        XCTAssertEqual(runTimers(&tracker, until: 400), [
            FiredEffect(time: 202, effect: .nowPlaying(song)),
            FiredEffect(time: 319, effect: .scrobble(song, startedAt: at(99)))
        ])
    }

    // MARK: - Restarts from elsewhere, reset and the clock

    func testSongRestartedAllowsASecondScrobble() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = runTimers(&tracker, until: 200)
        XCTAssertTrue(tracker.hasScrobbled)
        XCTAssertEqual(tracker.songRestarted(uptime: up(200), now: at(200)), [.nowPlaying(song)])
        XCTAssertEqual(tracker.startedAt, at(200))
        XCTAssertFalse(tracker.hasScrobbled)
        XCTAssertEqual(fire(&tracker, at: 320), [.scrobble(song, startedAt: at(200))])
    }

    func testSongRestartedTakesThePosition() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = tracker.songRestarted(position: 4, uptime: up(100), now: at(100))
        XCTAssertEqual(tracker.startedAt, at(96))
        XCTAssertEqual(tracker.nextDeadline, up(216))
    }

    func testSongRestartedWithNothingTrackedDoesNothing() {
        var tracker = PlayTracker(checksPosition: false)
        XCTAssertEqual(tracker.songRestarted(uptime: up(10), now: at(10)), [])
        XCTAssertNil(tracker.song)
        XCTAssertNil(tracker.nextDeadline)
    }

    func testResetForgetsThePlay() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        tracker.reset()
        XCTAssertNil(tracker.song)
        XCTAssertNil(tracker.nextDeadline)
        XCTAssertEqual(update(&tracker, song, at: 100), [], "A new play, announced after the delay")
        XCTAssertEqual(tracker.startedAt, at(100))
        XCTAssertEqual(tracker.nextDeadline, up(102))
    }

    func testTimeGoingBackwardsAddsNoPlayedTime() {
        // A resume stamped earlier than the pause would count the seconds before the pause
        // twice and scrobble early
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 0)
        _ = fire(&tracker, at: 2)
        _ = update(&tracker, .paused, song, at: 100)
        XCTAssertEqual(update(&tracker, song, at: 50), [])
        XCTAssertEqual(tracker.nextDeadline, up(102), "The resume counts as at 100, the latest time seen")
        XCTAssertEqual(fire(&tracker, at: 102), [.nowPlaying(song)])
        XCTAssertEqual(tracker.nextDeadline, up(120), "100 s played, 20 to go")
    }

    func testAnEarlierTimerAddsNoPlayedTime() {
        var tracker = PlayTracker(checksPosition: false)
        _ = update(&tracker, song, at: 100)
        _ = fire(&tracker, at: 150)
        XCTAssertEqual(fire(&tracker, at: 120), [])
        _ = update(&tracker, .paused, song, at: 130)
        _ = update(&tracker, song, at: 300)
        _ = fire(&tracker, at: 302)
        XCTAssertEqual(tracker.nextDeadline, up(370), "The pause stamped 130 counts as 150: 50 s played, 70 to go")
    }

}
