//
//  AppleMusicArtworkLoaderTests.swift
//  StarBarTests
//
//  Which album's cover is taken from Apple's search, and that each song is asked for once. No
//  network: the fetch is a fake, answering in the shape the live service gave on 2026-11-02.
//

import XCTest
@testable import StarBar

final class AppleMusicArtworkLoaderTests: XCTestCase {

    private var requests: [URL] = []
    private var searchAnswer: Data?
    /// Answers by search term, ahead of `searchAnswer`
    private var answersByTerm: [String: Data?] = [:]
    private var coverAnswer: Data?
    private var loader: AppleMusicArtworkLoader!

    override func setUp() {
        super.setUp()
        requests = []
        searchAnswer = finding
        answersByTerm = [:]
        coverAnswer = png
        loader = AppleMusicArtworkLoader(fetch: { [unowned self] url, completion in
            self.requests.append(url)
            guard url.host == "itunes.apple.com" else { return completion(self.coverAnswer) }
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value ?? ""
            completion(self.answersByTerm[term] ?? self.searchAnswer)
        }, country: "IE")
    }

    private func terms() -> [String] {
        return requests.filter { $0.host == "itunes.apple.com" }.compactMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value
        }
    }

    private let chainHome = (title: "Chain Home", artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore")

    /// An answer in the shape Apple's song search gives, one track per release
    private func answer(_ tracks: [(artist: String, album: String, cover: String)], albumArtist: String? = nil) -> Data {
        let results: [[String: Any]] = tracks.enumerated().map { index, track in
            var result: [String: Any] = [
                "wrapperType": "track",
                "kind": "song",
                "collectionId": 1_440_000_000 + index,
                "trackName": "A Song",
                "artistName": track.artist,
                "collectionName": track.album,
                "artworkUrl60": track.cover.replacingOccurrences(of: "100x100bb", with: "60x60bb"),
                "artworkUrl100": track.cover,
            ]
            if let albumArtist = albumArtist {
                result["collectionArtistName"] = albumArtist
            }
            return result
        }
        return try! JSONSerialization.data(withJSONObject: ["resultCount": results.count, "results": results])
    }

    private var finding: Data {
        return answer([
            ("Brian Eno", "Another Green World", "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/agw.jpg/100x100bb.jpg"),
            ("Tom Rogerson & Brian Eno", "Finding Shore", "https://is3-ssl.mzstatic.com/image/thumb/Music126/v4/bb/fs.jpg/100x100bb.jpg"),
        ])
    }

    /// The song search for "Exit Music (For a Film)", 2026-11-02: the plain album and the
    /// OKNOTOK edition, each with its own cover. The album search found only the plain one.
    /// The song search for "Obsidian", 2026-11-02: the expanded edition first, then the plain
    /// album, whose cover is another
    private var obsidian: Data {
        return answer([
            ("Roger Eno & Brian Eno", "Mixing Colours (Expanded)", "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/82/expanded.jpg/100x100bb.jpg"),
            ("Roger Eno & Brian Eno", "Mixing Colours", "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b6/plain.jpg/100x100bb.jpg"),
        ])
    }

    private var exitMusic: Data {
        return answer([
            ("Radiohead", "OK Computer OKNOTOK 1997 2017", "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/9c/oknotok.jpg/100x100bb.jpg"),
            ("Radiohead", "OK Computer", "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/07/okc.png/100x100bb.jpg"),
        ])
    }

    /// A tiny PNG, so `NSImage(data:)` has something real to decode
    private var png: Data {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.green.setFill()
            rect.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: - The search

    func testTheSearchAsksForTheSongByArtistAndTitle() {
        let url = AppleMusicArtworkLoader.searchURL(artist: "Radiohead", title: "Exit Music (For a Film) [Remastered]", country: "IE")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(url.path, "/search")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["term"], "Radiohead Exit Music (For a Film) [Remastered]")
        XCTAssertEqual(query["entity"], "song")
        XCTAssertEqual(query["media"], "music")
        XCTAssertEqual(query["limit"], "25")
        XCTAssertEqual(query["country"], "ie")
        XCTAssertNil(AppleMusicArtworkLoader.searchURL(artist: "", title: "Chain Home", country: nil))
        XCTAssertNil(AppleMusicArtworkLoader.searchURL(artist: "Radiohead", title: "", country: nil))
    }

    func testAnArtistsAmpersandOrPlusStaysInTheTerm() {
        let url = AppleMusicArtworkLoader.searchURL(artist: "Florence + The Machine", title: "Dog Days Are Over", country: nil)!
        XCTAssertTrue(url.absoluteString.contains("Florence%20%2B%20The%20Machine"), url.absoluteString)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "term" })?.value, "Florence + The Machine Dog Days Are Over")
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "country" }))
        let ampersand = AppleMusicArtworkLoader.searchURL(artist: "Simon & Garfunkel", title: "America", country: nil)!
        XCTAssertEqual(URLComponents(url: ampersand, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Simon & Garfunkel America")
    }

    func testTheMatchingAlbumsCoverIsTakenLarger() {
        XCTAssertEqual(AppleMusicArtworkLoader.cover(in: finding, artists: chainHome.artists, album: chainHome.album),
                       URL(string: "https://is3-ssl.mzstatic.com/image/thumb/Music126/v4/bb/fs.jpg/600x600bb.jpg"))
    }

    func testAnEditionNamedLikeTheAlbumIsNotTheAlbum() {
        // OKNOTOK and the plain OK Computer have different covers, and the search answers
        // with both for one song
        XCTAssertEqual(AppleMusicArtworkLoader.cover(in: exitMusic, artists: ["Radiohead"], album: "OK Computer OKNOTOK 1997 2017")?.lastPathComponent, "600x600bb.jpg")
        XCTAssertEqual(AppleMusicArtworkLoader.cover(in: exitMusic, artists: ["Radiohead"], album: "OK Computer OKNOTOK 1997 2017")?.deletingLastPathComponent().lastPathComponent, "oknotok.jpg")
        XCTAssertEqual(AppleMusicArtworkLoader.cover(in: exitMusic, artists: ["Radiohead"], album: "OK Computer")?.deletingLastPathComponent().lastPathComponent, "okc.png")
    }

    func testAnotherAlbumIsNeverTaken() {
        // The search for one album can answer with others by the same artist
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["Brian Eno"], album: "Music for Airports"))
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["Radiohead"], album: "The Bends"))
    }

    func testTheArtistHasToBeTheSongs() {
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["A Tribute Band"], album: "Finding Shore"))
        // The track's artist or the album artist will do
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["Various Artists", "Tom Rogerson & Brian Eno"], album: "Finding Shore"))
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["tom rogerson & brian eno"], album: "finding shore"))
        // and on Apple's side, the album artist of a compilation
        let compilation = answer([("Someone Else", "Finding Shore", "https://is3-ssl.mzstatic.com/fs.jpg/100x100bb.jpg")], albumArtist: "Tom Rogerson & Brian Eno")
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: compilation, artists: chainHome.artists, album: chainHome.album))
    }

    func testAnotherEditionOfTheAlbumIsAnotherAlbum() {
        let roger = ["Roger Eno & Brian Eno"]
        XCTAssertEqual(AppleMusicArtworkLoader.cover(in: obsidian, artists: roger, album: "Mixing Colours (Expanded)")?.deletingLastPathComponent().lastPathComponent, "expanded.jpg")
        XCTAssertEqual(AppleMusicArtworkLoader.cover(in: obsidian, artists: roger, album: "Mixing Colours")?.deletingLastPathComponent().lastPathComponent, "plain.jpg",
                       "whichever Apple puts first")
        let deluxe = answer([("Tom Rogerson & Brian Eno", "Finding Shore (Deluxe Edition)", "https://is3-ssl.mzstatic.com/fs.jpg/100x100bb.jpg")])
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: deluxe, artists: chainHome.artists, album: chainHome.album),
                     "a deluxe edition's cover can be another")
        // Only case, accents and punctuation are let go
        let typographic = answer([("Tom Rogerson & Brian Eno", "FINDING SHORE", "https://is3-ssl.mzstatic.com/fs.jpg/100x100bb.jpg")])
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: typographic, artists: chainHome.artists, album: "Finding Shore"))
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: answer([("Beyoncé", "Lemonade", "https://is1-ssl.mzstatic.com/l.jpg/100x100bb.jpg")]),
                                                      artists: ["Beyonce"], album: "Lemonade"))
    }

    func testOnlyApplesImageHostIsDownloaded() {
        XCTAssertTrue(AppleMusicArtworkLoader.isAllowedCover(URL(string: "https://is1-ssl.mzstatic.com/image/thumb/a.jpg/600x600bb.jpg")!))
        XCTAssertFalse(AppleMusicArtworkLoader.isAllowedCover(URL(string: "http://is1-ssl.mzstatic.com/a.jpg")!))
        XCTAssertFalse(AppleMusicArtworkLoader.isAllowedCover(URL(string: "https://example.com/is1-ssl.mzstatic.com/a.jpg")!))
        XCTAssertFalse(AppleMusicArtworkLoader.isAllowedCover(URL(string: "https://notmzstatic.com/a.jpg")!))
        XCTAssertFalse(AppleMusicArtworkLoader.isAllowedCover(URL(string: "file:///etc/passwd")!))
        let elsewhere = answer([("Tom Rogerson & Brian Eno", "Finding Shore", "https://example.com/fs.jpg/100x100bb.jpg")])
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: elsewhere, artists: chainHome.artists, album: chainHome.album))
    }

    func testAnAnswerThatIsntApplesShapeIsNoAnswer() {
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: Data("<html>".utf8), artists: chainHome.artists, album: chainHome.album))
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: Data("{\"results\": 3}".utf8), artists: chainHome.artists, album: chainHome.album))
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: [], album: chainHome.album))
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: chainHome.artists, album: ""))
    }

    func testAnAlbumIsKnownByItsFoldedNameAndArtist() {
        XCTAssertEqual(AppleMusicArtworkLoader.key(artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore"),
                       AppleMusicArtworkLoader.key(artists: ["tom rogerson & brian eno"], album: "finding shore"))
        // A cover kept for an edition is not handed out for the album
        XCTAssertNotEqual(AppleMusicArtworkLoader.key(artists: ["Roger Eno & Brian Eno"], album: "Mixing Colours (Expanded)"),
                          AppleMusicArtworkLoader.key(artists: ["Roger Eno & Brian Eno"], album: "Mixing Colours"))
        XCTAssertNotEqual(AppleMusicArtworkLoader.key(artists: ["Brian Eno"], album: "Finding Shore"),
                          AppleMusicArtworkLoader.key(artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore"))
        XCTAssertNil(AppleMusicArtworkLoader.key(artists: [], album: "Finding Shore"))
        XCTAssertNil(AppleMusicArtworkLoader.key(artists: ["Brian Eno"], album: ""))
    }

    func testATitleIsSearchedForWithoutItsBracketsWhenInFullItFindsNothing() {
        XCTAssertEqual(AppleMusicArtworkLoader.searchTitles("Life On Mars? (Original Ending Version)"), ["Life On Mars? (Original Ending Version)", "Life On Mars?"])
        XCTAssertEqual(AppleMusicArtworkLoader.searchTitles("Exit Music (For a Film) [Remastered]"), ["Exit Music (For a Film) [Remastered]", "Exit Music"])
        XCTAssertEqual(AppleMusicArtworkLoader.searchTitles("Fake Plastic Trees - Live"), ["Fake Plastic Trees - Live", "Fake Plastic Trees"])
        XCTAssertEqual(AppleMusicArtworkLoader.searchTitles("Chain Home"), ["Chain Home"])
        XCTAssertEqual(AppleMusicArtworkLoader.searchTitles("(Untitled)"), ["(Untitled)"])
        XCTAssertEqual(AppleMusicArtworkLoader.searchTitles("  "), [])
    }

    // MARK: - Loading

    private func load(_ song: (title: String, artists: [String], album: String)) -> NSImage? {
        let answered = expectation(description: "answered")
        var cover: NSImage?
        loader.load(title: song.title, artists: song.artists, album: song.album) { image in
            cover = image
            answered.fulfill()
        }
        wait(for: [answered], timeout: 1)
        return cover
    }

    func testACoverIsFetchedOnceAndThenKept() {
        XCTAssertTrue(loader.isEmpty)
        XCTAssertNotNil(load(chainHome))
        XCTAssertEqual(requests.map { $0.host }, ["itunes.apple.com", "is3-ssl.mzstatic.com"])
        XCTAssertEqual(requests.last?.lastPathComponent, "600x600bb.jpg")
        XCTAssertFalse(loader.isEmpty)
        XCTAssertNotNil(loader.cachedCover(artists: chainHome.artists, album: chainHome.album))

        XCTAssertNotNil(load(chainHome))
        XCTAssertEqual(requests.count, 2, "a kept cover asks nothing")
    }

    func testTwoAsksAtOnceShareOneSearch() {
        let both = expectation(description: "both answered")
        both.expectedFulfillmentCount = 2
        loader.load(title: chainHome.title, artists: chainHome.artists, album: chainHome.album) { image in
            XCTAssertNotNil(image)
            both.fulfill()
        }
        // The popover and the strip read the cover for one song
        loader.load(title: chainHome.title, artists: chainHome.artists, album: chainHome.album) { image in
            XCTAssertNotNil(image)
            both.fulfill()
        }
        wait(for: [both], timeout: 1)
        XCTAssertEqual(requests.count, 2)
    }

    func testASongAppleHasNotIsNotAskedForAgain() {
        searchAnswer = answer([("Brian Eno", "Another Green World", "https://is1-ssl.mzstatic.com/agw.jpg/100x100bb.jpg")])
        XCTAssertNil(load(chainHome))
        XCTAssertEqual(requests.count, 1, "no cover to download")
        XCTAssertNil(load(chainHome))
        XCTAssertEqual(requests.count, 1, "the popover reads again on every update, and mustn't search each time")
        XCTAssertTrue(loader.isEmpty)

        // Another song of the album is another search, which can find it
        searchAnswer = finding
        XCTAssertNotNil(load((title: "Marble Hill", artists: chainHome.artists, album: chainHome.album)))
        XCTAssertEqual(requests.count, 3)
        // and the album's cover then answers for every song of it
        XCTAssertNotNil(load(chainHome))
        XCTAssertEqual(requests.count, 3)
    }

    func testWhenTheFullTitleFindsNothingTheShortOneIsTried() {
        // 2026-11-02: the full name found no Bowie song at all; without the brackets, the album
        let bowie = (title: "Life On Mars? (Original Ending Version)", artists: ["David Bowie"], album: "Divine Symmetry")
        answersByTerm["David Bowie Life On Mars? (Original Ending Version)"] = answer([("Electric Light Orchestra", "Out of the Blue", "https://is1-ssl.mzstatic.com/otb.jpg/100x100bb.jpg")])
        answersByTerm["David Bowie Life On Mars?"] = answer([
            ("David Bowie", "Hunky Dory (2015 Remaster)", "https://is1-ssl.mzstatic.com/hd.jpg/100x100bb.jpg"),
            ("David Bowie", "Divine Symmetry", "https://is1-ssl.mzstatic.com/ds.jpg/100x100bb.jpg"),
        ])
        XCTAssertNotNil(load(bowie))
        XCTAssertEqual(terms(), ["David Bowie Life On Mars? (Original Ending Version)", "David Bowie Life On Mars?"])
        XCTAssertEqual(requests.last?.deletingLastPathComponent().lastPathComponent, "ds.jpg")
    }

    func testTheShortTitleIsNotSearchedForWhenTheFullOneFinds() {
        searchAnswer = exitMusic
        XCTAssertNotNil(load((title: "Exit Music (For a Film) [Remastered]", artists: ["Radiohead"], album: "OK Computer OKNOTOK 1997 2017")))
        XCTAssertEqual(terms(), ["Radiohead Exit Music (For a Film) [Remastered]"])
    }

    func testASongIsRememberedAsMissingOnlyWhenEverySearchWasAnswered() {
        let bowie = (title: "Life On Mars? (Original Ending Version)", artists: ["David Bowie"], album: "Divine Symmetry")
        answersByTerm["David Bowie Life On Mars? (Original Ending Version)"] = .some(nil)
        XCTAssertNil(load(bowie), "the first search failed and the second found another album")
        XCTAssertEqual(terms().count, 2)
        XCTAssertNil(load(bowie))
        XCTAssertEqual(terms().count, 4, "a failed search is tried again")

        answersByTerm = [:]
        XCTAssertNil(load(bowie))
        XCTAssertEqual(terms().count, 6)
        XCTAssertNil(load(bowie))
        XCTAssertEqual(terms().count, 6, "both answered without the album, so it isn't asked again")
    }

    func testAFailedSearchIsTriedAgainNextTime() {
        searchAnswer = nil
        XCTAssertNil(load(chainHome))
        searchAnswer = finding
        XCTAssertNotNil(load(chainHome))
        XCTAssertEqual(requests.count, 3)
    }

    func testAFailedDownloadIsNotKept() {
        coverAnswer = nil
        XCTAssertNil(load(chainHome))
        XCTAssertTrue(loader.isEmpty)
        coverAnswer = Data("not an image".utf8)
        XCTAssertNil(load(chainHome))
        XCTAssertTrue(loader.isEmpty)
    }

    func testASongWithNoAlbumArtistOrTitleAsksNothing() {
        XCTAssertNil(load((title: "Chain Home", artists: ["Tom Rogerson & Brian Eno"], album: "")))
        XCTAssertNil(load((title: "Chain Home", artists: [], album: "Finding Shore")))
        XCTAssertNil(load((title: "", artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore")))
        XCTAssertTrue(requests.isEmpty)
    }

    func testTheSharedLoaderNeverReachesTheNetworkUnderTests() {
        let answered = expectation(description: "answered")
        AppleMusicArtworkLoader.shared.load(title: chainHome.title, artists: chainHome.artists, album: "A Test Album Nobody Has") { image in
            XCTAssertNil(image)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 1)
    }

}
