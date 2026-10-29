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

    func testAOneWordLeadOfAJointCreditFindsIt() {
        // Dropping single words from a list lost these (2026-10-29)
        let underPressure = song("Under Pressure", by: "Queen & David Bowie")
        let creepin = song("Creepin'", by: "Metro Boomin, The Weeknd & 21 Savage")
        let matcher = SongMatcher(library: [underPressure, creepin])

        XCTAssertEqual(matcher.match(for: query("Under Pressure", by: "Queen")), underPressure)
        XCTAssertEqual(matcher.match(for: query("Under Pressure", by: "David Bowie")), underPressure)
        XCTAssertEqual(matcher.match(for: query("Creepin'", by: "Metro Boomin")), creepin)
        XCTAssertEqual(matcher.match(for: query("Creepin'", by: "21 Savage")), creepin)
        // One word after the lead could as well be a backing band: see
        // testABackingBandIsNotTheArtist. Missing The Weeknd here is the price.
        XCTAssertNil(matcher.match(for: query("Creepin'", by: "The Weeknd")))
    }

    func testABackingBandIsNotTheArtist() {
        // The Band's own "Tears of Rage" is another recording from the one they backed Bob
        // Dylan on (the third review, 2026-10-29)
        let basement = song("Tears of Rage", by: "Bob Dylan & The Band", on: "The Basement Tapes")
        let powerOfLove = song("The Power of Love", by: "Huey Lewis & The News")
        let matcher = SongMatcher(library: [basement, powerOfLove])

        XCTAssertNil(matcher.match(for: query("Tears of Rage", by: "The Band", on: "Music from Big Pink")))
        XCTAssertNil(matcher.match(for: query("The Power of Love", by: "The News")))
        XCTAssertEqual(matcher.match(for: query("Tears of Rage", by: "Bob Dylan", on: "The Basement Tapes")), basement)
        XCTAssertEqual(matcher.match(for: query("Tears of Rage", by: "Bob Dylan & The Band", on: "The Basement Tapes")), basement)
        XCTAssertEqual(matcher.match(for: query("The Power of Love", by: "Huey Lewis")), powerOfLove)
    }

    func testTheAlbumArtistCountsAsACredit() {
        let track = song("Theme", by: "London Session Orchestra", albumArtist: "Composer Name")
        let matcher = SongMatcher(library: [track])

        XCTAssertEqual(matcher.match(for: query("Theme", by: "Composer Name")), track)
    }

    func testAGuestAloneIsNotACredit() {
        // Spotify's song features the library's artist, or the other way round. On their
        // own, a guest's name would find their own song of the same title, and the user's
        // rating would go on it.
        let theirOwn = song("Collaboration", by: "Guest Artist")
        let featuring = song("Collaboration (feat. Guest Artist)", by: "Main Artist")
        let credited = song("Collaboration", by: "Main Artist feat. Guest Artist")

        XCTAssertNil(SongMatcher(library: [theirOwn]).match(for: query("Collaboration (feat. Guest Artist)", by: "Main Artist")))
        XCTAssertNil(SongMatcher(library: [featuring]).match(for: query("Collaboration", by: "Guest Artist")))
        XCTAssertNil(SongMatcher(library: [credited]).match(for: query("Collaboration", by: "Guest Artist")))
        XCTAssertEqual(SongMatcher(library: [theirOwn, featuring, credited])
            .copies(of: query("Collaboration (feat. Guest Artist)", by: "Main Artist")).count, 2, "the main artist finds both")
    }

    // MARK: - A different song

    func testAnIntroOnAnotherAlbumIsAnotherTrack() {
        // Every album can have one, whatever its length
        let intro = song("Intro", by: "The xx", on: "xx", length: 127)
        let matcher = SongMatcher(library: [intro])

        XCTAssertNil(matcher.match(for: query("Intro", by: "The xx", on: "Coexist", length: 60)))
        XCTAssertNil(matcher.match(for: query("Intro", by: "The xx", on: "Coexist", length: 131)), "close in length is no help")
        XCTAssertNil(matcher.match(for: query("Intro", by: "The xx", length: 127)), "no album says nothing")
        XCTAssertEqual(matcher.match(for: query("Intro", by: "The xx", on: "xx (Deluxe Edition)", length: 127)), intro)
    }

    func testAnIntroOnAnEditionTheRulesDontKnowIsTheSameTrack() {
        let intro = song("Intro", by: "The xx", on: "Coexist (Limited Edition)")

        XCTAssertEqual(SongMatcher(library: [intro]).match(for: query("Intro", by: "The xx", on: "Coexist")), intro)
    }

    func testAnIntroOnAnotherMarketsOrAnExpandedEditionIsTheSameTrack() {
        // Each was another release to the rules before the fourth review (2026-10-29)
        let japan = song("Intro", by: "The xx", on: "xx (Japan Version)")
        let expanded = song("Intro", by: "The xx", on: "Coexist (Expanded & Remastered)")

        XCTAssertEqual(SongMatcher(library: [japan]).match(for: query("Intro", by: "The xx", on: "xx")), japan)
        XCTAssertEqual(SongMatcher(library: [expanded]).match(for: query("Intro", by: "The xx", on: "Coexist")), expanded)
    }

    func testAFilmCueFindsItsScoreWhicheverWayTheSoundtrackIsCredited() {
        let spiderMan = song("Main Titles", by: "Danny Elfman", on: "Spider-Man")
        let bladeRunner = song("End Titles", by: "Vangelis", on: "Blade Runner: Original Motion Picture Soundtrack")

        XCTAssertEqual(SongMatcher(library: [spiderMan])
            .match(for: query("Main Titles", by: "Danny Elfman", on: "Spider-Man (Original Motion Picture Score)")), spiderMan)
        XCTAssertEqual(SongMatcher(library: [bladeRunner])
            .match(for: query("End Titles", by: "Vangelis", on: "Blade Runner (Original Motion Picture Soundtrack)")), bladeRunner)
    }

    func testAFilmCueOnAnotherScoreIsAnotherTrack() {
        let aliens = song("Main Title", by: "James Horner", on: "Aliens")
        let beetlejuice = song("Main Titles", by: "Danny Elfman", on: "Beetlejuice")
        let matcher = SongMatcher(library: [aliens, beetlejuice])

        XCTAssertNil(matcher.match(for: query("Main Title", by: "James Horner", on: "Braveheart (Original Motion Picture Soundtrack)")))
        XCTAssertNil(matcher.match(for: query("Main Titles", by: "Danny Elfman", on: "Sleepy Hollow")))
        XCTAssertEqual(matcher.match(for: query("Main Title", by: "James Horner", on: "Aliens (Original Motion Picture Soundtrack)")), aliens)
    }

    func testLengthNeverRulesACopyOut() {
        // The single and the album version, 4:22 and 15:18, and an edit and the album's
        let harmony = song("Sweet Harmony", by: "The Beloved", on: "Happiness", length: 918)
        let moveOnUp = song("Move On Up", by: "Curtis Mayfield", on: "Curtis", length: 529)
        let matcher = SongMatcher(library: [harmony, moveOnUp])

        XCTAssertEqual(matcher.match(for: query("Sweet Harmony", by: "The Beloved", on: "Sweet Harmony", length: 262)), harmony)
        XCTAssertEqual(matcher.match(for: query("Move On Up - Single Edit", by: "Curtis Mayfield", on: "Move On Up", length: 166)), moveOnUp)
    }

    func testTheSameTitleByAnotherArtistIsADifferentSong() {
        // Five artists in the measured library have a song called "One"
        let matcher = SongMatcher(library: [song("One", by: "U2"), song("One", by: "Aimee Mann")])

        XCTAssertNil(matcher.match(for: query("One", by: "Metallica")))
    }

    func testALiveVersionIsNotTheStudioOne() {
        let studio = song("One", by: "Metallica", on: "...And Justice for All")
        let live = song("One (Live)", by: "Metallica", on: "S&M")
        let matcher = SongMatcher(library: [studio, live])

        XCTAssertEqual(matcher.copies(of: query("One", by: "Metallica")), [studio])
        XCTAssertEqual(matcher.match(for: query("One - Live", by: "Metallica", on: "S&M")), live)
        XCTAssertNil(matcher.match(for: query("One - Live", by: "Metallica", on: "Live Shit: Binge & Purge")),
                     "a plain (Live) on another release is another night")
    }

    func testALiveSongFindsACopyOnlyItsAlbumSaysIsLive() {
        // Spotify can say so in the title where the library says it only in the album's
        // name, as it does for this song, or the other way round
        let studio = song("Idioteque", by: "Radiohead", on: "Kid A", length: 309)
        let live = song("Idioteque", by: "Radiohead", on: "I Might Be Wrong: Live Recordings", length: 265)
        let liveTitled = song("Idioteque (Live)", by: "Radiohead", on: "I Might Be Wrong: Live Recordings")

        XCTAssertEqual(SongMatcher(library: [studio, live])
            .match(for: query("Idioteque - Live", by: "Radiohead", on: "I Might Be Wrong: Live Recordings")), live)
        XCTAssertEqual(SongMatcher(library: [studio, liveTitled])
            .match(for: query("Idioteque", by: "Radiohead", on: "I Might Be Wrong: Live Recordings")), liveTitled)
    }

    func testTwoLiveAlbumsAreTwoRecordings() {
        // Neither title names the night, and the albums are different ones
        let basement = song("Idioteque (Live)", by: "Radiohead", on: "Live From The Basement")
        let sydney = song("Clocks", by: "Coldplay", on: "Live in Sydney")

        XCTAssertNil(SongMatcher(library: [basement])
            .match(for: query("Idioteque", by: "Radiohead", on: "I Might Be Wrong: Live Recordings")))
        XCTAssertNil(SongMatcher(library: [sydney]).match(for: query("Clocks", by: "Coldplay", on: "Live in Buenos Aires")))
    }

    func testTwoLiveReleasesOfOneTourAreTwoRecordings() {
        // One release once the names of the nights were taken off with the edition words
        // (the third review, 2026-10-29)
        let buenosAires = song("Clocks", by: "Coldplay", on: "Tour Anthology (Live in Buenos Aires 2017)")
        let sydney = song("Clocks", by: "Coldplay", on: "Tour Anthology (Live in Sydney 2003)")

        XCTAssertNil(SongMatcher(library: [buenosAires])
            .match(for: query("Clocks", by: "Coldplay", on: "Tour Anthology (Live in Sydney 2003)")))
        XCTAssertEqual(SongMatcher(library: [buenosAires, sydney])
            .match(for: query("Clocks - Live", by: "Coldplay", on: "Tour Anthology (Live in Sydney 2003) [Remastered]")), sydney)
    }

    func testALiveAlbumNamedTwoWaysIsOneRelease() {
        let live = song("Idioteque", by: "Radiohead", on: "I Might Be Wrong: Live Recordings")
        let matcher = SongMatcher(library: [live])

        XCTAssertEqual(matcher.match(for: query("Idioteque - Live", by: "Radiohead", on: "I Might Be Wrong")), live)
        XCTAssertNil(matcher.match(for: query("Idioteque", by: "Radiohead", on: "I Might Be Wrong")),
                     "Spotify says neither its title nor its album is live")
    }

    func testANamedLiveTrackFindsThePlainOneOnTheSameRelease() {
        let copy = song("Hotel California (Live)", by: "Eagles", on: "Hell Freezes Over")
        let matcher = SongMatcher(library: [copy])

        XCTAssertEqual(matcher.match(for: query("Hotel California - Live On MTV, 1994", by: "Eagles",
                                                on: "Hell Freezes Over (Remaster 2018)")), copy)
    }

    func testANamedLiveTrackFindsOneNamedLessOnTheSameRelease() {
        let copy = song("Hotel California (Live on MTV)", by: "Eagles", on: "Hell Freezes Over")
        let matcher = SongMatcher(library: [copy])

        XCTAssertEqual(matcher.match(for: query("Hotel California - Live On MTV, 1994", by: "Eagles",
                                                on: "Hell Freezes Over (Remaster 2018)")), copy)
        XCTAssertNil(matcher.match(for: query("Hotel California - Live On MTV, 1994", by: "Eagles", on: "Eagles Live")))
    }

    func testARemixIsNotTheOriginal() {
        let matcher = SongMatcher(library: [song("Strawberry Swing", by: "Coldplay")])

        XCTAssertNil(matcher.match(for: query("Strawberry Swing - Frankmusik Remix", by: "Coldplay")))
    }

    func testTwoRemixersMakeTwoRecordings() {
        let leger = song("Strobe (Sebastien Leger Remix)", by: "deadmau5")
        let woods = song("Strobe (Michael Woods Remix)", by: "deadmau5")

        XCTAssertNil(SongMatcher(library: [leger]).match(for: query("Strobe - Michael Woods Remix", by: "deadmau5")))
        XCTAssertEqual(SongMatcher(library: [leger, woods]).match(for: query("Strobe - Michael Woods Remix", by: "deadmau5")), woods)
    }

    func testAnotherNightsLiveRecordingIsAnotherRecording() {
        let glastonbury = song("Clocks (Live at Glastonbury 2011)", by: "Coldplay")
        let sydney = song("Clocks", by: "Coldplay", on: "Live in Sydney")
        let wembley86 = song("Song (Live at Wembley 1986)", by: "Band")

        XCTAssertNil(SongMatcher(library: [glastonbury]).match(for: query("Clocks - Live in Sydney", by: "Coldplay")))
        XCTAssertNil(SongMatcher(library: [glastonbury]).match(for: query("Clocks - Live at Glastonbury 2016", by: "Coldplay")))
        XCTAssertNil(SongMatcher(library: [wembley86]).match(for: query("Song - Live at Wembley 1987", by: "Band")))
        XCTAssertEqual(SongMatcher(library: [glastonbury, sydney]).match(for: query("Clocks - Live in Sydney", by: "Coldplay")), sydney,
                       "the album can say which night")
    }

    func testAnotherShowOrNightOnOneReleaseIsAnotherRecording() {
        let secondNight = song("Song (Live at the Royal Albert Hall, 2nd Night)", by: "Artist", on: "Live at the Royal Albert Hall")
        let remastered2016 = song("Clocks (Live at Glastonbury 2016 Remastered 2020)", by: "Coldplay", on: "Live Anthology")
        let matcher = SongMatcher(library: [secondNight, remastered2016])

        XCTAssertNil(matcher.match(for: query("Song - Live at the Royal Albert Hall, 1st Night", by: "Artist",
                                              on: "Live at the Royal Albert Hall")))
        XCTAssertEqual(matcher.match(for: query("Song - Live at the Royal Albert Hall, 2nd Night", by: "Artist",
                                                on: "Live at the Royal Albert Hall")), secondNight)
        XCTAssertNil(matcher.match(for: query("Clocks - Live at Glastonbury 2011 Remastered 2020", by: "Coldplay", on: "Live Anthology")))
        XCTAssertEqual(matcher.match(for: query("Clocks - Live at Glastonbury 2016 Remastered 2020", by: "Coldplay",
                                                on: "Live Anthology")), remastered2016)
    }

    func testANameThatSaysLessIsTheSameOnlyWhenItLeavesOutAYear() {
        // Leaving out a show, a place or a remixer's style named another recording, which
        // the fourth review found rated in place of this one (2026-10-29)
        let firstShow = song("Folsom Prison Blues (Live at Folsom State Prison)", by: "Johnny Cash", on: "At Folsom Prison")
        let deepHouse = song("Song (Tiesto Deep House Remix)", by: "Artist", on: "Song (Remixes)", rating: 80)
        let remix = song("Song (Tiesto Remix)", by: "Artist", on: "Song (Remixes)")

        XCTAssertNil(SongMatcher(library: [firstShow]).match(for: query(
            "Folsom Prison Blues - Live at Folsom State Prison, Folsom, CA (2nd Show) - January 1968", by: "Johnny Cash",
            on: "At Folsom Prison (Legacy Edition)")))
        XCTAssertNil(SongMatcher(library: [deepHouse]).match(for: query("Song - Tiësto Remix", by: "Artist", on: "Song (Remixes)")))
        XCTAssertEqual(SongMatcher(library: [deepHouse, remix])
            .match(for: query("Song - Tiësto Remix", by: "Artist", on: "Song (Remixes)")), remix)
    }

    func testATwelveInchRemixIsNotTheSevenInch() {
        let seven = song("Song (7\" Remix)", by: "Artist", on: "Song - Single", rating: 80)
        let twelve = song("Song (12\" Remix)", by: "Artist", on: "Song - Single")
        let bakerSeven = song("Song (Arthur Baker 7\" Remix)", by: "Artist", on: "Singles 1985")

        XCTAssertEqual(SongMatcher(library: [seven, twelve]).match(for: query("Song - 12\" Remix", by: "Artist", on: "Song")), twelve)
        XCTAssertNil(SongMatcher(library: [bakerSeven])
            .match(for: query("Song - Arthur Baker 12\" Remix", by: "Artist", on: "Greatest Hits")))
    }

    func testALiveTrackIsNotAPlainOneOnAnotherEditionsLiveAlbum() {
        let inConcert = song("Song", by: "Artist", on: "Album: In Concert")
        let matcher = SongMatcher(library: [inConcert])

        XCTAssertNil(matcher.match(for: query("Song - Live", by: "Artist", on: "Album (Deluxe Edition)")),
                     "a deluxe edition is not the concert")
        XCTAssertEqual(matcher.match(for: query("Song - Live", by: "Artist", on: "Album")), inConcert)
    }

    func testAReRecordingIsNotTheOriginal() {
        let original = song("Rock of Ages", by: "Def Leppard", on: "Pyromania")

        XCTAssertNil(SongMatcher(library: [original]).match(for: query("Rock of Ages - Re-Recorded", by: "Def Leppard")))
    }

    func testAnArrangementWithSomeoneIsNotThePlainSong() {
        // Nothing in "with" says whether it is a guest or an orchestra; only the other
        // track's credits can
        let yesterday = song("Yesterday", by: "The Beatles", on: "Help!")
        let orchestral = song("Love Me Tender (with The Royal Philharmonic Orchestra)", by: "Elvis Presley")

        XCTAssertNil(SongMatcher(library: [yesterday]).match(for: query("Yesterday (With Strings)", by: "The Beatles")))
        XCTAssertNil(SongMatcher(library: [orchestral]).match(for: query("Love Me Tender", by: "Elvis Presley")))
    }

    func testAGuestCreditedWithWithIsFoundWhereTheCopyCreditsThem() {
        let joint = song("Stay", by: "The Kid LAROI & Justin Bieber")
        let titled = song("Stay (with Justin Bieber)", by: "The Kid LAROI")

        XCTAssertEqual(SongMatcher(library: [joint]).match(for: query("Stay (with Justin Bieber)", by: "The Kid LAROI")), joint)
        XCTAssertEqual(SongMatcher(library: [titled]).match(for: query("Stay (with Justin Bieber)", by: "The Kid LAROI")), titled)
        XCTAssertNil(SongMatcher(library: [titled]).match(for: query("Stay", by: "Justin Bieber")))
    }

    func testSomeoneCreditedWithWithIsFoundInAJointCreditWhateverTheirName() {
        // A one-word name after the lead isn't the copy's artist (testABackingBandIsNotTheArtist),
        // but it is credited, which is all "with" asks. The fourth review found each of these
        // missed (2026-10-29).
        let stars = song("All the Stars", by: "Kendrick Lamar & SZA", on: "Black Panther The Album")
        let lovely = song("lovely", by: "Billie Eilish & Khalid", on: "lovely - Single")
        let sourCandy = song("Sour Candy", by: "Lady Gaga & BLACKPINK", on: "Chromatica")
        let creepin = song("Creepin'", by: "Metro Boomin, The Weeknd & 21 Savage", on: "Heroes & Villains")
        let basement = song("Tears of Rage", by: "Bob Dylan & The Band", on: "The Basement Tapes")
        let bigPink = song("Tears of Rage", by: "The Band", on: "Music from Big Pink")
        let matcher = SongMatcher(library: [stars, lovely, sourCandy, creepin, basement, bigPink])

        XCTAssertEqual(matcher.match(for: query("All The Stars (with SZA)", by: "Kendrick Lamar",
                                                on: "Black Panther The Album Music From And Inspired By")), stars)
        XCTAssertEqual(matcher.match(for: query("lovely (with Khalid)", by: "Billie Eilish", on: "lovely (with Khalid)")), lovely)
        XCTAssertEqual(matcher.match(for: query("Sour Candy (with BLACKPINK)", by: "Lady Gaga", on: "Chromatica")), sourCandy)
        XCTAssertEqual(matcher.match(for: query("Creepin' (with The Weeknd & 21 Savage)", by: "Metro Boomin",
                                                on: "HEROES & VILLAINS")), creepin)
        XCTAssertEqual(matcher.match(for: query("Tears of Rage (with The Band)", by: "Bob Dylan", on: "The Basement Tapes")), basement)
        XCTAssertEqual(matcher.copies(of: query("Tears of Rage", by: "The Band", on: "Music from Big Pink")), [bigPink],
                       "credited is not the artist")
    }

    func testEveryoneCreditedWithWithMustBeCredited() {
        // Only the first of two was looked for, so this found the duet without Rihanna
        let stay = song("Stay", by: "The Kid LAROI & Justin Bieber", on: "F*CK LOVE 3")
        let matcher = SongMatcher(library: [stay])

        XCTAssertNil(matcher.match(for: query("Stay (with Justin Bieber & Rihanna)", by: "The Kid LAROI", on: "Collaborations")))
        XCTAssertEqual(matcher.match(for: query("Stay (with Justin Bieber)", by: "The Kid LAROI", on: "F*CK LOVE 3")), stay)
    }

    func testAOneWordNameAfterTheLeadIsAMissTheRulesAccept() {
        // The Supremes are "one word after the lead", like The Band behind Bob Dylan
        let babyLove = song("Baby Love", by: "Diana Ross & The Supremes", on: "Gold")

        XCTAssertNil(SongMatcher(library: [babyLove]).match(for: query("Baby Love", by: "The Supremes", on: "Where Did Our Love Go")))
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

    func testAPlainTrackOnARemixAlbumIsNotANamedRemix() {
        // The EP's plain track is the original mix; its remixes name their remixers
        let original = song("Sweet Nothing", by: "Calvin Harris", on: "18 Months")
        let tiesto = song("Sweet Nothing (feat. Florence Welch) [Tiësto Remix]", by: "Calvin Harris", on: "Sweet Nothing (Remixes)")
        let onTheEP = song("Sweet Nothing (feat. Florence Welch)", by: "Calvin Harris", on: "Sweet Nothing (Remixes)")
        let ep = query("Sweet Nothing (feat. Florence Welch)", by: "Calvin Harris", on: "Sweet Nothing (Remixes)")

        XCTAssertNil(SongMatcher(library: [original, tiesto]).match(for: ep))
        XCTAssertEqual(SongMatcher(library: [onTheEP, tiesto]).match(for: ep), onTheEP)
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

    // MARK: - Building again after a library change

    func testAMatcherBuiltAgainFindsWhatAFreshOneFinds() {
        let before = [song("Zombie", by: "The Cranberries"), song("Linger", by: "The Cranberries"),
                      song("Strawberry Swing", by: "Coldplay")]
        let after = before + [song("Dreams", by: "The Cranberries"), song("Zombie", by: "The Cranberries", on: "Stars")]
        let reused = SongMatcher(library: after, reusing: SongMatcher(library: before))
        let fresh = SongMatcher(library: after)

        for name in ["Zombie", "Linger", "Dreams", "Strawberry Swing"] {
            let artist = name == "Strawberry Swing" ? "Coldplay" : "The Cranberries"
            XCTAssertEqual(reused.copies(of: query(name, by: artist)), fresh.copies(of: query(name, by: artist)), name)
        }
        XCTAssertEqual(reused.count, 5)
    }

    func testARenamedTrackIsFoundByItsNewName() {
        // What is reused goes by the names, never by the track: the persistent ID stays
        let zombie = song("Zombie", by: "The Cranberries")
        let renamed = LibrarySong(persistentID: zombie.persistentID, name: "Linger", artist: "The Cranberries",
                                  albumArtist: "")
        let matcher = SongMatcher(library: [renamed], reusing: SongMatcher(library: [zombie]))

        XCTAssertEqual(matcher.copies(of: query("Zombie", by: "The Cranberries")), [])
        XCTAssertEqual(matcher.copies(of: query("Linger", by: "The Cranberries")), [renamed])
    }

    func testATrackAddedAgainIsTheNewTrack() {
        // Deleted and added again: the same names, another persistent ID, and only the new
        // one is there to rate
        let old = song("Zombie", by: "The Cranberries")
        let new = song("Zombie", by: "The Cranberries")
        let matcher = SongMatcher(library: [new], reusing: SongMatcher(library: [old]))

        XCTAssertEqual(matcher.copies(of: query("Zombie", by: "The Cranberries")), [new])
        XCTAssertEqual(SongMatcher(library: [], reusing: matcher).copies(of: query("Zombie", by: "The Cranberries")), [],
                       "nothing carried over from a library the track has left")
    }

    func testPastTheLimitTheCopiesTitledAsTheSongIsRecordedAreRead() {
        // Only reading a copy tells its album, so past the limit its title has to say it all
        // (the third review, 2026-10-29)
        let studio = (1...13).map { song("Clocks", by: "Coldplay", on: "Studio \($0)") }
        let live = song("Clocks (Live)", by: "Coldplay", on: "Live 2003")

        XCTAssertEqual(SongMatcher.titledAlike(studio + [live], as: query("Clocks", by: "Coldplay", on: "Live 2003")), [live])
        XCTAssertEqual(SongMatcher.titledAlike(studio + [live], as: query("Clocks - Live", by: "Coldplay")), [live])
        XCTAssertEqual(SongMatcher.titledAlike(studio + [live], as: query("Clocks", by: "Coldplay", on: "A Rush of Blood to the Head")),
                       studio)
    }

    func testPastTheLimitARemixAlbumsPlainTrackFindsNoNamedRemix() {
        let studio = (1...13).map { song("Sweet Nothing", by: "Calvin Harris", on: "18 Months \($0)") }
        let tiesto = song("Sweet Nothing (feat. Florence Welch) [Tiësto Remix]", by: "Calvin Harris", on: "Sweet Nothing (Remixes)")
        let ep = query("Sweet Nothing (feat. Florence Welch)", by: "Calvin Harris", on: "Sweet Nothing (Remixes)")

        XCTAssertEqual(SongMatcher.ranked(SongMatcher.titledAlike(studio + [tiesto], as: ep), for: ep), [])
    }

    func testPastTheLimitACopyTitledWithPartOfWhatTheSongSaysIsRead() {
        // Spotify says acoustic in its title and live in its album's name, and the copy says
        // only acoustic: no copy is titled with both
        let studio = (1...13).map { song("Song", by: "Artist", on: "Studio \($0)") }
        let acoustic = song("Song (Acoustic)", by: "Artist", on: "MTV Unplugged")
        let unplugged = query("Song - Acoustic", by: "Artist", on: "MTV Unplugged")

        XCTAssertEqual(SongMatcher.titledAlike(studio + [acoustic], as: unplugged), [acoustic])
        XCTAssertEqual(SongMatcher.ranked(SongMatcher.titledAlike(studio + [acoustic], as: unplugged), for: unplugged), [acoustic])
    }

    func testAlbumCloseness() {
        XCTAssertEqual(SongMatcher.closeness(of: "abba gold", to: "abba gold"), 0)
        XCTAssertEqual(SongMatcher.closeness(of: "abba gold", to: "abba gold greatest hits"), 1)
        XCTAssertEqual(SongMatcher.closeness(of: "the complete singles collection", to: "abba gold"), 2)
        XCTAssertEqual(SongMatcher.closeness(of: "", to: "abba gold"), 2)
    }

}
