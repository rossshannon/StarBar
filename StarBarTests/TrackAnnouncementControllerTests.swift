//
//  TrackAnnouncementControllerTests.swift
//  StarBarTests
//
//  When the announcement strip shows, replaces itself and hides. Drives the controller with a
//  fake player, artwork loader, presenter and clock, so no Music is needed.
//

import XCTest
@testable import StarBar

final class TrackAnnouncementControllerTests: XCTestCase {

    private typealias Snapshot = TrackAnnouncementController.PlayerSnapshot

    private var presenter: FakePresenter!
    private var clock: FakeClock!
    private var player: Snapshot?
    private var playerReads = 0
    private var live: TrackAnnouncementController.LiveTrackLoad = .loaded(.init())
    private var liveQueue: [TrackAnnouncementController.LiveTrackLoad] = []
    private var artworkRequests: [String] = []
    private var wantsArtworkFlags: [Bool] = []
    private var reduceMotion = false
    private var reduceTransparency = false
    /// What Music answers when asked which track it is playing; nil when it can't say
    private var musicsCurrentIdentity: String?
    /// The identities the controller asked Music to match against
    private var identityReadsFor: [String] = []
    private var identityReads = 0
    /// Player positions Music will answer with, in order; nil stands for a failed read
    private var positions: [TimeInterval?] = []
    private var positionReads = 0
    private var controller: TrackAnnouncementController!

    override func setUp() {
        super.setUp()
        presenter = FakePresenter()
        clock = FakeClock()
        player = nil
        playerReads = 0
        live = .loaded(.init())
        artworkRequests = []
        wantsArtworkFlags = []
        reduceMotion = false
        reduceTransparency = false
        musicsCurrentIdentity = nil
        identityReadsFor = []
        identityReads = 0
        positions = []
        positionReads = 0
        controller = makeController(enabled: true)
    }

    override func tearDown() {
        controller = nil
        clock = nil
        presenter = nil
        super.tearDown()
    }

    private func makeController(enabled: Bool) -> TrackAnnouncementController {
        return TrackAnnouncementController(
            readPlayer: { [unowned self] in
                self.playerReads += 1
                return self.player
            },
            loadLiveTrack: { [unowned self] identity, wantsArtwork in
                self.artworkRequests.append(identity)
                self.wantsArtworkFlags.append(wantsArtwork)
                // A queued result, when a test wants the loads to differ, else the same one
                return self.liveQueue.isEmpty ? self.live : self.liveQueue.removeFirst()
            },
            readCurrentIdentity: { [unowned self] announced in
                self.identityReads += 1
                self.identityReadsFor.append(announced)
                return self.musicsCurrentIdentity
            },
            readPosition: { [unowned self] in
                self.positionReads += 1
                return self.positions.isEmpty ? nil : self.positions.removeFirst()
            },
            presenter: presenter,
            clock: clock,
            accessibility: { [unowned self] in (self.reduceMotion, self.reduceTransparency) },
            isEnabled: enabled
        )
    }

    private func snapshot(track: String? = "A", state: Snapshot.State = .playing, title: String? = nil, hasArtwork: Bool = true) -> Snapshot {
        return Snapshot(
            identity: track,
            state: state,
            title: title ?? (track.map { "Song \($0)" } ?? ""),
            artist: "Artist",
            album: "Album",
            hasArtwork: hasArtwork
        )
    }

    /// Set the fake player and tell the controller it changed
    private func update(_ snapshot: Snapshot?, seedOnly: Bool = false) {
        player = snapshot
        controller.playerDidUpdate(seedOnly: seedOnly)
    }

    private let expectedHold = TrackAnnouncementLayout.holdDuration + TrackAnnouncementLayout.slideDuration

    /// The position watch, if it is running
    private var positionWatch: FakeClock.FakeTimer? {
        return clock.timers.last { $0.isValid && $0.repeats }
    }

    /// Read the position once, as the watch's timer would, with Music answering `position`
    private func poll(_ position: TimeInterval?) {
        guard let watch = positionWatch else { return XCTFail("the position watch is not running") }
        positions = [position]
        watch.action()
    }

    // MARK: - New track detection

    func testFirstPlayingTrackIsAnnouncedWithAHoldTimer() {
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
        XCTAssertEqual(clock.pendingOneShot?.seconds, expectedHold)
    }

    func testSeedingRecordsTheTrackWithoutAnnouncing() {
        update(snapshot(track: "A"), seedOnly: true)
        XCTAssertTrue(presenter.shown.isEmpty)

        update(snapshot(track: "A"))
        XCTAssertTrue(presenter.shown.isEmpty, "the seeded track must not announce on its next update")
    }

    func testMetadataRefreshOfTheSameTrackDoesNotAnnounceAgain() {
        update(snapshot(track: "A"))
        let timer = clock.pendingOneShot

        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertTrue(clock.pendingOneShot === timer)
    }

    func testPauseAndResumeDoNotAnnounce() {
        update(snapshot(track: "A"))
        update(snapshot(track: "A", state: .paused))
        update(snapshot(track: "A", state: .playing))

        XCTAssertEqual(presenter.shown.count, 1)
    }

    func testSkippingToATrackWhilePausedAnnouncesItWhenItPlays() {
        update(snapshot(track: "A"))
        update(snapshot(track: "A", state: .paused))
        update(snapshot(track: "B", state: .paused))
        XCTAssertEqual(presenter.shown.count, 1)

        update(snapshot(track: "B", state: .playing))
        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song B"])
    }

    func testSeededPausedTrackDoesNotAnnounceOnPlay() {
        update(snapshot(track: "A", state: .paused), seedOnly: true)
        update(snapshot(track: "A", state: .playing))

        XCTAssertTrue(presenter.shown.isEmpty)
    }

    func testIsPersistentIDRecognisesHexIdentities() {
        XCTAssertTrue(Snapshot.isPersistentID("00000000000000FF"))
        XCTAssertFalse(Snapshot.isPersistentID("Live|Radio|"))
        XCTAssertFalse(Snapshot.isPersistentID("FF"))
    }

    func testATrackThatStartsPausedAnnouncesWhenItPlays() {
        update(snapshot(track: "A", state: .paused))
        XCTAssertTrue(presenter.shown.isEmpty)

        update(snapshot(track: "A", state: .playing))
        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
    }

    func testNewTrackReplacesTheStripAndRestartsTheTimer() {
        update(snapshot(track: "A"))
        let first = try! XCTUnwrap(clock.pendingOneShot)

        update(snapshot(track: "B"))

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song B"])
        XCTAssertFalse(first.isValid)
        XCTAssertEqual(clock.pendingOneShots.count, 1)
        XCTAssertEqual(presenter.hideCount, 0)
    }

    func testRapidSkipHidesOnceAfterTheLastTrack() {
        update(snapshot(track: "A"))
        clock.advance(by: 1)
        update(snapshot(track: "B"))

        clock.fireOneShot()

        XCTAssertEqual(presenter.hideCount, 1)
        XCTAssertEqual(presenter.shown.last?.title, "Song B")
        XCTAssertNil(clock.pendingOneShot)
    }

    func testHideTimerHidesAndTheTrackStaysKnown() {
        update(snapshot(track: "A"))
        clock.fireOneShot()

        XCTAssertEqual(presenter.hideCount, 1)
        update(snapshot(track: "A"))
        XCTAssertEqual(presenter.shown.count, 1)
    }

    // MARK: - Restarts

    /// Music sends no notification when a song restarts (measured 2026-09-23: neither
    /// playerInfo nor MediaRemote said anything for ⏮ at 1:30), so the position is watched
    func testRestartingTheSongAnnouncesItAgain() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "A"
        poll(120)
        poll(1.5)

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song A"])
    }

    func testTheWatchReadsEveryTwoSeconds() {
        update(snapshot(track: "A"))
        XCTAssertEqual(positionWatch?.seconds, TrackAnnouncementController.restartCheckInterval)
        XCTAssertEqual(TrackAnnouncementController.restartCheckInterval, 2)
    }

    func testPlayingOnDoesNotAnnounce() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "A"
        poll(120)
        poll(122)
        poll(124)

        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertEqual(identityReads, 0, "only a suspected restart asks Music which song it is")
    }

    func testARestartIsNotAnnouncedTwice() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "A"
        poll(120)
        poll(0.5)
        poll(2.5)
        poll(4.5)

        XCTAssertEqual(presenter.shown.count, 2)
    }

    func testSeekingBackPartWayIsNotARestart() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "A"
        poll(120)
        poll(40)

        XCTAssertEqual(presenter.shown.count, 1)
    }

    func testRestartingInTheFirstSecondsIsNotNoticed() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "A"
        poll(4)
        poll(0.5)

        XCTAssertEqual(presenter.shown.count, 1, "the song has only just been announced")
    }

    /// A read can land after Music has moved on to the next song but before its notification
    /// arrives, and the next song also starts near zero
    func testANewSongReadBeforeItsNotificationIsNotTakenForARestart() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "B"
        poll(200)
        poll(0.4)

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
        update(snapshot(track: "B"))
        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song B"])
    }

    func testAMissingAnswerFromMusicIsNotARestart() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = nil
        poll(200)
        poll(0.4)

        XCTAssertEqual(presenter.shown.count, 1)
    }

    func testTheFirstReadingAfterASongChangeIsNotComparedWithTheOldSong() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "B"
        poll(200)
        update(snapshot(track: "B"))
        poll(1)

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song B"])
    }

    func testAFailedReadForgetsThePosition() {
        update(snapshot(track: "A"))
        musicsCurrentIdentity = "A"
        poll(200)
        poll(nil)
        poll(1)

        XCTAssertEqual(presenter.shown.count, 1, "no reading to compare with, so no restart")
    }

    func testNothingIsWatchedWhilePausedStoppedOrOff() {
        update(snapshot(track: "A", state: .paused))
        XCTAssertNil(positionWatch, "paused")

        update(snapshot(track: "A"))
        XCTAssertNotNil(positionWatch)
        update(snapshot(track: "A", state: .paused))
        XCTAssertNil(positionWatch, "paused again")

        update(snapshot(track: "A"))
        update(snapshot(track: nil, state: .stopped))
        XCTAssertNil(positionWatch, "stopped")

        update(snapshot(track: "A"))
        update(nil)
        XCTAssertNil(positionWatch, "Music quit")

        update(snapshot(track: "A"))
        controller.setEnabled(false)
        XCTAssertNil(positionWatch, "announcements off")
        XCTAssertEqual(positionReads, 0)
    }

    func testTurningAnnouncementsOnWhilePlayingStartsTheWatch() {
        controller = makeController(enabled: false)
        update(snapshot(track: "A"))
        XCTAssertNil(positionWatch)

        controller.setEnabled(true)
        XCTAssertNotNil(positionWatch)
    }

    func testTheSongPlayingAtLaunchIsWatched() {
        update(snapshot(track: "A"), seedOnly: true)
        musicsCurrentIdentity = "A"
        poll(120)
        poll(1)

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
    }

    func testTheRestartRuleOnItsOwn() {
        XCTAssertTrue(TrackAnnouncementController.isRestart(from: 5, to: 2.9))
        XCTAssertFalse(TrackAnnouncementController.isRestart(from: 4.9, to: 0))
        XCTAssertFalse(TrackAnnouncementController.isRestart(from: 120, to: 3))
    }

    // MARK: - Enablement

    func testDisabledControllerTracksTheIdentityWithoutAnnouncing() {
        controller = makeController(enabled: false)
        update(snapshot(track: "A"))
        XCTAssertTrue(presenter.shown.isEmpty)

        controller.setEnabled(true)
        update(snapshot(track: "A"))
        XCTAssertTrue(presenter.shown.isEmpty, "the song already playing when the setting turns on is not announced")

        update(snapshot(track: "B"))
        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song B"])
    }

    func testDisablingDoesNotHideTheStripAlreadyShowing() {
        update(snapshot(track: "A"))
        controller.setEnabled(false)

        XCTAssertEqual(presenter.hideCount, 0)
        XCTAssertNotNil(clock.pendingOneShot)
    }

    // MARK: - Stops, quits and odd payloads

    func testStoppedClearsTheTrackSoItAnnouncesAgain() {
        update(snapshot(track: "A"))
        update(snapshot(track: "A", state: .stopped))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song A"])
    }

    /// Replays what Music sent on 2026-09-23 for a streamed Apple Music song: its events carry
    /// no persistent ID, so the identity is name|artist|album, and a Stopped naming no track
    /// arrived 1.2 s into the song and was followed 0.18 s later by the same song playing.
    /// That was announced twice.
    func testABareStoppedBlipDuringAStreamedSongDoesNotAnnounceItAgain() {
        let song = "The River Cried|Cyndi Lauper|True Colors (40th Anniversary Expanded Edition)"
        update(snapshot(track: song))
        clock.advance(by: 0.67)
        update(snapshot(track: song))
        clock.advance(by: 0.51)
        update(snapshot(track: nil, state: .stopped))
        clock.advance(by: 0.18)
        update(snapshot(track: song))

        XCTAssertEqual(presenter.shown.count, 1, "a stop lasting a fraction of a second is Music's blip, not the user")
    }

    /// Music sends the same bare Stopped when the user really stops, measured the same day:
    /// Paused and Stopped with only a Player State key. Replaying the song after that is a
    /// new play, and announces.
    func testABareStoppedThatLastsAnnouncesTheSameSongAgain() {
        update(snapshot(track: "A"))
        update(snapshot(track: nil, state: .stopped))
        clock.advance(by: 3)
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song A"])
    }

    func testABareStoppedBlipBeforeADifferentSongStillAnnouncesIt() {
        update(snapshot(track: "A"))
        update(snapshot(track: nil, state: .stopped))
        clock.advance(by: 0.18)
        update(snapshot(track: "B"))

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A", "Song B"])
    }

    func testMusicNotRunningThenPlayingAnnounces() {
        update(nil)
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
    }

    func testMusicQuittingAfterATrackClearsIt() {
        update(snapshot(track: "A"))
        update(nil)
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 2)
    }

    func testPayloadWithoutPlayerStateChangesNothing() {
        update(snapshot(track: "A"))
        // A sourceSaved payload: no Player State, no track fields
        update(Snapshot(identity: nil, state: .unknown, title: "", artist: "", album: "", hasArtwork: true))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 1, "the rating edit must not re-announce the song")
        XCTAssertTrue(controller.canShowCurrentTrack, "the last real track is still known")
    }

    func testPayloadWithoutIdentityIsIgnored() {
        update(snapshot(track: "A"))
        update(snapshot(track: nil, title: ""))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 1)
    }

    // MARK: - Artwork

    func testArtworkLoaderFailureStillAnnouncesWithoutArtwork() {
        live = .loaded(.init())
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertNil(presenter.shown.first?.artwork)
    }

    func testArtworkIsRequestedOncePerAnnouncementAndBoundToIt() {
        let imageA = NSImage(size: CGSize(width: 1, height: 1))
        let imageB = NSImage(size: CGSize(width: 2, height: 2))

        live = .loaded(.init(artwork: imageA))
        update(snapshot(track: "A"))
        live = .loaded(.init(artwork: imageB))
        update(snapshot(track: "B"))

        XCTAssertEqual(artworkRequests, ["A", "B"])
        XCTAssertTrue(presenter.shown[0].artwork === imageA)
        XCTAssertTrue(presenter.shown[1].artwork === imageB)
    }

    func testTrackChangedDuringArtworkLoadSkipsTheAnnouncement() {
        live = .trackChanged
        update(snapshot(track: "A"))

        XCTAssertTrue(presenter.shown.isEmpty)
        XCTAssertNil(clock.pendingOneShot)

        // The identity is still recorded: a later notification for A must not announce
        live = .loaded(.init())
        update(snapshot(track: "A"))
        XCTAssertTrue(presenter.shown.isEmpty)
    }

    func testNoArtworkStillReadsTheLiveTrackButNotItsArtwork() {
        update(snapshot(track: "A", hasArtwork: false))

        XCTAssertEqual(artworkRequests, ["A"])
        XCTAssertEqual(wantsArtworkFlags, [false])
        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertNil(presenter.shown.first?.artwork)
    }

    // MARK: - Rating and heart

    func testRatingAndHeartComeFromTheLiveTrack() {
        live = .loaded(.init(rating: 80, isFavorited: true))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.first?.rating, 80)
        XCTAssertEqual(presenter.shown.first?.isFavorited, true)
    }

    func testRatingFallsBackToThePayloadAndThenToUnrated() {
        live = .loaded(.init())
        update(Snapshot(identity: "A", state: .playing, title: "Song A", artist: "", album: "", hasArtwork: true, rating: 40))
        XCTAssertEqual(presenter.shown.first?.rating, 40)
        XCTAssertEqual(presenter.shown.first?.isFavorited, false)

        update(snapshot(track: "B"))
        XCTAssertEqual(presenter.shown.last?.rating, 0)
    }

    func testRatingTheSongWhileTheStripIsUpRefreshesIt() {
        live = .loaded(.init(rating: 0, isFavorited: false))
        update(snapshot(track: "A"))
        let timer = clock.pendingOneShot

        live = .loaded(.init(rating: 60, isFavorited: true))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 1, "not a new strip")
        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [60])
        XCTAssertEqual(presenter.refreshed.first?.isFavorited, true)
        XCTAssertEqual(wantsArtworkFlags, [true, false], "the refresh does not re-read the artwork")
        XCTAssertTrue(clock.pendingOneShot === timer, "the hold timer is untouched")
    }

    func testAnUnchangedUpdateWhileUpDoesNotRefresh() {
        live = .loaded(.init(rating: 60))
        update(snapshot(track: "A"))
        update(snapshot(track: "A"))

        XCTAssertTrue(presenter.refreshed.isEmpty)
    }

    func testNoRefreshAfterTheStripHasHidden() {
        update(snapshot(track: "A"))
        clock.fireOneShot()

        live = .loaded(.init(rating: 100))
        update(snapshot(track: "A"))

        XCTAssertTrue(presenter.refreshed.isEmpty)
        XCTAssertEqual(presenter.shown.count, 1)
    }

    // MARK: - Rating in StarBar while the strip is up

    func testRatingInStarBarShowsOnTheStripWithoutReadingMusicsRating() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))
        let timer = clock.pendingOneShot
        let liveReads = artworkRequests.count

        controller.userDidRate(80)

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [80], "Music still has 20, so the strip can't have read it from there")
        XCTAssertEqual(artworkRequests.count, liveReads, "only the one-property identity read, not a full live read")
        XCTAssertEqual(identityReads, 1)
        XCTAssertEqual(playerReads, 1)
        XCTAssertTrue(clock.pendingOneShot === timer, "the hold timer is untouched")
    }

    func testARatingForATrackMusicHasMovedOnFromLeavesTheStripAlone() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))

        // Music is on another track already; its notification hasn't arrived yet
        musicsCurrentIdentity = "B"
        controller.userDidRate(100)

        XCTAssertTrue(presenter.refreshed.isEmpty)

        // …and the rating isn't remembered for A either
        musicsCurrentIdentity = nil
        update(snapshot(track: "A"))
        XCTAssertTrue(presenter.refreshed.isEmpty)
    }

    func testARatingReachesTheStripForATrackWithNoPersistentID() {
        // An Apple Music catalog track's notification carries no persistent ID, so the
        // announcement is identified by name, artist and album. The live read has to answer in
        // that shape or the two can never match, and a rating chosen in the menu bar looks
        // like it belongs to another song -- which is how the strip stopped following the
        // stars.
        live = .loaded(.init(rating: 0))
        let identity = "Silium's Hill (Live)|Daniel Lanois|Calling My Name"
        update(snapshot(track: identity))

        musicsCurrentIdentity = identity
        controller.userDidRate(60)

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [60])
    }

    func testTheLiveIdentityIsAskedForInTheShapeTheStripIsUsing() {
        // The controller has to say which identity it wants matched, or the reader cannot know
        // whether to answer with a persistent ID or with name, artist and album
        live = .loaded(.init(rating: 0))
        let identity = "Silium's Hill (Live)|Daniel Lanois|Calling My Name"
        update(snapshot(track: identity))

        controller.userDidRate(60)

        XCTAssertEqual(identityReadsFor, [identity])
    }

    func testTheHeartTheUserSetSurvivesAStaleReadFromMusic() {
        // Music applies the write a moment later, so a refresh in between still reports the
        // old value. Without holding the user's own answer the strip puts the heart back.
        live = .loaded(.init(rating: 0, isFavorited: false))
        update(snapshot(track: "A"))

        controller.userDidFavorite(true)
        XCTAssertEqual(presenter.refreshed.last?.isFavorited, true)

        // Music still says false, because it has not caught up
        live = .loaded(.init(rating: 0, isFavorited: false))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.refreshed.last?.isFavorited, true, "the heart must not flip back")
    }

    func testMusicIsBelievedAgainOnceItReportsTheHeart() {
        live = .loaded(.init(rating: 0, isFavorited: false))
        update(snapshot(track: "A"))
        controller.userDidFavorite(true)

        // Music agrees, so a change made in Music straight afterwards is not held back
        live = .loaded(.init(rating: 0, isFavorited: true))
        update(snapshot(track: "A"))
        live = .loaded(.init(rating: 0, isFavorited: false))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.refreshed.last?.isFavorited, false)
    }

    func testTheHeldHeartExpires() {
        live = .loaded(.init(rating: 0, isFavorited: false))
        update(snapshot(track: "A"))
        controller.userDidFavorite(true)

        clock.advance(by: TrackAnnouncementController.pendingRatingLifetime + 0.1)
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.refreshed.last?.isFavorited, false, "Music wins once it has had time")
    }

    func testAnIdentityMusicCannotAnswerLeavesTheStripAsTheBestGuess() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))

        musicsCurrentIdentity = nil     // a timed-out read
        controller.userDidRate(80)

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [80])
    }

    func testMusicIsBelievedAgainAsSoonAsItReportsTheSavedRating() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))
        controller.userDidRate(80)

        // Music saves it and says so, still inside the waiting time
        clock.advance(by: iTunesRadioStation.ratingSaveDelay + 0.1)
        live = .loaded(.init(rating: 80))
        update(snapshot(track: "A"))

        // The song is then rated in Music itself
        clock.advance(by: 0.4)
        live = .loaded(.init(rating: 40))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [80, 40])
    }

    func testMusicsOldRatingDoesNotUndoARatingItHasYetToSave() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))
        controller.userDidRate(80)

        // The heart is toggled, or Music sends a notification, before the rating is saved
        clock.advance(by: iTunesRadioStation.ratingSaveDelay - 0.5)
        live = .loaded(.init(rating: 20, isFavorited: true))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [80, 80])
        XCTAssertEqual(presenter.refreshed.last?.isFavorited, true)
    }

    func testMusicIsBelievedAgainOnceTheRatingHasHadTimeToSave() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))
        controller.userDidRate(80)

        clock.advance(by: TrackAnnouncementController.pendingRatingLifetime)
        live = .loaded(.init(rating: 40))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [80, 40])
    }

    func testFavouritingInStarBarShowsOnTheStrip() {
        live = .loaded(.init(rating: 60, isFavorited: false))
        update(snapshot(track: "A"))

        controller.userDidFavorite(true)
        controller.userDidFavorite(true)

        XCTAssertEqual(presenter.refreshed.map { $0.isFavorited }, [true], "an unchanged heart is not redrawn")
        XCTAssertEqual(presenter.refreshed.first?.rating, 60)
    }

    func testRatingAnotherTrackLeavesTheStripAlone() {
        update(snapshot(track: "A"))
        // Skipped to B while paused: the strip still shows A, the menu bar shows B
        update(snapshot(track: "B", state: .paused))
        musicsCurrentIdentity = "B"

        controller.userDidRate(100)
        controller.userDidFavorite(true)

        XCTAssertTrue(presenter.refreshed.isEmpty)
    }

    func testRatingWithNoTrackKnownDoesNothing() {
        controller.userDidRate(80)
        controller.userDidFavorite(true)

        XCTAssertTrue(presenter.refreshed.isEmpty)
        XCTAssertTrue(presenter.shown.isEmpty)
    }

    func testRatingWhileHiddenIsShownByShowCurrentTrack() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))
        clock.fireOneShot()

        controller.userDidRate(80)
        XCTAssertTrue(presenter.refreshed.isEmpty)

        controller.showCurrentTrack()
        XCTAssertEqual(presenter.shown.last?.rating, 80)
    }

    func testRatingInMusicWhileTheStripIsUpRefreshesIt() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))

        // Music sends sourceSaved, with nothing about the player or the track
        live = .loaded(.init(rating: 100))
        update(Snapshot(identity: nil, state: .unknown, title: "", artist: "", album: "", hasArtwork: false))

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [100])
        XCTAssertEqual(presenter.refreshed.first?.title, "Song A")

        update(snapshot(track: "A"))
        XCTAssertEqual(presenter.shown.count, 1, "the track is still known, so it doesn't announce again")
    }

    func testASourceSavedPayloadCannotPutAnotherTracksWordsOnTheStrip() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))

        // Rating a different song in Music: its album reaches the payload, but no name,
        // so the payload identifies nothing
        live = .loaded(.init(rating: 100))
        update(Snapshot(identity: nil, state: .unknown, title: "", artist: "Someone Else", album: "Another Album", hasArtwork: false, rating: 60))

        XCTAssertEqual(presenter.refreshed.map { $0.album }, ["Album"], "the strip keeps the song's own album")
        XCTAssertEqual(presenter.refreshed.first?.artist, "Artist")
        XCTAssertEqual(presenter.refreshed.first?.rating, 100, "the rating comes from Music, not the payload")
    }

    // MARK: - On demand

    func testShowCurrentTrackWorksWhileDisabledAndPaused() {
        controller = makeController(enabled: false)
        update(snapshot(track: "A", state: .paused))

        XCTAssertTrue(controller.canShowCurrentTrack)
        controller.showCurrentTrack()

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
        XCTAssertEqual(clock.pendingOneShot?.seconds, expectedHold)
    }

    func testShowCurrentTrackWithNothingPlayingDoesNothing() {
        update(nil)

        XCTAssertFalse(controller.canShowCurrentTrack)
        controller.showCurrentTrack()

        XCTAssertTrue(presenter.shown.isEmpty)
    }

    func testMenuValidationUsesTheLastUpdateWithoutReadingThePlayer() {
        let item = NSMenuItem(title: "Show Current Track", action: #selector(TrackAnnouncementController.showCurrentTrackMenuItemPressed(_:)), keyEquivalent: "")
        XCTAssertFalse(controller.validateMenuItem(item))

        update(snapshot(track: "A", state: .paused))
        let readsBefore = playerReads
        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertTrue(controller.canShowCurrentTrack)
        XCTAssertEqual(playerReads, readsBefore, "validation must not send Apple Events")

        update(snapshot(track: "A", state: .stopped))
        XCTAssertFalse(controller.validateMenuItem(item))
    }

    func testShowCurrentTrackFallsBackToTheLastUpdateWhenTheReadHasNoTrack() {
        update(snapshot(track: "A", state: .paused))
        player = Snapshot(identity: nil, state: .unknown, title: "", artist: "", album: "", hasArtwork: true)

        controller.showCurrentTrack()

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
    }

    func testShowCurrentTrackWithAnUntitledTrackDoesNothing() {
        update(snapshot(track: "A", state: .paused, title: ""))

        XCTAssertFalse(controller.canShowCurrentTrack)
        controller.showCurrentTrack()

        XCTAssertTrue(presenter.shown.isEmpty)
    }

    func testPreviewShowsTheSampleWithoutTheLoader() {
        controller.preview()

        XCTAssertEqual(presenter.shown.map { $0.identity }, ["preview"])
        XCTAssertTrue(artworkRequests.isEmpty)
        XCTAssertEqual(clock.pendingOneShot?.seconds, expectedHold)
    }

    func testPreviewShowsTheCurrentTrackWhenThereIsOne() {
        update(snapshot(track: "A", state: .playing))

        controller.preview()

        XCTAssertEqual(presenter.shown.map { $0.identity }.last, "A", "the preview is the real thing when Music has a track")
        XCTAssertFalse(presenter.shown.map { $0.identity }.contains("preview"))
    }

    func testShowCurrentTrackReportsADroppedAnnouncement() {
        update(snapshot(track: "A", state: .playing))
        let shownBefore = presenter.shown.count
        live = .trackChanged

        XCTAssertFalse(controller.showCurrentTrack(), "the track changed under the read, nothing was shown")
        XCTAssertEqual(presenter.shown.count, shownBefore)
    }

    func testPreviewReadsAgainWhenTheTrackChangesUnderIt() {
        update(snapshot(track: "A", state: .playing))
        let shownBefore = presenter.shown.count
        artworkRequests.removeAll()
        player = snapshot(track: "B", state: .playing)
        liveQueue = [.trackChanged, .loaded(.init())]

        controller.preview()

        XCTAssertEqual(artworkRequests, ["B", "B"], "one more read after the drop")
        XCTAssertEqual(presenter.shown.dropFirst(shownBefore).map { $0.identity }, ["B"], "the second read shows the new track, not the sample")
    }

    func testPreviewFallsBackToTheSampleWhenBothReadsAreDropped() {
        update(snapshot(track: "A", state: .playing))
        let shownBefore = presenter.shown.count
        live = .trackChanged

        controller.preview()

        XCTAssertEqual(presenter.shown.dropFirst(shownBefore).map { $0.identity }, ["preview"])
    }

    // MARK: - Accessibility preferences

    func testAccessibilityPreferencesReachThePresenter() {
        reduceMotion = true
        reduceTransparency = true
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.reduceMotionFlags, [true])
        XCTAssertEqual(presenter.reduceTransparencyFlags, [true])
    }

    // MARK: - Snapshots from Music's payload

    func testIdentityIsTheHexPersistentID() {
        XCTAssertEqual(Snapshot.identity(persistentID: 1), "0000000000000001")
        XCTAssertEqual(Snapshot.identity(persistentID: 0x1234ABCD5678EF90), "1234ABCD5678EF90")
        XCTAssertEqual(Snapshot.identity(persistentID: -1), "FFFFFFFFFFFFFFFF")
    }

    func testSnapshotFromPlayInfoMapsIdentityAndState() throws {
        let playing = try playInfo(["Name": "Song", "Artist": "Band", "Album": "LP", "Persistent ID": 255, "Player State": "Playing", "Artwork Count": 1])
        let snapshot = Snapshot(playInfo: playing)

        XCTAssertEqual(snapshot.identity, "00000000000000FF")
        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.title, "Song")
        XCTAssertEqual(snapshot.artist, "Band")
        XCTAssertEqual(snapshot.album, "LP")
        XCTAssertTrue(snapshot.hasArtwork)
        XCTAssertNil(snapshot.rating)
        XCTAssertNil(snapshot.isFavorited, "the notification says nothing about the heart")

        XCTAssertEqual(Snapshot(playInfo: try playInfo(["Player State": "Paused"])).state, .paused)
        XCTAssertEqual(Snapshot(playInfo: try playInfo(["Player State": "Stopped"])).state, .stopped)
        XCTAssertEqual(Snapshot(playInfo: try playInfo([:])).state, .unknown, "no Player State key says nothing about the player")
    }

    func testScriptingBridgeStateMapping() {
        XCTAssertEqual(Snapshot.state(for: .playing), .playing)
        XCTAssertEqual(Snapshot.state(for: .fastForwarding), .playing)
        XCTAssertEqual(Snapshot.state(for: .rewinding), .playing)
        XCTAssertEqual(Snapshot.state(for: .paused), .paused)
        XCTAssertEqual(Snapshot.state(for: .stopped), .stopped)
        XCTAssertEqual(Snapshot.state(for: nil), .unknown)
    }

    // MARK: - Live track check for artwork

    func testLiveTrackMatchForAPersistentID() {
        let id = "00000000000000FF"
        XCTAssertEqual(Snapshot.liveTrackMatch(identity: id, livePersistentID: "00000000000000ff", liveName: nil, liveArtist: nil, liveAlbum: nil), .same)
        XCTAssertEqual(Snapshot.liveTrackMatch(identity: id, livePersistentID: "0000000000000100", liveName: nil, liveArtist: nil, liveAlbum: nil), .changed)
        XCTAssertEqual(Snapshot.liveTrackMatch(identity: id, livePersistentID: "", liveName: "X", liveArtist: nil, liveAlbum: nil), .unknown, "a timed-out read attaches no artwork rather than the wrong one")
        XCTAssertEqual(Snapshot.liveTrackMatch(identity: id, livePersistentID: nil, liveName: nil, liveArtist: nil, liveAlbum: nil), .unknown)
    }

    func testLiveTrackMatchForAStream() {
        let id = "Live|Radio|"
        XCTAssertEqual(Snapshot.liveTrackMatch(identity: id, livePersistentID: nil, liveName: "Live", liveArtist: "Radio", liveAlbum: nil), .same)
        XCTAssertEqual(Snapshot.liveTrackMatch(identity: id, livePersistentID: nil, liveName: "Other", liveArtist: "Radio", liveAlbum: nil), .changed)
        XCTAssertEqual(Snapshot.liveTrackMatch(identity: id, livePersistentID: nil, liveName: nil, liveArtist: nil, liveAlbum: nil), .unknown)
    }

    func testSnapshotFromPlayInfoWithoutAnIDUsesTheNames() throws {
        let stream = Snapshot(playInfo: try playInfo(["Name": "Live", "Artist": "Radio", "Player State": "Playing"]))
        XCTAssertEqual(stream.identity, "Live|Radio|")
        XCTAssertEqual(stream.album, "")

        let nothing = Snapshot(playInfo: try playInfo(["Player State": "Playing"]))
        XCTAssertNil(nothing.identity)
        XCTAssertEqual(nothing.title, "")
    }

    func testSnapshotFromPlayInfoReadsTheUserRatingOnly() throws {
        XCTAssertEqual(Snapshot(playInfo: try playInfo(["Rating": 60])).rating, 60)
        XCTAssertEqual(Snapshot(playInfo: try playInfo(["Rating": 60, "Rating Computed": 1])).rating, 0, "a computed rating is not the user's")
    }

    func testSnapshotFromPlayInfoReadsArtworkCount() throws {
        XCTAssertFalse(Snapshot(playInfo: try playInfo(["Artwork Count": 0])).hasArtwork)
        XCTAssertTrue(Snapshot(playInfo: try playInfo(["Artwork Count": 2])).hasArtwork)
        XCTAssertTrue(Snapshot(playInfo: try playInfo([:])).hasArtwork)
    }

    /// Decode a `PlayInfo` the way `iTunesRadioStation.playInfoChanged` does, from Music's
    /// notification keys
    private func playInfo(_ userInfo: [String: Any]) throws -> PlayInfo {
        var keyed: [String: Any] = [:]
        for (key, value) in userInfo {
            keyed[key.snakeCaseKey] = value
        }
        let data = try JSONSerialization.data(withJSONObject: keyed)
        return try JSONDecoder().decode(PlayInfo.self, from: data)
    }

}

// MARK: - Fakes

private final class FakePresenter: TrackAnnouncementPresenter {
    private(set) var shown: [TrackAnnouncement] = []
    private(set) var refreshed: [TrackAnnouncement] = []
    private(set) var reduceMotionFlags: [Bool] = []
    private(set) var reduceTransparencyFlags: [Bool] = []
    private(set) var hideCount = 0

    func show(_ announcement: TrackAnnouncement, reduceMotion: Bool, reduceTransparency: Bool) {
        shown.append(announcement)
        reduceMotionFlags.append(reduceMotion)
        reduceTransparencyFlags.append(reduceTransparency)
    }

    func refresh(_ announcement: TrackAnnouncement) {
        refreshed.append(announcement)
    }

    func hide() {
        hideCount += 1
    }
}
