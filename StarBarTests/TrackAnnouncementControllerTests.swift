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
    private var artwork: TrackAnnouncementController.ArtworkLoad = .loaded(nil)
    private var artworkRequests: [String] = []
    private var reduceMotion = false
    private var reduceTransparency = false
    private var controller: TrackAnnouncementController!

    override func setUp() {
        super.setUp()
        presenter = FakePresenter()
        clock = FakeClock()
        player = nil
        artwork = .loaded(nil)
        artworkRequests = []
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
            readPlayer: { [unowned self] in self.player },
            loadArtwork: { [unowned self] identity in
                self.artworkRequests.append(identity)
                return self.artwork
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

    func testPayloadWithoutIdentityIsIgnored() {
        update(snapshot(track: "A"))
        update(snapshot(track: nil, title: ""))
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 1)
    }

    // MARK: - Artwork

    func testArtworkLoaderFailureStillAnnouncesWithoutArtwork() {
        artwork = .loaded(nil)
        update(snapshot(track: "A"))

        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertNil(presenter.shown.first?.artwork)
    }

    func testArtworkIsRequestedOncePerAnnouncementAndBoundToIt() {
        let imageA = NSImage(size: CGSize(width: 1, height: 1))
        let imageB = NSImage(size: CGSize(width: 2, height: 2))

        artwork = .loaded(imageA)
        update(snapshot(track: "A"))
        artwork = .loaded(imageB)
        update(snapshot(track: "B"))

        XCTAssertEqual(artworkRequests, ["A", "B"])
        XCTAssertTrue(presenter.shown[0].artwork === imageA)
        XCTAssertTrue(presenter.shown[1].artwork === imageB)
    }

    func testTrackChangedDuringArtworkLoadSkipsTheAnnouncement() {
        artwork = .trackChanged
        update(snapshot(track: "A"))

        XCTAssertTrue(presenter.shown.isEmpty)
        XCTAssertNil(clock.pendingOneShot)

        // The identity is still recorded: a later notification for A must not announce
        artwork = .loaded(nil)
        update(snapshot(track: "A"))
        XCTAssertTrue(presenter.shown.isEmpty)
    }

    func testNoArtworkSkipsTheLoader() {
        update(snapshot(track: "A", hasArtwork: false))

        XCTAssertTrue(artworkRequests.isEmpty)
        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertNil(presenter.shown.first?.artwork)
    }

    // MARK: - On demand

    func testShowCurrentTrackWorksWhileDisabledAndPaused() {
        controller = makeController(enabled: false)
        player = snapshot(track: "A", state: .paused)

        XCTAssertTrue(controller.canShowCurrentTrack)
        controller.showCurrentTrack()

        XCTAssertEqual(presenter.shown.map { $0.title }, ["Song A"])
        XCTAssertEqual(clock.pendingOneShot?.seconds, expectedHold)
    }

    func testShowCurrentTrackWithNothingPlayingDoesNothing() {
        player = nil

        XCTAssertFalse(controller.canShowCurrentTrack)
        controller.showCurrentTrack()

        XCTAssertTrue(presenter.shown.isEmpty)
    }

    func testMenuItemIsDisabledWithoutATrack() {
        let item = NSMenuItem(title: "Show Current Track", action: #selector(TrackAnnouncementController.showCurrentTrackMenuItemPressed(_:)), keyEquivalent: "")

        player = nil
        XCTAssertFalse(controller.validateMenuItem(item))

        player = snapshot(track: "A")
        XCTAssertTrue(controller.validateMenuItem(item))
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

        XCTAssertEqual(Snapshot(playInfo: try playInfo(["Player State": "Paused"])).state, .paused)
        XCTAssertEqual(Snapshot(playInfo: try playInfo(["Player State": "Stopped"])).state, .stopped)
        XCTAssertEqual(Snapshot(playInfo: try playInfo([:])).state, .stopped)
    }

    func testSnapshotFromPlayInfoWithoutAnIDUsesTheNames() throws {
        let stream = Snapshot(playInfo: try playInfo(["Name": "Live", "Artist": "Radio", "Player State": "Playing"]))
        XCTAssertEqual(stream.identity, "Live|Radio|")
        XCTAssertEqual(stream.album, "")

        let nothing = Snapshot(playInfo: try playInfo(["Player State": "Playing"]))
        XCTAssertNil(nothing.identity)
        XCTAssertEqual(nothing.title, "")
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
    private(set) var reduceMotionFlags: [Bool] = []
    private(set) var reduceTransparencyFlags: [Bool] = []
    private(set) var hideCount = 0

    func show(_ announcement: TrackAnnouncement, reduceMotion: Bool, reduceTransparency: Bool) {
        shown.append(announcement)
        reduceMotionFlags.append(reduceMotion)
        reduceTransparencyFlags.append(reduceTransparency)
    }

    func hide() {
        hideCount += 1
    }
}
