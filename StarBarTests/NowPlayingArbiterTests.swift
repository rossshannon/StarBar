//
//  NowPlayingArbiterTests.swift
//  StarBarTests
//
//  Which player the strip and the menu bar follow when Music and Spotify are both open.
//

import XCTest
@testable import StarBar

final class NowPlayingArbiterTests: XCTestCase {

    private typealias State = NowPlayingArbiter.SourceState

    private var time = Date(timeIntervalSinceReferenceDate: 0)
    private var arbiter: NowPlayingArbiter!

    override func setUp() {
        super.setUp()
        time = Date(timeIntervalSinceReferenceDate: 0)
        arbiter = NowPlayingArbiter(now: { [unowned self] in self.time })
    }

    private func later() {
        time = time.addingTimeInterval(1)
    }

    // MARK: - The rule

    func testNothingRunningFollowsNothing() {
        XCTAssertNil(NowPlayingArbiter.choose(current: nil, states: [:]))
        XCTAssertNil(NowPlayingArbiter.choose(current: .music, states: [.music: State(isRunning: false, isPlaying: false)]))
    }

    func testAPlayingPlayerBeatsOneThatIsNot() {
        let states: [PlayerKind: State] = [
            .music: State(isRunning: true, isPlaying: false, startedPlayingAt: Date(timeIntervalSinceReferenceDate: 9)),
            .spotify: State(isRunning: true, isPlaying: true, startedPlayingAt: Date(timeIntervalSinceReferenceDate: 1)),
        ]
        XCTAssertEqual(NowPlayingArbiter.choose(current: .music, states: states), .spotify)
    }

    func testOfTwoPlayingTheOneThatStartedLastWins() {
        let states: [PlayerKind: State] = [
            .music: State(isRunning: true, isPlaying: true, startedPlayingAt: Date(timeIntervalSinceReferenceDate: 1)),
            .spotify: State(isRunning: true, isPlaying: true, startedPlayingAt: Date(timeIntervalSinceReferenceDate: 2)),
        ]
        XCTAssertEqual(NowPlayingArbiter.choose(current: .music, states: states), .spotify)
    }

    func testATieKeepsTheCurrentPlayer() {
        let start = Date(timeIntervalSinceReferenceDate: 1)
        let states: [PlayerKind: State] = [
            .music: State(isRunning: true, isPlaying: true, startedPlayingAt: start),
            .spotify: State(isRunning: true, isPlaying: true, startedPlayingAt: start),
        ]
        XCTAssertEqual(NowPlayingArbiter.choose(current: .spotify, states: states), .spotify)
        XCTAssertEqual(NowPlayingArbiter.choose(current: .music, states: states), .music)
    }

    func testWithNeitherPlayingTheCurrentPlayerStays() {
        let states: [PlayerKind: State] = [
            .music: State(isRunning: true, isPlaying: false),
            .spotify: State(isRunning: true, isPlaying: false),
        ]
        XCTAssertEqual(NowPlayingArbiter.choose(current: .spotify, states: states), .spotify)
    }

    func testWhenTheCurrentPlayerQuitsTheOtherTakesOver() {
        let states: [PlayerKind: State] = [
            .music: State(isRunning: true, isPlaying: false),
            .spotify: State(isRunning: false, isPlaying: false),
        ]
        XCTAssertEqual(NowPlayingArbiter.choose(current: .spotify, states: states), .music)
    }

    func testANotRunningPlayerNeverPlays() {
        let states: [PlayerKind: State] = [
            .music: State(isRunning: true, isPlaying: false),
            .spotify: State(isRunning: false, isPlaying: true),
        ]
        XCTAssertEqual(NowPlayingArbiter.choose(current: nil, states: states), .music)
    }

    // MARK: - Updates

    func testASongStartingInSpotifyTakesOverFromMusic() {
        arbiter.update(.music, isRunning: true, isPlaying: true, identity: "A")
        XCTAssertEqual(arbiter.active, .music)
        later()

        XCTAssertTrue(arbiter.update(.spotify, isRunning: true, isPlaying: true, identity: "S"))
        XCTAssertEqual(arbiter.active, .spotify)
    }

    func testPausingSpotifyAndPlayingMusicFollowsMusic() {
        arbiter.update(.music, isRunning: true, isPlaying: false, identity: "A")
        arbiter.update(.spotify, isRunning: true, isPlaying: true, identity: "S")
        later()
        arbiter.update(.spotify, isRunning: true, isPlaying: false, identity: "S")
        XCTAssertEqual(arbiter.active, .spotify, "a pause never hands over")
        later()

        // The song already loaded in Music: no new song, just play
        arbiter.update(.music, isRunning: true, isPlaying: true, identity: "A")

        XCTAssertEqual(arbiter.active, .music)
    }

    func testABareStopBetweenSpotifySongsDoesNotHandOver() {
        arbiter.update(.music, isRunning: true, isPlaying: false, identity: "A")
        arbiter.update(.spotify, isRunning: true, isPlaying: true, identity: "S")
        later()
        arbiter.update(.spotify, isRunning: true, isPlaying: false, identity: nil)
        later()
        arbiter.update(.spotify, isRunning: true, isPlaying: true, identity: "T")

        XCTAssertEqual(arbiter.active, .spotify)
    }

    func testANewSongInTheOtherPlayerWhileBothPlayTakesOver() {
        arbiter.update(.music, isRunning: true, isPlaying: true, identity: "A")
        later()
        arbiter.update(.spotify, isRunning: true, isPlaying: true, identity: "S")
        XCTAssertEqual(arbiter.active, .spotify)
        later()

        arbiter.update(.music, isRunning: true, isPlaying: true, identity: "B")

        XCTAssertEqual(arbiter.active, .music)
    }

    func testAnUpdateForTheSameSongWhilePlayingIsNoNewStart() {
        arbiter.update(.music, isRunning: true, isPlaying: true, identity: "A")
        later()
        arbiter.update(.spotify, isRunning: true, isPlaying: true, identity: "S")
        later()

        // A rating change in Music sends another Playing update for the same song
        arbiter.update(.music, isRunning: true, isPlaying: true, identity: "A")

        XCTAssertEqual(arbiter.active, .spotify)
    }

    func testSpotifyQuittingHandsBackToMusic() {
        arbiter.update(.music, isRunning: true, isPlaying: false, identity: "A")
        arbiter.update(.spotify, isRunning: true, isPlaying: true, identity: "S")

        XCTAssertTrue(arbiter.update(.spotify, isRunning: false, isPlaying: false, identity: nil))
        XCTAssertEqual(arbiter.active, .music)
    }

    func testAnUnchangedChoiceReportsNoChange() {
        arbiter.update(.music, isRunning: true, isPlaying: true, identity: "A")

        XCTAssertFalse(arbiter.update(.music, isRunning: true, isPlaying: false, identity: "A"))
    }

}
