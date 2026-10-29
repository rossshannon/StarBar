//
//  SongMatcherTests.swift
//  StarBarTests
//
//  Finding a Spotify song among the user's own Music library. The library tracks here are
//  real ones, as Music named them in the library measured on 2026-10-28. Pure, so it runs
//  anywhere.
//

import XCTest
@testable import StarBar

final class SongMatcherTests: XCTestCase {

    private var nextID = 0

    private func song(_ name: String, by artist: String, on album: String = "", albumArtist: String = "",
                      length: Double? = nil, rating: Int = 0, computed: Bool = false, played: Int = 0) -> LibrarySong {
        nextID += 1
        return LibrarySong(persistentID: String(format: "%016lX", nextID), name: name, artist: artist,
                           albumArtist: albumArtist, album: album, duration: length, rating: rating,
                           isRatingComputed: computed, playedCount: played)
    }

    private func query(_ name: String, by artist: String, on album: String = "", length: Double? = nil) -> SongQuery {
        return SongQuery(name: name, artist: artist, album: album, duration: length)
    }

    // MARK: - The same song

    func testARemasterFindsTheOriginal() {
        let original = song("Bohemian Rhapsody", by: "Queen", on: "A Night at the Opera")
        let matcher = SongMatcher(library: [original])

        XCTAssertEqual(matcher.match(for: query("Bohemian Rhapsody - Remastered 2011", by: "Queen")), original)
    }

    func testASingleEditFindsTheAlbumVersion() {
        // The two are 2:46 and 8:49: length never decides whether it is the same song
        let album = song("Move On Up", by: "Curtis Mayfield", length: 529)
        let matcher = SongMatcher(library: [album])

        XCTAssertEqual(matcher.match(for: query("Move On Up - Single Edit", by: "Curtis Mayfield", length: 166)), album)
    }

    func testARadioEditFindsTheSongWithItsFeaturedArtists() {
        let album = song("Get Lucky (feat. Pharrell Williams and Nile Rodgers)", by: "Daft Punk", on: "Random Access Memories")
        let matcher = SongMatcher(library: [album])

        XCTAssertEqual(matcher.match(for: query("Get Lucky - Radio Edit", by: "Daft Punk")), album)
    }

    func testTheBandWithAndWithoutTheIsTheSame() {
        let zombie = song("Zombie", by: "Cranberries")
        let matcher = SongMatcher(library: [zombie])

        XCTAssertEqual(matcher.match(for: query("Zombie", by: "The Cranberries")), zombie)
    }

    func testOneArtistOfAJointCreditFindsIt() {
        // Spotify names one artist; the library credits two, surname first
        let track = song("Destined For Great Things", by: "Cave, Nick & Warren Ellis")
        let matcher = SongMatcher(library: [track])

        XCTAssertEqual(matcher.match(for: query("Destined For Great Things", by: "Warren Ellis")), track)
    }

    func testTheAlbumArtistCountsAsACredit() {
        let track = song("Theme", by: "London Session Orchestra", albumArtist: "Composer Name")
        let matcher = SongMatcher(library: [track])

        XCTAssertEqual(matcher.match(for: query("Theme", by: "Composer Name")), track)
    }

    func testAFeaturedArtistOnSpotifyCanBeTheLibrarysArtist() {
        let track = song("Collaboration", by: "Second Artist")
        let matcher = SongMatcher(library: [track])

        XCTAssertEqual(matcher.match(for: query("Collaboration (feat. Second Artist)", by: "First Artist")), track)
    }

    // MARK: - A different song

    func testTheSameTitleByAnotherArtistIsADifferentSong() {
        // Five artists in the measured library have a song called "One"
        let matcher = SongMatcher(library: [song("One", by: "U2"), song("One", by: "Aimee Mann")])

        XCTAssertNil(matcher.match(for: query("One", by: "Metallica")))
    }

    func testALiveVersionIsNotTheStudioOne() {
        let studio = song("One", by: "Metallica")
        let live = song("One (Live)", by: "Metallica")
        let matcher = SongMatcher(library: [studio, live])

        XCTAssertEqual(matcher.copies(of: query("One", by: "Metallica")), [studio])
        XCTAssertEqual(matcher.copies(of: query("One - Live", by: "Metallica")), [live])
    }

    func testARemixIsNotTheOriginal() {
        let matcher = SongMatcher(library: [song("Strawberry Swing", by: "Coldplay")])

        XCTAssertNil(matcher.match(for: query("Strawberry Swing - Frankmusik Remix", by: "Coldplay")))
    }

    func testATrackOnALiveAlbumIsNotTheStudioOne() {
        // Both in the measured library, and neither title says which is live. The live copy
        // is the one rated, so only its album keeps it out.
        let studio = song("Idioteque", by: "Radiohead", on: "Kid A", length: 309)
        let live = song("Idioteque", by: "Radiohead", on: "I Might Be Wrong: Live Recordings", length: 265, rating: 100)
        let matcher = SongMatcher(library: [studio, live])

        XCTAssertEqual(matcher.match(for: query("Idioteque", by: "Radiohead")), studio)
        XCTAssertEqual(matcher.match(for: query("Idioteque", by: "Radiohead", on: "I Might Be Wrong: Live Recordings")), live)
        XCTAssertEqual(Set(matcher.copies(of: query("Idioteque", by: "Radiohead")).map { $0.persistentID }),
                       [studio.persistentID, live.persistentID], "the names alone can't tell them apart")
    }

    func testATrackOnARemixAlbumIsNotTheOriginal() {
        // Measured 2026-10-29: Spotify credits this remix to the original's composer and says
        // nothing in its title. It runs 373 s against the original's 251.
        let original = song("Foregone Destruction", by: "Michiel Van Den Bos", on: "Unreal Tournament", length: 251, rating: 60)
        let matcher = SongMatcher(library: [original])

        XCTAssertNil(matcher.match(for: query("Foregone Destruction", by: "Michiel van den Bos",
                                              on: "Tournament Rematch: Unreal Tournament Remixed", length: 373)))
        XCTAssertEqual(matcher.match(for: query("Foregone Destruction", by: "Michiel van den Bos", on: "Unreal Tournament")), original)
    }

    func testAnArtistNameIsNeverSplitOnTheQuerySide() {
        // "Earth" is a band of its own; splitting Spotify's name would let it find this
        let matcher = SongMatcher(library: [song("September", by: "Earth, Wind & Fire")])

        XCTAssertNil(matcher.match(for: query("September", by: "Earth")))
    }

    func testABracketThatIsPartOfTheNameMustBeThere() {
        // A miss the rules accept: loosening them would cost wrong matches elsewhere
        let matcher = SongMatcher(library: [song("Street Spirit (Fade Out)", by: "Radiohead")])

        XCTAssertNil(matcher.match(for: query("Street Spirit", by: "Radiohead")))
        XCTAssertNotNil(matcher.match(for: query("Street Spirit (Fade Out)", by: "Radiohead")))
    }

    func testAnUnfamiliarVersionOnlyMatchesItself() {
        let matcher = SongMatcher(library: [song("Kota", by: "Bonobo")])

        XCTAssertNil(matcher.match(for: query("Kota (Salsa Version)", by: "Bonobo")))
    }

    func testAnEmptyTitleOrArtistMatchesNothing() {
        let matcher = SongMatcher(library: [song("", by: "Nobody"), song("Untitled", by: "")])

        XCTAssertNil(matcher.match(for: query("", by: "Nobody")))
        XCTAssertNil(matcher.match(for: query("Untitled", by: "")))
    }

    // MARK: - Choosing between copies

    func testTheCopyOnTheNamedAlbumComesFirst() {
        // Measured: 3 stars on ABBA Gold, 1½ on The Complete Singles Collection
        let singles = song("Thank You For The Music", by: "ABBA", on: "The Complete Singles Collection", rating: 30)
        let gold = song("Thank You For The Music", by: "ABBA", on: "ABBA Gold - Greatest Hits", rating: 60)
        let matcher = SongMatcher(library: [singles, gold])

        XCTAssertEqual(matcher.match(for: query("Thank You for the Music", by: "ABBA", on: "ABBA Gold")), gold)
        XCTAssertEqual(matcher.match(for: query("Thank You for the Music", by: "ABBA", on: "The Complete Singles Collection")), singles)
    }

    func testTheAlbumBeatsTheSingleItCameOutOn() {
        let single = song("Wonderful Life", by: "BLACK", on: "Wonderful Life - Single", rating: 60, played: 50)
        let album = song("Wonderful Life", by: "BLACK", on: "Wonderful Life", rating: 100, played: 5)
        let matcher = SongMatcher(library: [single, album])

        XCTAssertEqual(matcher.match(for: query("Wonderful Life", by: "Black", on: "Wonderful Life (Deluxe Edition)")), album)
    }

    func testACopyTheUserRatedBeatsOneTheyDidnt() {
        let unrated = song("Zombie", by: "The Cranberries", on: "Greatest Hits", played: 40)
        let computed = song("Zombie", by: "The Cranberries", on: "Stars: The Best of 1992-2002", rating: 80, computed: true, played: 30)
        let rated = song("Zombie", by: "The Cranberries", on: "No Need to Argue", rating: 60, played: 1)
        let matcher = SongMatcher(library: [unrated, computed, rated])

        XCTAssertEqual(matcher.match(for: query("Zombie", by: "The Cranberries", on: "Something Else")), rated)
    }

    func testThenTheNearestLengthThenTheMostPlayed() {
        let short = song("Kota", by: "Bonobo", on: "A", length: 194, played: 1)
        let long = song("Kota", by: "Bonobo", on: "B", length: 325, played: 9)
        let matcher = SongMatcher(library: [short, long])

        XCTAssertEqual(matcher.match(for: query("Kota", by: "Bonobo", length: 320)), long)
        XCTAssertEqual(matcher.match(for: query("Kota", by: "Bonobo", length: 200)), short)
        XCTAssertEqual(matcher.match(for: query("Kota", by: "Bonobo")), long)
    }

    func testTheChoiceDoesNotDependOnTheLibrarysOrder() {
        let first = song("Hallelujah", by: "Jeff Buckley", on: "Grace")
        let second = song("Hallelujah", by: "Jeff Buckley", on: "Grace")

        XCTAssertEqual(SongMatcher(library: [first, second]).match(for: query("Hallelujah", by: "Jeff Buckley")),
                       SongMatcher(library: [second, first]).match(for: query("Hallelujah", by: "Jeff Buckley")))
    }

    func testEveryCopyIsListed() {
        let copies = [song("Hallelujah", by: "Jeff Buckley", on: "Grace"),
                      song("Hallelujah", by: "Jeff Buckley", on: "Live at Sin-é"),
                      song("Hallelujah", by: "Jeff Buckley", on: "So Real")]
        let matcher = SongMatcher(library: copies + [song("Hallelujah", by: "Leonard Cohen")])

        XCTAssertEqual(Set(matcher.copies(of: query("Hallelujah", by: "Jeff Buckley")).map { $0.persistentID }),
                       Set(copies.map { $0.persistentID }))
    }

    func testAlbumCloseness() {
        XCTAssertEqual(SongMatcher.closeness(of: "abba gold", to: "abba gold"), 0)
        XCTAssertEqual(SongMatcher.closeness(of: "abba gold", to: "abba gold greatest hits"), 1)
        XCTAssertEqual(SongMatcher.closeness(of: "the complete singles collection", to: "abba gold"), 2)
        XCTAssertEqual(SongMatcher.closeness(of: "", to: "abba gold"), 2)
    }

}
