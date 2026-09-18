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

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[ScriptBridgeTests.optInVariable] == "1",
            "Live Music tests are opt-in: run ./build.sh --test-all with a track playing"
        )
        try XCTSkipUnless(iTunesRadioStation.shared.iTunes != nil, "Music is not running")
    }

    func testApplicationReportsAVersion() {
        let version = iTunesRadioStation.shared.iTunes?.version ?? ""
        XCTAssertFalse(version.isEmpty)
    }

    func testCurrentTrackHasArtwork() throws {
        let track = try XCTUnwrap(iTunesRadioStation.shared.iTunes?.currentTrackCopy, "Play a track before running this test")
        XCTAssertNotNil(track.firstArtworkImage(), "The playing track needs artwork")
    }

    func testCurrentTrackRatingRoundsToHalfStars() throws {
        let track = try XCTUnwrap(iTunesRadioStation.shared.iTunes?.currentTrackCopy, "Play a track before running this test")
        let rating = track.rating ?? 0
        XCTAssertTrue((0...100).contains(rating))
        XCTAssertEqual(rating % 10, 0, "Music stores whole and half stars as multiples of 10")
    }

}
