//
//  MusicStarterTests.swift
//  StarBarTests
//
//  Created by Ross Shannon on 2026-11-04.
//

import XCTest
@testable import StarBar

/// The popover's play button with no song loaded: `MusicStarter` plays the last library song
/// StarBar saw (`LastMusicSong`), opening Music first when it isn't running, and brings Music
/// forward when there is none or Music won't play it. Driven with fakes: nothing here opens
/// Music or sends it an event.
final class MusicStarterTests: XCTestCase {

    private static let analogue = LastMusicSong(persistentID: "1D48A07F86924E5C", name: "Analogue", artist: "A-Ha")

    private var clock: FakeClock!
    private var center: NotificationCenter!
    private var defaults: UserDefaults!
    private var store: LastMusicSongStore!
    private var isRunning = false
    /// Whether the process Music was opened as is there, when that differs from `isRunning`
    private var processAlive: Bool?
    private var hasTrack = false
    private var isPlaying = false
    private var launches: [(pid_t?) -> Void] = []
    private var plays: [(pid: pid_t?, song: LastMusicSong, answer: (MusicStarter.PlayAnswer) -> Void)] = []
    private var activations = 0
    private var starter: MusicStarter!

    override func setUp() {
        super.setUp()
        clock = FakeClock()
        center = NotificationCenter()
        defaults = UserDefaults(suiteName: "MusicStarterTests")
        defaults.removePersistentDomain(forName: "MusicStarterTests")
        store = LastMusicSongStore(defaults: defaults)
        store.remember(MusicStarterTests.analogue)
        isRunning = false
        processAlive = nil
        hasTrack = false
        isPlaying = false
        launches = []
        plays = []
        activations = 0
        starter = MusicStarter(
            isRunning: { [unowned self] in self.isRunning },
            isAlive: { [unowned self] _ in self.processAlive ?? self.isRunning },
            hasTrack: { [unowned self] in self.hasTrack },
            isPlaying: { [unowned self] in self.isPlaying },
            store: store,
            launch: { [unowned self] completion in self.launches.append(completion) },
            play: { [unowned self] pid, song, answer in self.plays.append((pid, song, answer)) },
            activate: { [unowned self] in self.activations += 1 },
            clock: clock,
            center: center)
    }

    override func tearDown() {
        starter = nil
        defaults.removePersistentDomain(forName: "MusicStarterTests")
        super.tearDown()
    }

    // MARK: - Music isn't running

    func testOpensMusicThenAsksThatProcessToPlayTheLastSong() {
        starter.start()
        XCTAssertEqual(starter.status, .opening)
        XCTAssertEqual(launches.count, 1)
        XCTAssertTrue(plays.isEmpty, "play waits until Music has been opened")
        XCTAssertEqual(activations, 0, "opened in the background, so the popover stays")

        isRunning = true
        launches[0](4242)
        XCTAssertEqual(starter.status, .starting)
        XCTAssertEqual(plays.map { $0.pid }, [4242], "sent to the Music just opened, not by bundle ID")
        XCTAssertEqual(plays.first?.song, MusicStarterTests.analogue)
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

    func testWithNoSongRememberedPlayBringsMusicForward() {
        store.forget(MusicStarterTests.analogue)
        starter.start()
        XCTAssertEqual(activations, 1)
        XCTAssertTrue(launches.isEmpty, "bringing Music forward opens it too")
        XCTAssertTrue(plays.isEmpty)
        XCTAssertEqual(starter.status, .idle)
    }

    func testASongAnnouncedEndsTheStart() {
        isRunning = true
        starter.start()
        plays[0].answer(.taken)
        hasTrack = true
        isPlaying = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .idle)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the wait for a song is cancelled")
    }

    func testASongAnnouncedBeforeMusicAnswersEndsTheStartToo() {
        isRunning = true
        starter.start()
        hasTrack = true
        isPlaying = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .idle)
        // Music's late answer schedules nothing
        plays[0].answer(.taken)
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
    }

    func testARefusedSongIsForgottenAndTheNextPressBringsMusicForward() {
        isRunning = true
        starter.start()
        plays[0].answer(.songNotFound)
        XCTAssertEqual(starter.status, .couldNotPlay)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "a refusal isn't asked again")
        XCTAssertNil(store.song, "a song Music won't play, likely deleted, isn't offered again")

        starter.start()
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(plays.count, 1)
        XCTAssertEqual(starter.status, .idle)
    }

    func testASongLoadedButNotPlayingDoesNotEndTheStart() {
        isRunning = true
        starter.start()
        plays[0].answer(.taken)
        // Music loads the song asked for stopped, and announces it paused at 0.0, a moment
        // before it plays
        hasTrack = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .starting)
        XCTAssertEqual(plays.count, 1, "not asked again on sight of a paused song")
    }

    func testNothingPlayingAfterTheFirstWaitAsksOnceMore() {
        // Measured: once in about seven cold launches, Music took the play and then put back
        // the song it had been paused on when it quit, paused
        starter.start()
        isRunning = true
        launches[0](4242)
        plays[0].answer(.taken)
        hasTrack = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(clock.pendingOneShot?.seconds, MusicStarter.retryWait)
        clock.fireOneShot()
        XCTAssertEqual(plays.count, 2)
        XCTAssertEqual(plays[1].pid, 4242, "the Music this press opened")
        XCTAssertEqual(plays[1].song, MusicStarterTests.analogue)
        XCTAssertEqual(starter.status, .starting)

        isPlaying = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .idle)
    }

    func testNoSongAfterAskingTwiceMeansItCouldNotPlay() {
        isRunning = true
        starter.start()
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the wait starts when Music answers, not when asked")
        plays[0].answer(.taken)
        // An update with no song in it changes nothing
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .starting)
        clock.fireOneShot()
        XCTAssertEqual(plays.count, 2)
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the second wait starts when Music answers again")
        plays[1].answer(.taken)
        XCTAssertEqual(clock.pendingOneShot?.seconds, MusicStarter.songWait)
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .couldNotPlay)
        XCTAssertEqual(plays.count, 2, "asked twice at most")
        XCTAssertEqual(store.song, MusicStarterTests.analogue, "Music took it, so it is still in the library")

        starter.start()
        XCTAssertEqual(activations, 1, "asking again would come to the same thing")
        XCTAssertEqual(plays.count, 2)
    }

    func testASongLoadedButStillNotPlayingAfterTheSecondAskEndsQuietly() {
        isRunning = true
        starter.start()
        plays[0].answer(.taken)
        clock.fireOneShot()
        plays[1].answer(.taken)
        hasTrack = true
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .idle, "the popover shows the song, and its Play button plays it")
    }

    func testASongThatCameWithoutAnUpdateIsStillSeenWhenTheWaitEnds() {
        isRunning = true
        starter.start()
        plays[0].answer(.taken)
        hasTrack = true
        isPlaying = true
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .idle)
        XCTAssertEqual(plays.count, 1)
    }

    // MARK: - A play that doesn't reach Music

    func testAPlayThatDidNotReachMusicIsSentAgainAndTheSongKept() {
        // Measured 2026-11-05: twice in seven cold presses, Scripting Bridge couldn't resolve a
        // Music launched 150 ms before, and the play never went out
        starter.start()
        isRunning = true
        launches[0](4242)
        plays[0].answer(.notReady)
        XCTAssertEqual(starter.status, .starting, "the popover still says it is starting the song")
        XCTAssertEqual(store.song, MusicStarterTests.analogue, "Music never said the song wasn't there")
        XCTAssertEqual(clock.pendingOneShot?.seconds, MusicStarter.notReadyWait)
        clock.fireOneShot()
        XCTAssertEqual(plays.count, 2)
        XCTAssertEqual(plays[1].pid, 4242, "to the Music this press opened")
        plays[1].answer(.taken)
        XCTAssertEqual(clock.pendingOneShot?.seconds, MusicStarter.retryWait, "then waits for the song as usual")
        hasTrack = true
        isPlaying = true
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .idle)
    }

    func testAMusicJustOpenedCountsAsRunningBeforeTheRunningAppsListShowsIt() {
        // Measured 2026-11-05: a play that didn't reach Music came 150 ms after the launch,
        // and the list of running apps showed Music 2.5 s after it, so the press ended there
        starter.start()
        processAlive = true
        launches[0](4242)
        XCTAssertFalse(isRunning, "not listed yet")
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .starting, "an update before Music is listed doesn't end the press")
        plays[0].answer(.notReady)
        XCTAssertEqual(starter.status, .starting)
        XCTAssertEqual(clock.pendingOneShot?.seconds, MusicStarter.notReadyWait)
        clock.fireOneShot()
        XCTAssertEqual(plays.count, 2, "sent again to the Music this press opened")
        XCTAssertEqual(plays[1].pid, 4242)
    }

    func testTheMusicThisPressOpenedQuittingEndsTheStart() {
        starter.start()
        processAlive = true
        launches[0](4242)
        processAlive = false
        isRunning = true  // another Music, say, which this press didn't open
        plays[0].answer(.notReady)
        XCTAssertEqual(starter.status, .idle)
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
    }

    func testAPlayThatNeverReachesMusicGivesUpButKeepsTheSong() {
        isRunning = true
        starter.start()
        for attempt in 1...MusicStarter.notReadyTries {
            XCTAssertEqual(plays.count, attempt)
            plays[attempt - 1].answer(.notReady)
            if attempt < MusicStarter.notReadyTries {
                clock.fireOneShot()
            }
        }
        XCTAssertEqual(starter.status, .couldNotPlay)
        XCTAssertEqual(plays.count, MusicStarter.notReadyTries, "no more tries")
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
        XCTAssertEqual(store.song, MusicStarterTests.analogue)
    }

    func testAPlayThatDidNotReachAMusicThatHasQuitEndsQuietly() {
        isRunning = true
        starter.start()
        isRunning = false
        plays[0].answer(.notReady)
        XCTAssertEqual(starter.status, .idle)
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
        XCTAssertEqual(store.song, MusicStarterTests.analogue)
    }

    func testOnlyMusicSayingThereIsNoSuchTrackCountsAsTheSongGone() {
        XCTAssertEqual(MusicStarter.answer(sent: false, failed: false, code: nil), .notReady,
                       "the library couldn't be found, so the play never went out")
        XCTAssertEqual(MusicStarter.answer(sent: true, failed: false, code: nil), .taken)
        XCTAssertEqual(MusicStarter.answer(sent: true, failed: false, code: -609), .taken,
                       "an earlier event's failure isn't the play's")
        XCTAssertEqual(MusicStarter.answer(sent: true, failed: true, code: -1728), .songNotFound)
        XCTAssertEqual(MusicStarter.answer(sent: true, failed: true, code: -1719), .songNotFound)
        XCTAssertEqual(MusicStarter.answer(sent: true, failed: true, code: -609), .notReady, "connection invalid")
        XCTAssertEqual(MusicStarter.answer(sent: true, failed: true, code: -1712), .notReady, "timed out")
    }

    func testPressingAgainWhileStartingSendsNothingMore() {
        isRunning = true
        starter.start()
        starter.start()
        XCTAssertEqual(plays.count, 1)
    }

    func testPressingAgainWhileOpeningOpensMusicOnce() {
        starter.start()
        starter.start()
        XCTAssertEqual(launches.count, 1)
        XCTAssertTrue(plays.isEmpty)
    }

    func testCouldNotPlayThenMusicQuitOpensItAgainOnThePress() {
        isRunning = true
        starter.start()
        plays[0].answer(.taken)
        clock.fireOneShot()
        plays[1].answer(.taken)
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .couldNotPlay)
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

    // MARK: - Which song is remembered

    func testRemembersALibrarySongMusicIsPlaying() {
        XCTAssertEqual(LastMusicSong.remembering(isPlaying: true, libraryPersistentID: "1D48A07F86924E5C", name: "Analogue", artist: "A-Ha"),
                       MusicStarterTests.analogue)
    }

    func testDoesNotRememberASongOnlyLoadedOrNotInTheLibrary() {
        XCTAssertNil(LastMusicSong.remembering(isPlaying: false, libraryPersistentID: "1D48A07F86924E5C", name: "Analogue", artist: "A-Ha"),
                     "paused or stopped isn't listened to")
        XCTAssertNil(LastMusicSong.remembering(isPlaying: true, libraryPersistentID: nil, name: "Chain Home", artist: "Tom Rogerson"),
                     "a catalog song the user doesn't have can't be found again")
        XCTAssertNil(LastMusicSong.remembering(isPlaying: true, libraryPersistentID: "", name: "Analogue", artist: "A-Ha"))
        XCTAssertNil(LastMusicSong.remembering(isPlaying: true, libraryPersistentID: "1D48A07F86924E5C", name: nil, artist: "A-Ha"),
                     "the popover names the song before playing it")
    }

    func testTheStoreKeepsTheSongAcrossInstances() {
        let other = LastMusicSongStore(defaults: defaults)
        XCTAssertEqual(other.song, MusicStarterTests.analogue)
        let next = LastMusicSong(persistentID: "0123456789ABCDEF", name: "Some", artist: "Nils Frahm")
        other.remember(next)
        XCTAssertEqual(store.song, next)
        // Forgetting a song that isn't the one kept leaves the kept one
        store.forget(MusicStarterTests.analogue)
        XCTAssertEqual(store.song, next)
    }

    // MARK: - What the popover says

    func testEmptyStateNamesTheSongPlayWillStart() {
        let song = MusicStarterTests.analogue
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .idle, song: song).title, "Not Playing")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .idle, song: song).detail,
                       "Press play for \u{201C}Analogue\u{201D} by A-Ha.")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .opening, song: song).detail, "Opening Music…")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: true, starting: .starting, song: song).detail,
                       "Starting \u{201C}Analogue\u{201D} by A-Ha…")
        XCTAssertTrue(PopoverEmptyState.when(musicIsRunning: true, starting: .couldNotPlay, song: nil).detail.contains("choose something in Music"))
    }

    func testEmptyStateWithNoSongSaysPlayOpensMusic() {
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .idle, song: nil).detail, "Press play to open Music.")
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: true, starting: .idle, song: nil).detail, "Press play to choose something in Music.")
    }

    func testCouldNotPlayIsForgottenOnceMusicQuits() {
        XCTAssertEqual(PopoverEmptyState.when(musicIsRunning: false, starting: .couldNotPlay, song: nil),
                       PopoverEmptyState.when(musicIsRunning: false, starting: .idle, song: nil),
                       "a press opens Music again, so say that")
    }

    func testThePlaceholderKeepsTheLastTwoWordsTogether() {
        XCTAssertEqual(PlayerPlaceholderView.keepingLastWordsTogether("Press play for \u{201C}Veridis Quo\u{201D} by Daft Punk."),
                       "Press play for \u{201C}Veridis Quo\u{201D} by Daft\u{00A0}Punk.")
        XCTAssertEqual(PlayerPlaceholderView.keepingLastWordsTogether("Alone"), "Alone")
        XCTAssertEqual(PlayerPlaceholderView.keepingLastWordsTogether(""), "")
    }

    func testDisplayNameUsesTypographicMarks() {
        let song = LastMusicSong(persistentID: "0123456789ABCDEF", name: "Don't Stop", artist: nil)
        XCTAssertEqual(song.displayName, "\u{201C}Don\u{2019}t Stop\u{201D}")
    }

}
