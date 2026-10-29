//
//  SongNameTests.swift
//  StarBarTests
//
//  Folding Spotify's and Music's names for a song down to what they agree on. Pure, so it
//  runs anywhere.
//

import XCTest
@testable import StarBar

final class SongNameTests: XCTestCase {

    private func core(_ title: String) -> String {
        return SongName.title(title).core
    }

    private func versions(_ title: String) -> Set<String> {
        return SongName.title(title).versions
    }

    // MARK: - Folding text

    func testCaseAndAccentsFoldAway() {
        XCTAssertEqual(SongName.artist("Björk"), "bjork")
        XCTAssertEqual(SongName.artist("Sigur Rós"), "sigur ros")
        XCTAssertEqual(SongName.artist("BLACK"), "black")
    }

    func testLettersUnicodeDoesNotTakeApartFoldToo() {
        // ø and ß have no accent to strip; they are letters of their own
        XCTAssertEqual(SongName.artist("Mø"), "mo")
        XCTAssertEqual(SongName.artist("Die Ärzte ß"), "die arzte ss")
    }

    func testCurlyAndStraightApostrophesAreTheSame() {
        XCTAssertEqual(core("Don\u{2019}t Stop Me Now"), core("Don't Stop Me Now"))
        XCTAssertEqual(core("Don't Stop Me Now"), "dont stop me now")
    }

    func testAmpersandAndPlusReadAsAnd() {
        XCTAssertEqual(SongName.artist("Florence + The Machine"), SongName.artist("Florence and the Machine"))
        XCTAssertEqual(SongName.artist("Simon & Garfunkel"), "simon and garfunkel")
    }

    func testALeadingTheComesOffAnArtist() {
        XCTAssertEqual(SongName.artist("The Cranberries"), SongName.artist("Cranberries"))
    }

    func testATheSortedToTheEndComesOffToo() {
        // As the measured library has it
        XCTAssertEqual(SongName.artist("Cure, The"), "cure")
        XCTAssertEqual(SongName.artists("Cure, The"), ["cure"])
    }

    func testPtReadsAsPart() {
        XCTAssertEqual(core("Pt. 2"), core("Part 2"))
    }

    // MARK: - Edition words are dropped

    func testSpotifysDashedRemasterIsDropped() {
        XCTAssertEqual(core("Bohemian Rhapsody - Remastered 2011"), "bohemian rhapsody")
        XCTAssertEqual(core("Don\u{2019}t Stop Me Now - 2011 Remaster"), "dont stop me now")
        XCTAssertEqual(versions("Bohemian Rhapsody - Remastered 2011"), [])
    }

    func testBracketedEditionsAreDropped() {
        XCTAssertEqual(core("One (Remastered 2024)"), "one")
        XCTAssertEqual(core("Move On Up (Single Edit)"), "move on up")
        XCTAssertEqual(core("Rock Lobster (Re-Mastered)"), "rock lobster")
        XCTAssertEqual(core("Song (Bonus Track)"), "song")
    }

    func testEditsAndSingleVersionsAreTheSameSong() {
        XCTAssertEqual(core("Halo - Radio Edit"), "halo")
        XCTAssertEqual(core("I Will Survive - Single Version"), "i will survive")
        XCTAssertEqual(core("Take On Me - 1985 12\" Version"), "take on me")
        XCTAssertEqual(versions("Take On Me - 1985 12\" Version"), [])
    }

    func testAMixNamedOnlyByYearOrFormatIsAnEdition() {
        // The Beatles' anniversary remixes, and mono or stereo mixes, are the same song
        XCTAssertEqual(core("Come Together - 2019 Mix"), "come together")
        XCTAssertEqual(versions("Come Together - 2019 Mix"), [])
        XCTAssertEqual(versions("Firestarter - Single Mix"), [])
    }

    func testASoundtrackCreditIsDropped() {
        XCTAssertEqual(core("Lose Yourself - From \"8 Mile\" Soundtrack"), "lose yourself")
    }

    func testFeaturedArtistsComeOffTheTitle() {
        let title = SongName.title("Wake Me Up (feat. Aloe Blacc)")
        XCTAssertEqual(title.core, "wake me up")
        XCTAssertEqual(title.featured, ["aloe blacc"])
    }

    func testAFeaturedCreditAndAnEditionTogether() {
        let title = SongName.title("Get Lucky (feat. Pharrell Williams) [Radio Edit]")
        XCTAssertEqual(title.core, "get lucky")
        XCTAssertEqual(title.versions, [])
        XCTAssertEqual(title.featured, ["pharrell williams"])
    }

    func testADashedWithCreditIsAFeature() {
        let title = SongName.title("Stay - with Rihanna")
        XCTAssertEqual(title.core, "stay")
        XCTAssertEqual(title.featured, ["rihanna"])
    }

    // MARK: - What is part of the name stays

    func testABracketThatIsPartOfTheNameStays() {
        XCTAssertEqual(core("Street Spirit (Fade Out)"), "street spirit fade out")
        XCTAssertEqual(core("(Don't Fear) The Reaper"), "dont fear the reaper")
        XCTAssertEqual(core("Hurt (Quiet)"), "hurt quiet")
    }

    func testADashThatIsPartOfTheNameStays() {
        XCTAssertEqual(core("Lights, Camera, Action! - Studiopolis Zone Act 1"),
                       "lights camera action studiopolis zone act 1")
    }

    func testWithInsideATitleIsNotAFeature() {
        XCTAssertEqual(core("Stay With Me"), "stay with me")
    }

    // MARK: - A different recording is kept apart

    func testLiveIsAVersion() {
        XCTAssertEqual(versions("One (Live)"), ["live"])
        XCTAssertEqual(versions("Clocks - Live in Sydney"), ["live"])
        XCTAssertEqual(core("Clocks - Live in Sydney"), "clocks")
    }

    func testRemixesAndDubsAreVersions() {
        XCTAssertEqual(versions("Strawberry Swing - Frankmusik Remix"), ["remix"])
        XCTAssertEqual(versions("Teardrop - Mad Professor Mazaruni Dub"), ["remix"])
    }

    func testAcousticDemoAndInstrumentalAreVersions() {
        XCTAssertEqual(versions("Everlong - Acoustic Version"), ["acoustic"])
        XCTAssertEqual(versions("Song (Original Demo)"), ["demo"])
        XCTAssertEqual(versions("Song [Instrumental]"), ["instrumental"])
    }

    func testANamedVersionTheRulesDontKnowIsKeptWhole() {
        // So it only ever matches itself: an unfamiliar word costs a match, never makes a
        // wrong one
        XCTAssertEqual(versions("Kota (Salsa Version)"), ["variant:salsa version"])
        XCTAssertEqual(versions("Bad (Matt Butcher Mix)"), ["variant:matt butcher mix"])
    }

    // MARK: - Artists

    func testACreditNamesEachArtistAndItsWhole() {
        XCTAssertEqual(SongName.artists("Calvin Harris & Dua Lipa"), ["calvin harris", "dua lipa", "calvin harris and dua lipa"])
        XCTAssertTrue(SongName.artists("Cave, Nick & Warren Ellis").contains("warren ellis"))
        XCTAssertTrue(SongName.artists("Calvin Harris feat. Rihanna").contains("rihanna"))
        XCTAssertTrue(SongName.artists("Aaliyah ft. Timbaland").contains("timbaland"))
    }

    func testABandNamedLikeAListStaysOneName() {
        // Split, these would let a band called Earth match Earth, Wind & Fire
        XCTAssertEqual(SongName.artists("Earth, Wind & Fire"), ["earth wind and fire"])
        XCTAssertEqual(SongName.artists("Simon & Garfunkel"), ["simon and garfunkel"])
        XCTAssertEqual(SongName.artists("Florence + The Machine"), ["florence and the machine"])
        XCTAssertEqual(SongName.artists("Crosby, Stills, Nash & Young"), ["crosby stills nash and young"])
    }

    func testAFeaturedArtistIsSplitOffEvenAsOneWord() {
        XCTAssertEqual(SongName.artists("Drake feat. Rihanna"), ["drake", "rihanna", "drake feat rihanna"])
    }

    // MARK: - Albums

    func testAlbumEditionsAreDropped() {
        XCTAssertEqual(SongName.album("A Night At The Opera (2011 Remaster)"), "a night at the opera")
        XCTAssertEqual(SongName.album("Bad (25th Anniversary Edition)"), "bad")
        XCTAssertEqual(SongName.album("Abbey Road (Super Deluxe Edition)"), "abbey road")
    }

    func testASingleStaysASingle() {
        // So the copy on the album Spotify names wins over the single it came out on
        XCTAssertEqual(SongName.album("Wonderful Life - Single"), "wonderful life single")
    }

    func testALiveOrRemixAlbumMarksItsTracks() {
        XCTAssertEqual(SongName.albumVersions("I Might Be Wrong: Live Recordings"), ["live"])
        XCTAssertEqual(SongName.albumVersions("Live at the Fillmore West"), ["live"])
        XCTAssertEqual(SongName.albumVersions("Where the Light Is - John Mayer Live In Los Angeles"), ["live"])
        XCTAssertEqual(SongName.albumVersions("MTV Unplugged In New York"), ["live"])
        XCTAssertEqual(SongName.albumVersions("Parklive (Live)"), ["live"])
        XCTAssertEqual(SongName.albumVersions("World Wide Live"), ["live"])
        XCTAssertEqual(SongName.albumVersions("Tournament Rematch: Unreal Tournament Remixed"), ["remix"])
        XCTAssertEqual(SongName.albumVersions("Strobe (Remixes)"), ["remix"])
    }

    func testAnAlbumNamedAfterASongIsNotLiveForSayingLive() {
        XCTAssertEqual(SongName.albumVersions("Live to Tell - Single"), [])
        XCTAssertEqual(SongName.albumVersions("Live Forever"), [])
        XCTAssertEqual(SongName.albumVersions("Alive 1997"), [])
        XCTAssertEqual(SongName.albumVersions("Kid A"), [])
    }

    func testATracksVersionsComeFromItsTitleAndItsAlbumTogether() {
        XCTAssertEqual(SongName.versions(of: "Black - Live at GTE Amphitheater", on: "Live On Two Legs"), ["live"])
        XCTAssertEqual(SongName.versions(of: "Black (Live)", on: "Rearviewmirror"), ["live"])
        XCTAssertEqual(SongName.versions(of: "Idioteque", on: "I Might Be Wrong: Live Recordings"), ["live"])
        XCTAssertEqual(SongName.versions(of: "Idioteque", on: "Kid A"), [])
    }

}
