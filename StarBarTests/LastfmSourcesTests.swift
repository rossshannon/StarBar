//
//  LastfmSourcesTests.swift
//  StarBarTests
//
//  What Music's and Spotify's notifications become in the scrobbler's terms. Only the pure
//  parts: the live reads of Music can't run under tests.
//

import XCTest
@testable import StarBar

final class LastfmSourcesTests: XCTestCase {

    // MARK: - Music

    /// A `PlayInfo` as Codable spells it; the station decodes Music's own key names to these
    private func playInfo(_ fields: [String: Any]) throws -> PlayInfo {
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(PlayInfo.self, from: data)
    }

    private let song: [String: Any] = [
        "name": "Running Up That Hill",
        "artist": "Kate Bush",
        "album": "Hounds of Love",
        "albumArtist": "Kate Bush",
        "trackNumber": 1,
        "totalTime": 240000,
        "persistentID": -5_678_901_234_567_890,
        "playerState": "Playing",
    ]

    private func music(_ changes: [String: Any] = [:], removing removed: [String] = []) throws -> PlayerObservation? {
        var fields = song
        changes.forEach { fields[$0.key] = $0.value }
        removed.forEach { fields.removeValue(forKey: $0) }
        return try playInfo(fields).lastfmObservation
    }

    func testAPlayingSongWithAPersistentIDIsIdentifiedAsTheStripIdentifiesIt() throws {
        let info = try playInfo(song)
        let observation = try XCTUnwrap(info.lastfmObservation)

        XCTAssertEqual(observation.state, .playing)
        // A decimal or differently cased identity would never match the live read in
        // musicPosition(matching:), so every position check would say the song changed
        XCTAssertEqual(observation.song?.identity, TrackAnnouncementController.PlayerSnapshot(playInfo: info).identity)
        XCTAssertEqual(observation.song?.identity.count, 16, "the persistent ID goes as 16 hex digits")
        XCTAssertEqual(observation.song?.track.title, "Running Up That Hill")
        XCTAssertEqual(observation.song?.track.artist, "Kate Bush")
        XCTAssertEqual(observation.song?.track.album, "Hounds of Love")
        XCTAssertEqual(observation.song?.isScrobblable, true)
        XCTAssertNil(observation.position, "Music's notification says nothing of the position")
    }

    func testASongWithNoPersistentIDIsIdentifiedByItsNames() throws {
        let observation = try XCTUnwrap(music(removing: ["persistentID"]))

        XCTAssertEqual(observation.song?.identity, "Running Up That Hill|Kate Bush|Hounds of Love",
                       "an Apple Music catalog song sends no ID, and the strip names it this way")
    }

    func testPausedIsPaused() throws {
        XCTAssertEqual(try music(["playerState": "Paused"])?.state, .paused)
    }

    func testStoppedIsAStop() throws {
        // Music's "Stopped" decodes as .unknown; taken for "nothing new" a stopped song would
        // go on counting
        XCTAssertEqual(try music(["playerState": "Stopped"])?.state, .stopped)
    }

    func testAPayloadWithNoPlayerStateSaysNothing() throws {
        XCTAssertNil(try music(removing: ["playerState"]), "a payload with no state changes nothing")
    }

    func testAPayloadNamingNoSongHasNoSong() throws {
        let observation = try XCTUnwrap(music(["playerState": "Stopped"], removing: ["name", "persistentID"]))

        XCTAssertEqual(observation.state, .stopped)
        XCTAssertNil(observation.song, "a bare Stopped names no song")
    }

    func testTheLengthIsInSeconds() throws {
        XCTAssertEqual(try music()?.song?.track.duration, 240, "totalTime is milliseconds")
    }

    func testANoughtOrMissingLengthIsNoLength() throws {
        // A length of 0 would make every song "30 seconds or shorter" and never scrobble it
        XCTAssertNil(try music(["totalTime": 0])?.song?.track.duration)
        XCTAssertNil(try music(removing: ["totalTime"])?.song?.track.duration)
    }

    func testTheAlbumArtistIsKeptOnlyWhenItIsNotTheArtist() throws {
        XCTAssertNil(try music()?.song?.track.albumArtist, "the same as the artist says nothing")
        XCTAssertEqual(try music(["albumArtist": "Various Artists"])?.song?.track.albumArtist, "Various Artists")
        XCTAssertNil(try music(["albumArtist": ""])?.song?.track.albumArtist, "an empty album artist is none")
    }

    func testTrackNumberNoughtIsDropped() throws {
        XCTAssertEqual(try music()?.song?.track.trackNumber, 1)
        XCTAssertNil(try music(["trackNumber": 0])?.song?.track.trackNumber, "Music sends 0 for no track number")
    }

    func testASongWithNoArtistIsNotScrobblable() throws {
        // A radio stream has a name and no artist
        let observation = try XCTUnwrap(music(removing: ["artist", "albumArtist"]))

        XCTAssertNotNil(observation.song, "it is still a song, so the one before it ends")
        XCTAssertEqual(observation.song?.isScrobblable, false)
    }

    func testNamesGoAsMusicGaveThem() throws {
        let observation = try music(["name": "  Song (Remastered 2011) ", "artist": "The Artist "])

        XCTAssertEqual(observation?.song?.track.title, "  Song (Remastered 2011) ", "Last.fm corrects names itself")
        XCTAssertEqual(observation?.song?.track.artist, "The Artist ")
    }

    // MARK: - Spotify

    private func spotify(trackID: String? = "spotify:track:4uLU6hMCjMI75M1A2tKUQC", name: String? = "Running Up That Hill",
                         artist: String? = "Kate Bush", album: String? = "Hounds of Love",
                         state: SpotifyPlayInfo.State = .playing, duration: Int? = 213560,
                         position: TimeInterval? = 7.938) -> PlayerObservation? {
        return SpotifyPlayInfo(trackID: trackID, name: name, artist: artist, album: album, state: state,
                               duration: duration, position: position).lastfmObservation
    }

    func testASpotifySongIsScrobblable() throws {
        let observation = try XCTUnwrap(spotify())

        XCTAssertEqual(observation.state, .playing)
        XCTAssertEqual(observation.song?.identity, "spotify:track:4uLU6hMCjMI75M1A2tKUQC", "the Track ID is the identity")
        XCTAssertEqual(observation.song?.track.title, "Running Up That Hill")
        XCTAssertEqual(observation.song?.track.artist, "Kate Bush")
        XCTAssertEqual(observation.song?.track.album, "Hounds of Love")
        XCTAssertEqual(try XCTUnwrap(observation.song?.track.duration), 213.56, accuracy: 0.001, "Duration is milliseconds")
        XCTAssertEqual(observation.song?.isScrobblable, true)
        XCTAssertEqual(observation.position, 7.938, "the position is passed on as Spotify gave it")
    }

    func testASpotifyLocalFileIsScrobblable() {
        XCTAssertEqual(spotify(trackID: "spotify:local:Kate+Bush:Hounds+of+Love:Running+Up+That+Hill:298")?.song?.isScrobblable, true)
    }

    func testAnEpisodeIsASongThatIsNeverScrobbled() throws {
        let observation = try XCTUnwrap(spotify(trackID: "spotify:episode:1cy1cIpeY7px7zxLhjVIZE", artist: "", album: "A Podcast"))

        XCTAssertNotNil(observation.song, "the song before it still has to end")
        XCTAssertEqual(observation.song?.isScrobblable, false)
    }

    func testAnAdIsNeverScrobbled() throws {
        // Even with a title and an artist, which an ad may well have
        let observation = try XCTUnwrap(spotify(trackID: "spotify:ad:0123456789abcdef", name: "An Advert", artist: "A Brand"))

        XCTAssertNotNil(observation.song)
        XCTAssertEqual(observation.song?.isScrobblable, false)
    }

    func testASpotifyPayloadWithNoTrackIDHasNoSong() throws {
        let observation = try XCTUnwrap(spotify(trackID: nil))

        XCTAssertNil(observation.song)
    }

    func testAnUnknownSpotifyStateSaysNothing() {
        XCTAssertNil(spotify(state: .unknown))
    }

    func testSpotifyStatesMap() {
        XCTAssertEqual(spotify(state: .paused)?.state, .paused)
        XCTAssertEqual(spotify(state: .stopped)?.state, .stopped)
    }

    func testASpotifySongWithNoLengthHasNone() {
        XCTAssertNil(spotify(duration: nil)?.song?.track.duration)
        XCTAssertNil(spotify(duration: 0)?.song?.track.duration, "a length of 0 is none")
    }

}
