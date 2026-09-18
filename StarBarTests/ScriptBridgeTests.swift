//
//  ScriptBridgeTests.swift
//  StarBarTests
//
//  Reads from the running Music app through the Scripting Bridge. Opt-in: these need Music
//  playing a track with artwork and permission to control it, so they are skipped unless
//  STARBAR_LIVE_MUSIC_TESTS=1 is in the test host's environment (`./build.sh --test-all`).
//  They only read; nothing here writes to the library.
//

import XCTest
@testable import StarBar

class ScriptBridgeTests: XCTestCase {

    static let optInVariable = "STARBAR_LIVE_MUSIC_TESTS"

    struct MusicNotRunning: Error {}

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[ScriptBridgeTests.optInVariable] == "1",
            "Live Music tests are opt-in: run ./build.sh --test-all with a track playing"
        )
        // Opted in but no Music is a failure, not a skip: a skip would let --test-all pass
        // without ever running these
        guard iTunesRadioStation.shared.iTunes != nil else {
            XCTFail("STARBAR_LIVE_MUSIC_TESTS is set but Music is not running")
            throw MusicNotRunning()
        }
    }

    func testApplicationReportsAVersion() {
        let version = iTunesRadioStation.shared.iTunes?.version ?? ""
        XCTAssertFalse(version.isEmpty)
    }

    func testCurrentTrackHasArtwork() throws {
        let track = try XCTUnwrap(iTunesRadioStation.shared.iTunes?.currentTrackCopy, "Play a track before running this test")
        XCTAssertNotNil(track.firstArtworkImage(), "The playing track needs artwork")
    }

    /// The app's reading of the track: a user rating is nil or in Music's range, and the
    /// favourite flag answers through whichever property name this Music version has
    func testCurrentTrackReadsThroughTheAppsAccessors() throws {
        let track = try XCTUnwrap(iTunesRadioStation.shared.iTunes?.currentTrackCopy, "Play a track before running this test")
        if let rating = track.userRating {
            XCTAssertTrue((0...100).contains(rating))
            XCTAssertEqual(rating % 10, 0, "Music stores whole and half stars as multiples of 10")
        }
        XCTAssertEqual(track.isFavorited, track.favorited ?? track.loved ?? false)
    }

}
