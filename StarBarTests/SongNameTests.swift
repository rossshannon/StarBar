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
        XCTAssertEqual(core("The Son of Flynn - From \"TRON: Legacy\"/Score"), "the son of flynn")
        XCTAssertEqual(core("My Heart Will Go On - From the Motion Picture Titanic"), "my heart will go on")
    }

    func testFromIsOnlyASoundtrackCreditWhenItNamesOne() {
        XCTAssertEqual(core("Song (From The Heart)"), "song from the heart")
    }

    func testAPartOfAnAlbumIsAGenericTitle() {
        XCTAssertTrue(SongName.isGenericTitle(core("Intro")))
        XCTAssertTrue(SongName.isGenericTitle(core("Interlude 2")))
        XCTAssertTrue(SongName.isGenericTitle(core("Untitled")))
        XCTAssertTrue(SongName.isGenericTitle(core("Skit (Explicit)")))
        XCTAssertFalse(SongName.isGenericTitle(core("Intro to Love")))
        XCTAssertFalse(SongName.isGenericTitle(core("Clocks")))
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
        XCTAssertEqual(title.withNames, ["rihanna"])
    }

    func testWithIsKeptApartFromFeat() {
        // "(With Strings)" is an arrangement as often as "(with Justin Bieber)" is a guest;
        // the matcher decides by the other track's credits
        XCTAssertEqual(SongName.title("Yesterday (With Strings)").withNames, ["strings"])
        XCTAssertEqual(SongName.title("Stay (with Justin Bieber)").withNames, ["justin bieber"])
        XCTAssertEqual(SongName.title("Wake Me Up (feat. Aloe Blacc)").withNames, [])
    }

    func testABareFeatNeedsItsDot() {
        // Without one, these are words of the title
        XCTAssertEqual(core("A Feat of Strength"), "a feat of strength")
        XCTAssertEqual(core("Fifty Ft Woman"), "fifty ft woman")
        XCTAssertEqual(core("Song feat. Someone Else"), "song")
        XCTAssertEqual(core("Song ft. Someone Else"), "song")
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
        XCTAssertEqual(versions("Clocks - Live in Sydney"), ["live:sydney"])
        XCTAssertEqual(core("Clocks - Live in Sydney"), "clocks")
    }

    func testRemixesAndDubsAreVersions() {
        XCTAssertEqual(versions("Strawberry Swing - Frankmusik Remix"), ["remix:frankmusik"])
        XCTAssertEqual(versions("Teardrop - Mad Professor Mazaruni Dub"), ["remix:mad professor mazaruni"])
        XCTAssertEqual(versions("Strobe (Extended Remix)"), ["remix"], "edition words name nothing")
        XCTAssertEqual(SongName.kinds(of: versions("Strawberry Swing - Frankmusik Remix")), ["remix"])
    }

    func testNumbersNameAVersion() {
        // Two years at one venue, or two takes, are two recordings
        XCTAssertEqual(versions("Song - Live at Wembley 1986"), ["live:wembley 1986"])
        XCTAssertEqual(versions("Song (Take 2)"), ["session:2"])
        XCTAssertEqual(versions("Song (Alt. Take 3)"), ["session:3"])
        XCTAssertEqual(versions("Song - Live at Wembley - 2011 Remaster"), ["live:wembley"], "a remaster's year names nothing")
    }

    func testRecordedLiveIsLive() {
        XCTAssertEqual(versions("Song - Recorded Live at Wembley"), ["live:wembley"])
    }

    func testAReRecordingIsAVersion() {
        XCTAssertEqual(versions("Rock of Ages - Re-Recorded"), ["rerecording"])
        XCTAssertEqual(versions("Rock of Ages (Re-Recorded Version)"), ["rerecording"])
        XCTAssertEqual(versions("Rock of Ages (Rerecorded)"), ["rerecording"])
        XCTAssertEqual(core("Rock of Ages - Re-Recorded"), "rock of ages")
    }

    // MARK: - The same recording

    func testANamedVersionIsOnlyTheSameName() {
        // Two remixers, or two nights, are two recordings
        XCTAssertFalse(SongName.isSameRecording("Strobe - Michael Woods Remix", on: "", as: "Strobe (Sebastien Leger Remix)", on: ""))
        XCTAssertTrue(SongName.isSameRecording("Strobe - Michael Woods Remix", on: "", as: "Strobe (Michael Woods Remix)", on: ""))
        XCTAssertFalse(SongName.isSameRecording("Clocks - Live in Sydney", on: "", as: "Clocks (Live at Glastonbury 2011)", on: ""))
        XCTAssertFalse(SongName.isSameRecording("Song - Live at Wembley 1986", on: "Live Anthology",
                                                as: "Song (Live at Wembley 1987)", on: "Live Anthology"),
                       "named differently, even on one release")
        XCTAssertFalse(SongName.isSameRecording("Song (Take 1)", on: "", as: "Song (Take 2)", on: ""))
        XCTAssertTrue(SongName.isSameRecording("Song - Recorded Live at Wembley", on: "", as: "Song (Live at Wembley)", on: ""))
    }

    func testTwoPlainPerformancesAreOneOnlyOnOneRelease() {
        // Nothing else says which night or which remixer
        XCTAssertTrue(SongName.isSameRecording("Clocks - Live", on: "Viva la Vida (Deluxe Edition)",
                                               as: "Clocks (Live)", on: "Viva la Vida"))
        XCTAssertFalse(SongName.isSameRecording("Clocks - Live", on: "Live 2003", as: "Clocks (Live)", on: "Live in Buenos Aires"))
        XCTAssertFalse(SongName.isSameRecording("Clocks", on: "Live in Sydney", as: "Clocks", on: "Live in Buenos Aires"))
        XCTAssertFalse(SongName.isSameRecording("Clocks - Live", on: "", as: "Clocks (Live)", on: ""), "no album says nothing")
        XCTAssertTrue(SongName.isSameRecording("Song - Instrumental", on: "Single", as: "Song (Instrumental)", on: "Album"),
                      "an instrumental is not a performance of its own")
    }

    func testANamedPerformanceFindsThePlainOneOnTheSameRelease() {
        // Spotify names live tracks by venue and date where Music mostly says "(Live)"
        XCTAssertTrue(SongName.isSameRecording("Hotel California - Live On MTV, 1994", on: "Hell Freezes Over (Remaster 2018)",
                                               as: "Hotel California (Live)", on: "Hell Freezes Over"))
        XCTAssertFalse(SongName.isSameRecording("Hotel California - Live On MTV, 1994", on: "Hell Freezes Over",
                                                as: "Hotel California (Live)", on: "Eagles Live"))
    }

    func testTheSameReleaseIsTheSameAlbumOnceItsEditionIsOff() {
        XCTAssertTrue(SongName.isSameRelease("Hell Freezes Over (Remaster 2018)", "Hell Freezes Over"))
        XCTAssertTrue(SongName.isSameRelease("Wonderful Life - Single", "Wonderful Life"))
        XCTAssertFalse(SongName.isSameRelease("Live", "Live at Wembley"))
        XCTAssertFalse(SongName.isSameRelease("", ""))
    }

    func testANamedVersionCanBeNamedByTheOtherTracksAlbum() {
        XCTAssertTrue(SongName.isSameRecording("Clocks - Live in Sydney", on: "", as: "Clocks", on: "Live in Sydney"))
        XCTAssertTrue(SongName.isSameRecording("Clocks - Live in Sydney", on: "", as: "Clocks (Live)", on: "Live in Sydney"))
        XCTAssertFalse(SongName.isSameRecording("Clocks - Live in Sydney", on: "", as: "Clocks (Live)", on: "Prospekt's March"),
                       "a plain (Live) is not the Sydney performance")
        XCTAssertTrue(SongName.isSameRecording("Idioteque - Live", on: "I Might Be Wrong: Live Recordings",
                                               as: "Idioteque", on: "I Might Be Wrong: Live Recordings"))
    }

    func testKindsOfRecordingHaveToAgree() {
        XCTAssertFalse(SongName.isSameRecording("Idioteque", on: "Kid A", as: "Idioteque", on: "I Might Be Wrong: Live Recordings"))
        XCTAssertFalse(SongName.isSameRecording("Rock of Ages - Re-Recorded", on: "", as: "Rock of Ages", on: "Pyromania"))
        XCTAssertTrue(SongName.isSameRecording("Bohemian Rhapsody - Remastered 2011", on: "", as: "Bohemian Rhapsody", on: "A Night at the Opera"))
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
        XCTAssertEqual(SongName.artists("Run-DMC vs. Jason Nevins"), ["run dmc", "jason nevins", "run dmc vs jason nevins"])
        XCTAssertEqual(SongName.artists("Eminem; Rihanna"), ["eminem", "rihanna", "eminem rihanna"])
    }

    func testALeadArtistOfOneWordIsKept() {
        // Dropping it lost Queen's "Under Pressure" (2026-10-29)
        XCTAssertTrue(SongName.artists("Queen & David Bowie").contains("queen"))
        XCTAssertTrue(SongName.artists("Rihanna, Kanye West & Paul McCartney").contains("rihanna"))
        XCTAssertTrue(SongName.artists("Drake & 21 Savage").contains("drake"))
    }

    func testACommaBeforeTheCanBeInsideANameOrStartTheNext() {
        XCTAssertEqual(SongName.artists("Tyler, The Creator"), ["tyler the creator"])
        let tyler = SongName.artists("Tyler, The Creator, Kali Uchis")
        XCTAssertTrue(tyler.contains("tyler the creator"))
        XCTAssertTrue(tyler.contains("kali uchis"))
        let metro = SongName.artists("Metro Boomin, The Weeknd & 21 Savage")
        XCTAssertTrue(metro.isSuperset(of: ["metro boomin", "weeknd", "21 savage"]), "\(metro)")
    }

    func testAGuestIsStillOneOfTheCredits() {
        // For a "(with ...)" on the other side to be checked against
        XCTAssertTrue(SongName.credits("Calvin Harris feat. Rihanna").contains("rihanna"))
        XCTAssertTrue(SongName.credits("Calvin Harris feat. Rihanna").contains("calvin harris"))
    }

    func testAGuestIsNotOneOfTheCreditsOwnArtists() {
        // On their own, a guest would find their own song of the same title
        XCTAssertFalse(SongName.artists("Calvin Harris feat. Rihanna").contains("rihanna"))
        XCTAssertFalse(SongName.artists("Aaliyah ft. Timbaland").contains("timbaland"))
        XCTAssertEqual(SongName.artists("Ella Fitzgerald with Chick Webb & His Orchestra"),
                       ["ella fitzgerald", "ella fitzgerald with chick webb and his orchestra"])
    }

    func testABandNamedLikeAListStaysOneName() {
        // Split, these would let a band called Earth match Earth, Wind & Fire
        XCTAssertEqual(SongName.artists("Earth, Wind & Fire"), ["earth wind and fire"])
        XCTAssertEqual(SongName.artists("Simon & Garfunkel"), ["simon and garfunkel"])
        XCTAssertEqual(SongName.artists("Florence + The Machine"), ["florence and the machine"])
        XCTAssertEqual(SongName.artists("Crosby, Stills, Nash & Young"), ["crosby stills nash and young"])
        XCTAssertEqual(SongName.artists("AC/DC"), ["ac dc"])
    }

    func testAGuestIsSplitOffEvenAsOneWord() {
        XCTAssertEqual(SongName.artists("Drake feat. Rihanna"), ["drake", "drake feat rihanna"])
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
        XCTAssertEqual(SongName.albumVersions("Live 2003"), ["live"])
        XCTAssertEqual(SongName.albumVersions("Live 1975-85"), ["live"])
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
