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
    private var artworkRequests: [String] = []
    private var wantsArtworkFlags: [Bool] = []
    private var reduceMotion = false
    private var reduceTransparency = false
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
                return self.live
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

    func testRatingInStarBarShowsOnTheStripWithoutAskingMusic() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))
        let timer = clock.pendingOneShot

        controller.userDidRate(80)

        XCTAssertEqual(presenter.refreshed.map { $0.rating }, [80], "Music still has 20, so the strip can't have read it from there")
        XCTAssertEqual(wantsArtworkFlags, [true, false], "the check that Music is still on this track doesn't re-read the artwork")
        XCTAssertEqual(playerReads, 1)
        XCTAssertTrue(clock.pendingOneShot === timer, "the hold timer is untouched")
    }

    func testARatingForATrackMusicHasMovedOnFromLeavesTheStripAlone() {
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))

        // Music is on another track already; its notification hasn't arrived yet
        live = .trackChanged
        controller.userDidRate(100)

        XCTAssertTrue(presenter.refreshed.isEmpty)

        // …and the rating isn't remembered for A either
        live = .loaded(.init(rating: 20))
        update(snapshot(track: "A"))
        XCTAssertTrue(presenter.refreshed.isEmpty)
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
        live = .trackChanged

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
