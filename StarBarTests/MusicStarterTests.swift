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
    private var hasTrack = false
    private var launches: [(pid_t?) -> Void] = []
    private var plays: [(pid: pid_t?, song: LastMusicSong, answer: (Bool) -> Void)] = []
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
        hasTrack = false
        launches = []
        plays = []
        activations = 0
        starter = MusicStarter(
            isRunning: { [unowned self] in self.isRunning },
            hasTrack: { [unowned self] in self.hasTrack },
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
        plays[0].answer(true)
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
        plays[0].answer(true)
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
    }

    func testARefusedSongIsForgottenAndTheNextPressBringsMusicForward() {
        isRunning = true
        starter.start()
        plays[0].answer(false)
        XCTAssertEqual(starter.status, .couldNotPlay)
        XCTAssertNil(store.song, "a song Music won't play, likely deleted, isn't offered again")

        starter.start()
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(plays.count, 1)
        XCTAssertEqual(starter.status, .idle)
    }

    func testNoSongAfterMusicAnswersMeansItCouldNotPlay() {
        isRunning = true
        starter.start()
        XCTAssertTrue(clock.pendingOneShots.isEmpty, "the wait starts when Music answers, not when asked")
        plays[0].answer(true)
        XCTAssertEqual(clock.pendingOneShot?.seconds, MusicStarter.songWait)
        // An update with no song in it changes nothing
        center.post(name: .iTunesPlayerDidUpdated, object: nil)
        XCTAssertEqual(starter.status, .starting)
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .couldNotPlay)
        XCTAssertEqual(store.song, MusicStarterTests.analogue, "Music took it, so it is still in the library")

        starter.start()
        XCTAssertEqual(activations, 1, "asking again would come to the same thing")
        XCTAssertEqual(plays.count, 1)
    }

    func testASongThatCameWithoutAnUpdateIsStillSeenWhenTheWaitEnds() {
        isRunning = true
        starter.start()
        plays[0].answer(true)
        hasTrack = true
        clock.fireOneShot()
        XCTAssertEqual(starter.status, .idle)
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
        plays[0].answer(true)
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

    func testDisplayNameUsesTypographicMarks() {
        let song = LastMusicSong(persistentID: "0123456789ABCDEF", name: "Don't Stop", artist: nil)
        XCTAssertEqual(song.displayName, "\u{201C}Don\u{2019}t Stop\u{201D}")
    }

}
