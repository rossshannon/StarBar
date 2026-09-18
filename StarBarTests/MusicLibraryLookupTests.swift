//
//  MusicLibraryLookupTests.swift
//  StarBarTests
//
//  Finding a song in the user's library through the Scripting Bridge.
//
//  These read from Music, so they only run with `--test-all`. They are read-only: nothing
//  here writes a rating, a favourite or anything else, because a rating cannot be undone.
//
//  Every assertion here is a claim about Music's own API that was got wrong once and cost a
//  real bug. They are not restatements of the code: each one can fail if Music behaves
//  differently, and two of them did fail before the code was fixed.
//

import XCTest
import ScriptingBridge
@testable import StarBar

final class MusicLibraryLookupTests: XCTestCase {

    /// The library playlist, or nil when Music isn't running
    private func libraryPlaylist() throws -> iTunesPlaylist {
        let iTunes = try XCTUnwrap(iTunesRadioStation.shared.iTunes, "Music isn't running")
        let source = try XCTUnwrap(
            iTunes.sources?().first(where: { ($0 as? iTunesSource)?.kind == .library }) as? iTunesSource,
            "no library source"
        )
        return try XCTUnwrap(source.libraryPlaylists?().firstObject as? iTunesPlaylist, "no library playlist")
    }

    private func firstLibraryTrack() throws -> iTunesTrack {
        let tracks = try XCTUnwrap(try libraryPlaylist().tracks?(), "no tracks")
        try XCTSkipUnless(tracks.count > 0, "the library is empty")
        return try XCTUnwrap(tracks.firstObject as? iTunesTrack, "first track unreadable")
    }

    // MARK: - The two IDs a track has

    /// A track carries both an `id` and a `database ID`, and they are different numbers.
    /// Assuming they were the same is what made a rating read back as zero.
    func testATracksIdIsNotItsDatabaseId() throws {
        let track = try firstLibraryTrack()

        let id = try XCTUnwrap(track.id?(), "no id")
        let databaseID = try XCTUnwrap(track.databaseID, "no database ID")

        XCTAssertNotEqual(id, databaseID, """
            Music is now giving a track the same id and database ID. If that is really true \
            everywhere, the warning in libraryCopy(of:) can go -- but check before trusting it.
            """)
    }

    /// `object(withID:)` matches a track's `id`, so a database ID finds nothing -- and it says
    /// so by answering with a specifier that reads as empty rather than by returning nil.
    /// That silence is what made the bug look like an unrated song.
    func testObjectWithIdDoesNotFindATrackByItsDatabaseId() throws {
        let track = try firstLibraryTrack()
        let databaseID = try XCTUnwrap(track.databaseID, "no database ID")
        let tracks = try XCTUnwrap(try libraryPlaylist().tracks?(), "no tracks")

        // Only meaningful while the two numbers differ, which the test above pins down
        try XCTSkipUnless(track.id?() != databaseID, "this track's id and database ID match")

        let fetched = tracks.object(withID: databaseID) as? iTunesTrack

        // It answers with a specifier that is alive enough to read from and empty enough to
        // be useless: the name comes back as "" and the database ID as 0, not as nil
        XCTAssertTrue((fetched?.name ?? "").isEmpty, """
            object(withID:) now answers for a database ID. If so it is safe to use, but until \
            this fails, keep the track a search returned instead.
            """)
        XCTAssertEqual(fetched?.databaseID ?? 0, 0)
    }

    // MARK: - Finding the user's own copy

    /// The regression test for the bug: the track handed back has to be a live one.
    ///
    /// Before the fix this returned a dead specifier -- nil name, zero rating -- so the menu
    /// bar drew no stars over a song that was rated.
    func testLibraryCopyReturnsATrackThatCanBeRead() throws {
        let track = try firstLibraryTrack()

        let copy = try XCTUnwrap(iTunesRadioStation.shared.libraryCopy(of: track), "no copy found")

        // Not merely non-nil: a dead specifier answers with an empty string and a zero, so
        // asserting non-nil here would pass for exactly the object this test exists to catch
        XCTAssertFalse((copy.name ?? "").isEmpty, "a dead specifier reads as empty here")
        XCTAssertNotEqual(copy.databaseID ?? 0, 0, "a dead specifier reads as 0 here")
    }

    /// And it has to be the same song, not merely some song
    func testLibraryCopyFindsTheSameSong() throws {
        let track = try firstLibraryTrack()

        let copy = try XCTUnwrap(iTunesRadioStation.shared.libraryCopy(of: track), "no copy found")

        XCTAssertEqual(copy.name, track.name)
        XCTAssertEqual(copy.artist, track.artist)
        XCTAssertEqual(copy.album, track.album)
    }

    /// The rating the menu bar would draw is the one the library really holds
    func testLibraryCopyCarriesTheRatingTheLibraryHolds() throws {
        let track = try firstLibraryTrack()

        let copy = try XCTUnwrap(iTunesRadioStation.shared.libraryCopy(of: track), "no copy found")

        // Same song, so the same rating -- unless the library holds several copies of it,
        // in which case the oldest is taken and the ratings may differ
        try XCTSkipUnless(copy.databaseID == track.databaseID, "the library has more than one copy")
        XCTAssertEqual(copy.rating, track.rating)
        XCTAssertEqual(copy.ratingKind, track.ratingKind)
    }

    // MARK: - Telling a library song from a catalog stream

    func testALibraryTrackIsNotACatalogStream() throws {
        let track = try firstLibraryTrack()

        XCTAssertEqual(track.scriptingClassCode, MusicTrackClass.fileTrack)
        XCTAssertFalse(track.isCatalogStream, "a song in the library can always be rated")
    }

    /// The control reads the class from `currentTrackCopy`, a resolved copy rather than the
    /// live specifier, so the class has to survive that round trip.
    func testTheClassCanBeReadFromAResolvedCopy() throws {
        let track = try firstLibraryTrack()

        let copy = try XCTUnwrap(track.copy(), "could not resolve a copy")

        XCTAssertEqual(copy.scriptingClassCode, track.scriptingClassCode)
        XCTAssertNotNil(copy.scriptingClassCode, "a nil class code would make every track look ratable")
    }

    /// Only meaningful while a catalog track is playing, so it steps aside otherwise
    func testAPlayingCatalogTrackIsRecognised() throws {
        let iTunes = try XCTUnwrap(iTunesRadioStation.shared.iTunes, "Music isn't running")
        let playing = try XCTUnwrap(iTunes.currentTrackCopy, "nothing is playing")
        try XCTSkipUnless(playing.scriptingClassCode == MusicTrackClass.urlTrack,
                          "the playing track is not an Apple Music catalog track")

        XCTAssertTrue(playing.isCatalogStream)
        XCTAssertNotEqual(playing.scriptingClassCode, MusicTrackClass.fileTrack)
    }

}
