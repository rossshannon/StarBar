//
//  SpotifyPlayInfoTests.swift
//  StarBarTests
//
//  Decoding Spotify's PlaybackStateChanged payload, with payloads shaped like the ones
//  measured from Spotify 1.3.5 on 2026-10-21 (docs/spotify.md).
//

import XCTest
@testable import StarBar

final class SpotifyPlayInfoTests: XCTestCase {

    /// A song's payload as Spotify sent it: all 13 keys, with their measured types
    private func song(state: String = "Playing", trackID: String = "spotify:track:4uLU6hMCjMI75M1A2tKUQC", hasArtwork: Bool = true) -> [AnyHashable: Any] {
        return [
            "Album": "Hounds of Love",
            "Album Artist": "",
            "Artist": "Kate Bush",
            "Disc Number": 1,
            "Duration": 213560,
            "Has Artwork": hasArtwork,
            "Name": "Running Up That Hill",
            "Play Count": 0,
            "Playback Position": 7.938,
            "Player State": state,
            "Popularity": 80,
            "Track ID": trackID,
            "Track Number": 1,
        ]
    }

    func testASongPayloadDecodes() {
        let info = SpotifyPlayInfo(userInfo: song())

        XCTAssertEqual(info.trackID, "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(info.name, "Running Up That Hill")
        XCTAssertEqual(info.artist, "Kate Bush")
        XCTAssertEqual(info.album, "Hounds of Love")
        XCTAssertEqual(info.state, .playing)
        XCTAssertEqual(info.duration, 213560)
        XCTAssertTrue(info.hasArtwork)
        XCTAssertEqual(info.content, .track)
        XCTAssertTrue(info.isAnnounceable)
    }

    func testPlayerStates() {
        XCTAssertEqual(SpotifyPlayInfo(userInfo: song(state: "Paused")).state, .paused)
        XCTAssertEqual(SpotifyPlayInfo(userInfo: song(state: "Stopped")).state, .stopped)
        XCTAssertEqual(SpotifyPlayInfo(userInfo: song(state: "Buffering")).state, .unknown, "a state this code doesn't know changes nothing")
        var noState = song()
        noState["Player State"] = nil
        XCTAssertEqual(SpotifyPlayInfo(userInfo: noState).state, .unknown, "no state at all changes nothing")
    }

    /// What Spotify sent when it quit: the state and nothing else
    func testABareStopHasNoTrack() {
        let info = SpotifyPlayInfo(userInfo: ["Player State": "Stopped"])

        XCTAssertEqual(info.state, .stopped)
        XCTAssertNil(info.trackID)
        XCTAssertFalse(info.isAnnounceable)
        XCTAssertNil(info.snapshot.identity)
        XCTAssertEqual(info.snapshot.state, .stopped)
    }

    func testOnlySongsEpisodesAndLocalFilesAreAnnounced() {
        XCTAssertTrue(SpotifyPlayInfo(userInfo: song(trackID: "spotify:episode:1cy1cIpeY7px7zxLhjVIZE")).isAnnounceable)
        XCTAssertTrue(SpotifyPlayInfo(userInfo: song(trackID: "spotify:local:Artist:Album:Title:200")).isAnnounceable)
        XCTAssertFalse(SpotifyPlayInfo(userInfo: song(trackID: "spotify:ad:0123456789abcdef")).isAnnounceable)
        XCTAssertFalse(SpotifyPlayInfo(userInfo: song(trackID: "")).isAnnounceable)
        XCTAssertNil(SpotifyPlayInfo(userInfo: song(trackID: "")).trackID, "an empty ID is no ID")
    }

    func testAnAdHasNoIdentity() {
        let info = SpotifyPlayInfo(userInfo: song(trackID: "spotify:ad:0123456789abcdef"))

        XCTAssertNil(info.snapshot.identity, "so the strip and the menu bar keep the song before it")
        XCTAssertEqual(info.snapshot.state, .playing)
    }

    func testASongSnapshot() {
        let snapshot = SpotifyPlayInfo(userInfo: song()).snapshot

        XCTAssertEqual(snapshot.identity, "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.title, "Running Up That Hill")
        XCTAssertEqual(snapshot.artist, "Kate Bush")
        XCTAssertEqual(snapshot.album, "Hounds of Love")
        XCTAssertTrue(snapshot.hasArtwork)
        XCTAssertEqual(snapshot.source, .spotify)
        XCTAssertNil(snapshot.rating)
        XCTAssertNil(snapshot.isFavorited)
    }

    /// Measured: an episode's Artist was empty and its Album (and Album Artist) held the show
    func testAnEpisodePutsItsShowOnTheArtistLine() {
        var episode = song(trackID: "spotify:episode:1cy1cIpeY7px7zxLhjVIZE")
        episode["Name"] = "2026-Part 2-BRK Annual Shareholders Meeting"
        episode["Artist"] = ""
        episode["Album"] = "Berkshire Hathaway Annual Meetings"
        episode["Album Artist"] = "Berkshire Hathaway Annual Meetings"

        let snapshot = SpotifyPlayInfo(userInfo: episode).snapshot

        XCTAssertEqual(snapshot.artist, "Berkshire Hathaway Annual Meetings")
        XCTAssertEqual(snapshot.album, "")
    }

    func testArtworkIsSkippedWhenSpotifySaysThereIsNone() {
        XCTAssertFalse(SpotifyPlayInfo(userInfo: song(hasArtwork: false)).snapshot.hasArtwork)
        XCTAssertFalse(SpotifyPlayInfo(userInfo: song(trackID: "spotify:local:a:b:c:1")).snapshot.hasArtwork, "a local file has no artwork URL")
        var noKey = song()
        noKey["Has Artwork"] = nil
        XCTAssertTrue(SpotifyPlayInfo(userInfo: noKey).hasArtwork, "missing means try")
    }

}
