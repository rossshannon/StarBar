//
//  LastfmScrobblerTests.swift
//  StarBarTests
//
//  What the scrobbler sends to Last.fm, and when: driven with a fake account, sender, queue
//  store, players and clock, never `start()`ed, so nothing reaches Music, Spotify, the disk
//  or the network.
//

import XCTest
@testable import StarBar

final class LastfmScrobblerTests: XCTestCase {

    /// A `FakeClock` with the uptime beside it, which knows when each of its timers is due,
    /// so `run(for:)` passes time and fires every timer in the order they fall due, as the
    /// run loop would
    private final class TestClock: RatingReminderClock {

        private struct Due {
            let at: TimeInterval
            let timer: FakeClock.FakeTimer
        }

        let fake = FakeClock()
        /// What `ProcessInfo.systemUptime` would say. Starts well away from zero, so a
        /// deadline mistaken for a delay is caught.
        private(set) var uptime: TimeInterval = LastfmScrobblerTests.startUptime
        private var due: [Due] = []

        func now() -> Date {
            return fake.now()
        }

        func schedule(after seconds: TimeInterval, repeats: Bool, action: @escaping () -> Void) -> RatingReminderTimer {
            let timer = fake.schedule(after: seconds, repeats: repeats, action: action)
            if let fakeTimer = timer as? FakeClock.FakeTimer {
                due.append(Due(at: uptime + seconds, timer: fakeTimer))
            }
            return timer
        }

        /// How long each one-shot timer still waiting was set for
        var pendingDelays: [TimeInterval] {
            return fake.pendingOneShots.map { $0.seconds }
        }

        func run(for seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
            let end = uptime + seconds
            var fired = 0
            while let next = due.filter({ $0.timer.isValid && !$0.timer.repeats }).min(by: { $0.at < $1.at }),
                  next.at <= end + 1e-9 {
                fired += 1
                guard fired < 100_000 else { return XCTFail("timers keep re-arming for no time", file: file, line: line) }
                let step = max(0, next.at - uptime)
                uptime += step
                fake.advance(by: step)
                next.timer.invalidate()
                next.timer.action()
            }
            let rest = end - uptime
            if rest > 0 {
                uptime = end
                fake.advance(by: rest)
            }
        }
    }

    fileprivate static let startUptime: TimeInterval = 1000

    private var clock: TestClock!
    private var store: MemoryScrobbleQueueStore!
    private var sender: FakeLastfmSender!
    private var account: FakeLastfmAccount!
    private var settings = LastfmScrobbler.Settings(scrobblesSpotify: false, lovesFavorites: true, isDryRun: false, isPaused: false)
    private var reports: [PlayerKind: PlayerReport] = [:]
    /// The players the scrobbler asked about, in order
    private var observed: [PlayerKind] = []
    /// The identities `.checkPosition` reads were made for
    private var positionReads: [String] = []
    private var reading = PlayTracker.PositionReading.unanswered
    private var favorite: Bool?
    private var favoriteAsks = 0
    private var moving = false
    private var scrobbler: LastfmScrobbler!

    private let song = PlayTracker.Song.test()

    override func setUp() {
        super.setUp()
        clock = TestClock()
        store = MemoryScrobbleQueueStore()
        sender = FakeLastfmSender()
        account = FakeLastfmAccount(username: "alice", sender: sender)
        settings = LastfmScrobbler.Settings(scrobblesSpotify: false, lovesFavorites: true, isDryRun: false, isPaused: false)
        reports = [:]
        observed = []
        positionReads = []
        reading = .unanswered
        favorite = nil
        favoriteAsks = 0
        moving = false
        scrobbler = nil
    }

    override func tearDown() {
        scrobbler = nil
        clock = nil
        store = nil
        sender = nil
        account = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeScrobbler() -> LastfmScrobbler {
        let environment = LastfmScrobbler.Environment(
            account: account,
            queueStore: store,
            clock: clock,
            uptime: { [unowned self] in self.clock.uptime },
            settings: { [unowned self] in self.settings },
            observe: { [unowned self] kind in
                self.observed.append(kind)
                return self.reports[kind] ?? .gone
            },
            readPosition: { [unowned self] identity in
                self.positionReads.append(identity)
                return self.reading
            },
            isMoving: { [unowned self] in self.moving },
            isFavorited: { [unowned self] _, _ in
                self.favoriteAsks += 1
                return self.favorite
            })
        scrobbler = LastfmScrobbler(environment: environment)
        return scrobbler
    }

    /// The wall-clock time at a given uptime: the fake clock starts at the reference date
    /// when the uptime is `startUptime`
    private func date(at uptime: TimeInterval) -> Date {
        return Date(timeIntervalSinceReferenceDate: uptime - LastfmScrobblerTests.startUptime)
    }

    private func play(_ song: PlayTracker.Song, in kind: PlayerKind = .music) {
        reports[kind] = .observed(PlayerObservation(state: .playing, song: song))
        scrobbler.playerDidUpdate(kind)
    }

    /// Puts `count` scrobbles in the store for `user`, oldest first, and returns them
    @discardableResult
    private func waiting(_ count: Int, user: String = "alice") -> [Scrobble] {
        let now = clock.now()
        let scrobbles = (0..<count).map { index in
            Scrobble(track: .test("Song \(index)"), startedAt: now.addingTimeInterval(-Double(count - index) * 300), source: "music")
        }
        var contents = store.contents[user] ?? ScrobbleQueue.Contents()
        contents.scrobbles = scrobbles
        store.contents[user] = contents
        return scrobbles
    }

    /// Signs alice in after the scrobbler was made with nobody, as the account would
    private func connect(_ user: String = "alice", sender: FakeLastfmSender? = nil) {
        account.username = user
        account.sender = sender ?? self.sender
        scrobbler.accountDidChange()
    }

    private func storedScrobbles(_ user: String = "alice") -> [Scrobble] {
        return store.contents[user]?.scrobbles ?? []
    }

    // MARK: - Signed in or not

    func testNothingIsTrackedOrSentWhenNotSignedIn() {
        account = FakeLastfmAccount(username: nil, sender: sender)
        makeScrobbler()
        play(song)
        clock.run(for: 300)
        XCTAssertFalse(scrobbler.isActive, "nobody is signed in, so nothing should be tracked")
        XCTAssertTrue(observed.isEmpty, "a player was read with nobody signed in")
        XCTAssertTrue(sender.calls.isEmpty, "something was sent with nobody signed in")
        XCTAssertEqual(store.saves, 0, "something was queued with nobody signed in")
    }

    func testAPlayIsAnnouncedAfterTwoSecondsAndScrobbledHalfway() {
        makeScrobbler()
        play(song)
        clock.run(for: 1.9)
        XCTAssertTrue(sender.nowPlayingCalls.isEmpty, "now playing went before the song had played 2 s")
        clock.run(for: 0.2)
        XCTAssertEqual(sender.nowPlayingCalls, [song.track], "now playing should go 2 s into the song")

        let successesBefore = account.successes
        clock.run(for: 117.8)
        XCTAssertTrue(sender.scrobbleCalls.isEmpty, "a 240 s song scrobbled before 120 s")
        clock.run(for: 0.2)
        XCTAssertEqual(sender.scrobbleCalls, [[Scrobble(track: song.track, startedAt: date(at: 1000), source: "music")]],
                       "one scrobble with the song, the time it started and its player should go at 120 s")
        XCTAssertTrue(storedScrobbles().isEmpty, "the scrobble Last.fm answered for is still waiting")
        XCTAssertEqual(scrobbler.waitingCount, 0, "waitingCount should be 0 once Last.fm answered")
        XCTAssertGreaterThan(account.successes, successesBefore, "the account wasn't told of the success")
    }

    // MARK: - Failures

    func testANetworkFailureKeepsTheScrobbleAndRetriesAfterAMinute() {
        waiting(1)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = [.failure(.network)]
        connect()
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "a new sign-in should send what is waiting")
        XCTAssertEqual(storedScrobbles().count, 1, "a scrobble that failed to send was dropped")
        XCTAssertEqual(account.failures, [.network], "the failure wasn't passed to the account")
        XCTAssertEqual(clock.pendingDelays, [60], "the first retry should wait 60 s")

        clock.run(for: 59.9)
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "retried before the minute was up")
        clock.run(for: 0.2)
        XCTAssertEqual(sender.scrobbleCalls.count, 2, "the retry didn't send")
        XCTAssertTrue(storedScrobbles().isEmpty, "the retried scrobble is still waiting after it went")
    }

    func testRetriesStepThroughTheDelaysAndStayOnTheLast() {
        waiting(1)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = Array(repeating: .failure(.network), count: 5)
        connect()
        var delays: [TimeInterval] = []
        for _ in 0..<5 {
            guard let delay = clock.pendingDelays.first else { return XCTFail("no retry was scheduled") }
            delays.append(delay)
            clock.run(for: delay)
        }
        XCTAssertEqual(delays, [60, 300, 900, 3600, 3600], "retries should follow retryDelays and repeat the last")
        XCTAssertEqual(sender.scrobbleCalls.count, 6, "five failures and one success should be six sends")
        XCTAssertTrue(storedScrobbles().isEmpty, "the scrobble is still waiting after it was accepted")
        XCTAssertTrue(clock.pendingDelays.isEmpty, "a retry is still scheduled after a success")
    }

    func testATemporaryFailureRetriesLikeANetworkOne() {
        waiting(1)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = [.failure(.temporary(16))]
        connect()
        XCTAssertEqual(storedScrobbles().count, 1, "a scrobble Last.fm was too busy for was dropped")
        XCTAssertEqual(clock.pendingDelays, [60], "a temporary failure should retry after 60 s")
        clock.run(for: 60)
        XCTAssertEqual(sender.scrobbleCalls.count, 2, "the retry didn't send")
    }

    func testARefusedBatchIsDroppedAndSendingCarriesOn() {
        let scrobbles = waiting(60)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = [.failure(.refused(6))]
        connect()
        XCTAssertEqual(sender.scrobbleCalls.map { $0.count }, [50, 10], "the refused batch should be dropped and the rest sent")
        XCTAssertEqual(sender.scrobbleCalls.last ?? [], Array(scrobbles[50...]), "the second batch should be the ten after the refused fifty")
        XCTAssertTrue(storedScrobbles().isEmpty, "a refused batch is still waiting")
        XCTAssertEqual(account.failures, [.refused(6)], "the refusal wasn't passed to the account")
    }

    func testARejectedSessionKeepsTheQueueAndSendsNothingMore() {
        waiting(60)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = [.failure(.sessionInvalid)]
        connect()
        XCTAssertEqual(account.rejections, 1, "the account wasn't told its session was rejected")
        XCTAssertEqual(storedScrobbles().count, 60, "a rejected session lost what was waiting")
        scrobbler.flush()
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "something more was sent after the session was rejected")
    }

    func testARejectedKeyBlocksSendingUntilAnotherUserSignsIn() {
        waiting(1)
        waiting(1, user: "bob")
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = [.failure(.credentialsRejected(10))]
        connect()
        XCTAssertEqual(account.failures, [.credentialsRejected(10)], "the rejected key wasn't passed to the account")
        scrobbler.flush()
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "sending went on after Last.fm refused the key")
        XCTAssertEqual(storedScrobbles().count, 1, "a scrobble was dropped because the key was refused")

        let bobsSender = FakeLastfmSender()
        connect("bob", sender: bobsSender)
        XCTAssertEqual(bobsSender.scrobbleCalls.count, 1, "another user's sign-in should lift the block")
        XCTAssertTrue(storedScrobbles("bob").isEmpty, "bob's scrobble wasn't sent")
    }

    // MARK: - Batches

    func testWaitingScrobblesGoInBatchesOfFiftyOldestFirstOneAtATime() {
        let scrobbles = waiting(120)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.answersAtOnce = false
        connect()
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "the first batch should go on sign-in")
        scrobbler.flush()
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "a second request went while the first was out")
        sender.answerPending()
        XCTAssertEqual(sender.scrobbleCalls.count, 2, "the second batch should go once the first is answered")
        sender.answerPending()
        sender.answerPending()
        XCTAssertEqual(sender.pendingCount, 0, "a request is still out after three answers")
        XCTAssertEqual(sender.scrobbleCalls.map { $0.count }, [50, 50, 20], "120 scrobbles should go as 50, 50 and 20")
        XCTAssertEqual(sender.scrobbleCalls.flatMap { $0 }, scrobbles, "scrobbles should go oldest first, each once")
        XCTAssertTrue(storedScrobbles().isEmpty, "scrobbles are still waiting after every batch was answered")
    }

    // MARK: - Hearts set in StarBar

    func testAHeartIsSentAfterTheScrobbles() {
        waiting(1)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.answersAtOnce = false
        connect()
        scrobbler.userDidSetHeart(true, title: "Title", artist: "Artist")
        XCTAssertEqual(sender.calls.count, 1, "the love went while a scrobble was out")
        sender.answerPending()
        XCTAssertEqual(sender.calls.last, .love(title: "Title", artist: "Artist", loved: true), "the love should follow the scrobble")
        sender.answerPending()
        XCTAssertEqual(scrobbler.waitingCount, 0, "the love is still waiting after Last.fm answered")
    }

    func testAHeartSetAndClearedBeforeSendingSendsOnlyTheUnlove() {
        waiting(1)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.answersAtOnce = false
        connect()
        scrobbler.userDidSetHeart(true, title: "Title", artist: "Artist")
        scrobbler.userDidSetHeart(false, title: "Title", artist: "Artist")
        sender.answerPending()
        sender.answerPending()
        XCTAssertEqual(sender.loveCalls, [.love(title: "Title", artist: "Artist", loved: false)], "only where the heart ended up should be sent")
    }

    func testAHeartIsNotKeptWithTheSettingOff() {
        settings.lovesFavorites = false
        makeScrobbler()
        scrobbler.userDidSetHeart(true, title: "Title", artist: "Artist")
        XCTAssertEqual(scrobbler.waitingCount, 0, "a heart was kept with loving switched off")
        XCTAssertTrue(sender.loveCalls.isEmpty, "a love was sent with loving switched off")
    }

    func testAHeartIsNotKeptWhenNotSignedIn() {
        account = FakeLastfmAccount(username: nil, sender: sender)
        makeScrobbler()
        scrobbler.userDidSetHeart(true, title: "Title", artist: "Artist")
        XCTAssertEqual(scrobbler.waitingCount, 0, "a heart was kept with nobody signed in")
        XCTAssertTrue(sender.calls.isEmpty, "a love was sent with nobody signed in")
    }

    func testAHeartIsNotKeptWhilePaused() {
        settings.isPaused = true
        makeScrobbler()
        scrobbler.userDidSetHeart(true, title: "Title", artist: "Artist")
        XCTAssertEqual(scrobbler.waitingCount, 0, "a heart was kept while paused")
        XCTAssertTrue(sender.calls.isEmpty, "a love was sent while paused")
    }

    func testAHeartForASongWithNoTitleIsIgnored() {
        makeScrobbler()
        scrobbler.userDidSetHeart(true, title: "  ", artist: "Artist")
        scrobbler.userDidSetHeart(true, title: "Title", artist: nil)
        XCTAssertEqual(scrobbler.waitingCount, 0, "a heart with no title or no artist was kept")
        XCTAssertTrue(sender.calls.isEmpty, "a heart with no title or no artist was sent")
    }

    // MARK: - Favourites as they scrobble

    func testAFavouriteIsLovedAsItScrobbles() {
        favorite = true
        makeScrobbler()
        play(song)
        clock.run(for: 121)
        XCTAssertEqual(sender.loveCalls, [.love(title: "Song", artist: "Artist", loved: true)], "a favourite wasn't loved as it scrobbled")
        let scrobbleIndex = sender.calls.firstIndex { if case .scrobble = $0 { return true } else { return false } }
        let loveIndex = sender.calls.firstIndex { if case .love = $0 { return true } else { return false } }
        XCTAssertNotNil(scrobbleIndex, "the favourite didn't scrobble")
        XCTAssertLessThan(scrobbleIndex ?? .max, loveIndex ?? .max, "the love should go after the scrobble")
    }

    func testAFavouritePlayedTwiceIsLovedOnce() {
        favorite = true
        makeScrobbler()
        play(song)
        clock.run(for: 121)
        scrobbler.songRestarted(.music)
        clock.run(for: 125)
        XCTAssertEqual(sender.scrobbleCalls.count, 2, "the song should have scrobbled twice")
        XCTAssertEqual(sender.loveCalls.count, 1, "a favourite played twice was loved twice")
    }

    func testASongWhoseHeartIsUnknownIsNotLoved() {
        favorite = nil
        makeScrobbler()
        play(song)
        clock.run(for: 121)
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "the song didn't scrobble")
        XCTAssertTrue(sender.loveCalls.isEmpty, "a song whose heart wasn't known was loved")
    }

    func testASongWhoseHeartIsClearIsNotLoved() {
        favorite = false
        makeScrobbler()
        play(song)
        clock.run(for: 121)
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "the song didn't scrobble")
        XCTAssertTrue(sender.loveCalls.isEmpty, "a song whose heart is clear was loved")
    }

    func testAFavouriteIsNotLovedWithTheSettingOff() {
        settings.lovesFavorites = false
        favorite = true
        makeScrobbler()
        play(song)
        clock.run(for: 121)
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "the song didn't scrobble")
        XCTAssertTrue(sender.loveCalls.isEmpty, "a favourite was loved with loving switched off")
    }

    // MARK: - Spotify

    func testSpotifyIsIgnoredWithTheSettingOff() {
        makeScrobbler()
        play(.test("Spotify Song"), in: .spotify)
        clock.run(for: 300)
        XCTAssertFalse(observed.contains(.spotify), "Spotify was read with its scrobbling off")
        XCTAssertTrue(sender.calls.isEmpty, "a Spotify song was sent with its scrobbling off")
    }

    func testSpotifyIsScrobbledWhenOn() {
        settings.scrobblesSpotify = true
        makeScrobbler()
        play(.test("Spotify Song"), in: .spotify)
        clock.run(for: 121)
        XCTAssertEqual(sender.scrobbleCalls.first?.first?.track.title, "Spotify Song", "the Spotify song didn't scrobble")
        XCTAssertEqual(sender.scrobbleCalls.first?.first?.source, "spotify", "a Spotify scrobble should say it came from Spotify")
    }

    func testTurningSpotifyOffForgetsItsPlay() {
        settings.scrobblesSpotify = true
        makeScrobbler()
        play(.test("Spotify Song"), in: .spotify)
        clock.run(for: 60)
        settings.scrobblesSpotify = false
        scrobbler.settingsDidChange()
        clock.run(for: 300)
        XCTAssertTrue(sender.scrobbleCalls.isEmpty, "a Spotify play went on counting after Spotify scrobbling was switched off")
    }

    // MARK: - Pause

    func testPausingForgetsThePlay() {
        makeScrobbler()
        play(song)
        clock.run(for: 60)
        settings.isPaused = true
        scrobbler.settingsDidChange()
        XCTAssertFalse(scrobbler.isActive, "pausing should stop tracking")
        clock.run(for: 300)
        XCTAssertTrue(sender.scrobbleCalls.isEmpty, "a play went on counting after scrobbling was paused")
        XCTAssertTrue(storedScrobbles().isEmpty, "a play was queued while paused")
    }

    func testWhatWasWaitingIsStillSentWhilePaused() {
        waiting(1)
        settings.isPaused = true
        makeScrobbler()
        scrobbler.flush()
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "what was waiting should still go while paused")
    }

    func testUnpausingReadsThePlayersAndCountsFromThen() {
        settings.isPaused = true
        makeScrobbler()
        reports[.music] = .observed(PlayerObservation(state: .playing, song: song))
        clock.run(for: 100)
        XCTAssertTrue(observed.isEmpty, "a player was read while paused")
        settings.isPaused = false
        scrobbler.settingsDidChange()
        XCTAssertEqual(observed, [.music], "un-pausing should read Music at once")
        clock.run(for: 119.9)
        XCTAssertTrue(sender.scrobbleCalls.isEmpty, "time before un-pausing counted towards the play")
        clock.run(for: 0.2)
        XCTAssertEqual(sender.scrobbleCalls.first?.first?.startedAt, date(at: 1100), "the play should start when scrobbling resumed")
    }

    func testPausingTellsPreferences() {
        makeScrobbler()
        let posted = expectation(forNotification: .lastfmScrobblerDidChange, object: nil)
        settings.isPaused = true
        scrobbler.settingsDidChange()
        wait(for: [posted], timeout: 0.1)
    }

    // MARK: - Dry run

    func testADryRunSendsNothingToTheAccountAndEmptiesItsQueue() {
        account = FakeLastfmAccount(username: nil, sender: sender)
        settings.isDryRun = true
        makeScrobbler()
        XCTAssertTrue(scrobbler.isActive, "a dry run should track with nobody signed in")
        play(song)
        clock.run(for: 121)
        XCTAssertEqual(store.contents[LastfmScrobbler.dryRunUser]?.lastScrobbled["music"]?.identity, song.identity,
                       "the dry run's play wasn't queued under the dry-run user")
        let answered = expectation(description: "the dry run answers on the next turn of the run loop")
        DispatchQueue.main.async { answered.fulfill() }
        wait(for: [answered], timeout: 1)
        XCTAssertEqual(scrobbler.waitingCount, 0, "the dry run's answer didn't empty the queue")
        XCTAssertTrue(storedScrobbles(LastfmScrobbler.dryRunUser).isEmpty, "the dry run left its scrobble on disk")
        XCTAssertTrue(sender.calls.isEmpty, "a dry run reached the account's sender")
    }

    // MARK: - What the player said

    func testAPlayerThatHasGoneForgetsThePlay() {
        makeScrobbler()
        play(song)
        clock.run(for: 60)
        reports[.music] = .gone
        scrobbler.playerDidUpdate(.music)
        clock.run(for: 300)
        XCTAssertTrue(sender.scrobbleCalls.isEmpty, "a play went on counting after its player quit")
    }

    func testNothingNewChangesNothing() {
        makeScrobbler()
        play(song)
        clock.run(for: 60)
        reports[.music] = .nothingNew
        scrobbler.playerDidUpdate(.music)
        clock.run(for: 61)
        XCTAssertEqual(sender.scrobbleCalls, [[Scrobble(track: song.track, startedAt: date(at: 1000), source: "music")]],
                       "an update that said nothing changed the play")
    }

    // MARK: - Rollover and restarts

    func testARolloverIsReadOnceAndTheRepeatScrobbles() {
        reading = PlayTracker.PositionReading(position: 3, isPlaying: true, isSameSong: true)
        makeScrobbler()
        play(song)
        clock.run(for: 242.9)
        XCTAssertTrue(positionReads.isEmpty, "the position was read before the song could have ended")
        clock.run(for: 0.2)
        XCTAssertEqual(positionReads, [song.identity], "the position should be read once, 3 s past the song's end")
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "the first pass should have scrobbled")
        clock.run(for: 116.8)
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "the repeat scrobbled too soon")
        clock.run(for: 0.2)
        XCTAssertEqual(sender.scrobbleCalls.count, 2, "the repeat found by the read didn't scrobble")
        XCTAssertEqual(sender.scrobbleCalls.last?.first?.startedAt, date(at: 1240), "the repeat should start where the read put it")
        XCTAssertEqual(positionReads.count, 1, "the position was read more than once")
    }

    func testThePositionReadWaitsWhileSomethingMoves() {
        moving = true
        makeScrobbler()
        play(song)
        clock.run(for: 243)
        clock.run(for: 0.5)
        XCTAssertTrue(positionReads.isEmpty, "Music was read while something moved on screen")
        moving = false
        clock.run(for: 0.15)
        XCTAssertEqual(positionReads, [song.identity], "the read should happen once the screen is still")
    }

    func testThePositionReadWaitsNoLongerThanTheLimit() {
        moving = true
        makeScrobbler()
        play(song)
        clock.run(for: 243)
        clock.run(for: LastfmScrobbler.motionWaitLimit - 0.15)
        XCTAssertTrue(positionReads.isEmpty, "the read gave up waiting too soon")
        clock.run(for: 0.3)
        XCTAssertEqual(positionReads, [song.identity], "the read should happen after motionWaitLimit even while moving")
    }

    func testARestartAfterAScrobbleAllowsAnother() {
        makeScrobbler()
        play(song)
        clock.run(for: 121)
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "the first pass didn't scrobble")
        scrobbler.songRestarted(.music)
        clock.run(for: 121)
        XCTAssertEqual(sender.scrobbleCalls.count, 2, "a restarted song didn't scrobble again")
    }

    // MARK: - The account

    func testDisconnectingDeletesThatUsersQueue() {
        waiting(3)
        makeScrobbler()
        account.username = nil
        account.sender = nil
        scrobbler.accountDidChange(disconnected: "alice")
        XCTAssertTrue(store.deletes.contains("alice"), "a user who disconnected kept their queue on disk")
        XCTAssertNil(store.contents["alice"], "a user who disconnected left scrobbles in the store")
        XCTAssertEqual(scrobbler.waitingCount, 0, "something is waiting with nobody signed in")
    }

    func testARejectedSessionKeepsTheQueueForWhenTheUserComesBack() {
        waiting(2)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = [.failure(.sessionInvalid)]
        connect()
        scrobbler.accountDidChange()
        XCTAssertTrue(store.deletes.isEmpty, "a rejected session deleted the user's queue")
        XCTAssertEqual(storedScrobbles().count, 2, "a rejected session lost what was waiting")

        let newSender = FakeLastfmSender()
        connect(sender: newSender)
        XCTAssertEqual(newSender.scrobbleCalls.map { $0.count }, [2], "what was waiting should go when the user connects again")
    }

    func testARelaunchDoesNotScrobbleThePlayStillGoingAgain() {
        var contents = ScrobbleQueue.Contents()
        contents.lastScrobbled["music"] = PlayTracker.Earlier(identity: song.identity, startedAt: date(at: 1000 - 130), duration: 240)
        store.contents["alice"] = contents
        makeScrobbler()
        play(song)
        clock.run(for: 240)
        XCTAssertTrue(sender.scrobbleCalls.isEmpty, "the pass scrobbled before the relaunch was scrobbled again")
    }

    func testAnUnchangedAccountNeitherSendsNorReadsThePlayers() {
        waiting(1)
        account = FakeLastfmAccount()
        makeScrobbler()
        sender.scrobbleAnswers = [.failure(.network)]
        connect()
        let reads = observed.count
        // A flush would forget the retry wait and send again at once
        scrobbler.accountDidChange()
        scrobbler.settingsDidChange()
        XCTAssertEqual(sender.scrobbleCalls.count, 1, "an account change that changed nothing sent again")
        XCTAssertEqual(observed.count, reads, "an account change that changed nothing read the players")
        XCTAssertEqual(clock.pendingDelays, [60], "an account change that changed nothing forgot the retry wait")
    }

    func testPreparingToQuitSynchronisesTheStore() {
        makeScrobbler()
        scrobbler.prepareToQuit()
        XCTAssertEqual(store.synchronizes, 1, "the store wasn't told to finish writing before the quit")
    }

}
