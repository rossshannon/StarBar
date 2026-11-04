//
//  MusicStarterTests.swift
//  StarBarTests
//
//  Created by Ross Shannon on 2026-11-04.
//

import XCTest
@testable import StarBar

/// The popover's play button with no song loaded: `MusicStarter` opens Music when it isn't
/// running, asks it to play, and says so when no song comes. Driven with fakes: nothing here
/// opens Music or sends it an event.
final class MusicStarterTests: XCTestCase {

    private var clock: FakeClock!
    private var center: NotificationCenter!
    private var isRunning = false
    private var hasTrack = false
    private var launches: [(pid_t?) -> Void] = []
    private var plays: [(pid: pid_t?, answer: () -> Void)] = []
    private var activations = 0
    private var starter: MusicStarter!

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        center = NotificationCenter()
        isRunning = false
        hasTrack = false
        launches = []
        plays = []
        activations = 0
        starter = MusicStarter(
            isRunning: { [unowned self] in self.isRunning },
            hasTrack: { [unowned self] in self.hasTrack },
            launch: { [unowned self] completion in self.launches.append(completion) },
            play: { [unowned self] pid, answer in self.plays.append((pid, answer)) },
            activate: { [unowned self] in self.activations += 1 },
            clock: clock,
            center: center)
    }

    override func tearDown() {
        starter = nil
        super.tearDown()
    }

    // MARK: - Music isn't running

    func testOpensMusicThenAsksThatProcessToPlay() {
        starter.start()
        XCTAssertEqual(starter.status, .opening)
        XCTAssertEqual(launches.count, 1)
        XCTAssertTrue(plays.isEmpty, "play waits until Music has been opened")

        isRunning = true
        launches[0](4242)
        XCTAssertEqual(starter.status, .starting)
        XCTAssertEqual(plays.map { $0.pid }, [4242], "sent to the Music just opened, not by bundle ID")
    }

    func testMusicThatWontOpenGoesBackToIdle() {
        starter.start()
        launches[0](nil)
        XCTAssertEqual(starter.status, .idle)
        XCTAssertTrue(plays.isEmpty)
    }

    func testAnUpdateWhileMusicOpensDoesNotEndTheOpening() {
        starter.start()
        // The station clears the player while Music isn't running yet
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .opening)
    }

    // MARK: - Music is running with no song

    func testAsksTheRunningMusicToPlayStraightAway() {
        isRunning = true
        starter.start()
        XCTAssertTrue(launches.isEmpty)
        XCTAssertEqual(starter.status, .starting)
        XCTAssertEqual(plays.count, 1)
        XCTAssertNil(plays[0].pid, "the Music already running")
    }

    func testASongAnnouncedEndsTheStart() {
        isRunning = true
        starter.start()
        plays[0].answer()
        hasTrack = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .idle)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the wait for a song is cancelled")
    }

    func testASongAnnouncedBeforeMusicAnswersEndsTheStartToo() {
        isRunning = true
        starter.start()
        hasTrack = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .idle)
        // Music's late answer schedules nothing
        plays[0].answer()
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
    }

    func testNoSongAfterMusicAnswersMeansNothingToPlay() {
        isRunning = true
        starter.start()
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the wait starts when Music answers, not when asked")
        plays[0].answer()
        XCTAssertEqual(clock.pendingOneShot?.seconds, MusicStarter.songWait)
        // An update with no song in it changes nothing
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .starting)
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .nothingToPlay)
    }

    func testASongThatCameWithoutAnUpdateIsStillSeenWhenTheWaitEnds() {
        isRunning = true
        starter.start()
        plays[0].answer()
        hasTrack = true
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .idle)
    }

    func testPressingAgainWhileStartingSendsNothingMore() {
        isRunning = true
        starter.start()
        starter.start()
        XCTAssertEqual(plays.count, 1)

        isRunning = false
        let second = MusicStarter(isRunning: { false }, hasTrack: { false },
                                  launch: { [unowned self] completion in self.launches.append(completion) },
                                  play: { _, _ in XCTFail("nothing is sent while Music opens") },
                                  activate: {}, clock: clock, center: NotificationCenter())
        second.start()
        second.start()
        XCTAssertEqual(launches.count, 1, "Music is opened once")
    }

    func testPressingAfterNothingToPlayBringsMusicForward() {
        isRunning = true
        starter.start()
        plays[0].answer()
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .nothingToPlay)

        starter.start()
        XCTAssertEqual(activations, 1, "Music's window is where a song can be chosen")
        XCTAssertEqual(plays.count, 1, "asking again would come to the same thing")
        XCTAssertEqual(starter.status, .idle)
    }

    func testNothingToPlayThenMusicQuitOpensItAgainOnThePress() {
        isRunning = true
        starter.start()
        plays[0].answer()
        clock.fireOneShot()
        isRunning = false
        starter.start()
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(launches.count, 1)
        XCTAssertEqual(starter.status, .opening)
    }

    func testMusicQuittingWhileStartingEndsIt() {
        isRunning = true
        starter.start()
        isRunning = false
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .idle)
    }

    func testStatusChangesAreAnnounced() {
        var posted = 0
        let observer = NotificationCenter.default.addObserver(forName: .musicStarterDidChange, object: starter, queue: nil) { _ in posted += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        isRunning = true
        starter.start()
        XCTAssertEqual(posted, 1)
        starter.start()
        XCTAssertEqual(posted, 1, "no change, no notification")
    }

    // MARK: - What the popover says

    func testEmptyStateSaysWhatPlayWillDo() {
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .idle).title, "Not Playing")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .idle).detail, "Press play to open Music.")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: true, starting: .idle).detail, "Press play to start Music.")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .opening).detail, "Opening Music…")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: true, starting: .starting).detail, "Starting Music…")
        XCTAssertTrue(PopoverEmptyState.when(musicIsRunning: true, starting: .nothingToPlay).detail.contains("choose something"))
    }

    func testNothingToPlayIsForgottenOnceMusicQuits() {
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .nothingToPlay),
                       PopoverEmptyState.when(musicIsRunning: false, starting: .idle),
                       "a press opens Music again, so say that")
    }

}
