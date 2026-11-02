//
//  AppleMusicArtworkLoaderTests.swift
//  StarBarTests
//
//  Which album's cover is taken from Apple's search, and that each album is asked once. No
//  network: the fetch is a fake.
//

import XCTest
@testable import StarBar

final class AppleMusicArtworkLoaderTests: XCTestCase {

    private var requests: [URL] = []
    private var searchAnswer: Data?
    private var coverAnswer: Data?
    private var loader: AppleMusicArtworkLoader!

    override func setUp() {
        super.setUp()
        requests = []
        searchAnswer = finding
        coverAnswer = png
        loader = AppleMusicArtworkLoader(fetch: { [unowned self] url, completion in
            self.requests.append(url)
            completion(url.host == "itunes.apple.com" ? self.searchAnswer : self.coverAnswer)
        }, country: "IE")
    }

    private let chainHome = (artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore")

    /// An answer in the shape Apple's search gives, with the album asked for second
    private func answer(_ albums: [(artist: String, name: String, cover: String)]) -> Data {
        let results: [[String: Any]] = albums.enumerated().map { index, album in
            [
                "wrapperType": "collection",
                "collectionType": "Album",
                "collectionId": 1_440_000_000 + index,
                "artistName": album.artist,
                "collectionName": album.name,
                "artworkUrl60": album.cover.replacingOccurrences(of: "100x100bb", with: "60x60bb"),
                "artworkUrl100": album.cover,
            ]
        }
        return try! JSONSerialization.data(withJSONObject: ["resultCount": results.count, "results": results])
    }

    private var finding: Data {
        return answer([
            ("Brian Eno", "Another Green World", "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/aa/agw.jpg/100x100bb.jpg"),
            ("Tom Rogerson & Brian Eno", "Finding Shore", "https://is3-ssl.mzstatic.com/image/thumb/Music126/v4/bb/fs.jpg/100x100bb.jpg"),
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

    func testTheSearchAsksForAlbumsByArtistAndName() {
        let url = AppleMusicArtworkLoader.searchURL(artist: "Tom Rogerson & Brian Eno", album: "Finding Shore", country: "IE")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(url.path, "/search")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["term"], "Tom Rogerson & Brian Eno Finding Shore")
        XCTAssertEqual(query["entity"], "album")
        XCTAssertEqual(query["media"], "music")
        XCTAssertEqual(query["country"], "ie")
        XCTAssertNil(AppleMusicArtworkLoader.searchURL(artist: "", album: "", country: nil))
    }

    func testAnArtistsAmpersandOrPlusStaysInTheTerm() {
        let url = AppleMusicArtworkLoader.searchURL(artist: "Florence + The Machine", album: "Lungs", country: nil)!
        XCTAssertTrue(url.absoluteString.contains("Florence%20%2B%20The%20Machine"), url.absoluteString)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "term" })?.value, "Florence + The Machine Lungs")
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "country" }))
        let ampersand = AppleMusicArtworkLoader.searchURL(artist: "Simon & Garfunkel", album: "Bookends", country: nil)!
        XCTAssertEqual(URLComponents(url: ampersand, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Simon & Garfunkel Bookends")
    }

    func testTheMatchingAlbumsCoverIsTakenLarger() {
        XCTAssertEqual(AppleMusicArtworkLoader.cover(in: finding, artists: chainHome.artists, album: chainHome.album),
                       URL(string: "https://is3-ssl.mzstatic.com/image/thumb/Music126/v4/bb/fs.jpg/600x600bb.jpg"))
    }

    func testAnotherAlbumIsNeverTaken() {
        // The search for one album can answer with others by the same artist
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["Brian Eno"], album: "Music for Airports"))
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["Radiohead"], album: "The Bends"))
    }

    func testTheArtistHasToBeTheSongs() {
        XCTAssertNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["A Tribute Band"], album: "Finding Shore"))
        // The album artist or the track's artist will do
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["Various Artists", "Tom Rogerson & Brian Eno"], album: "Finding Shore"))
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: finding, artists: ["tom rogerson & brian eno"], album: "finding shore"))
    }

    func testAnEditionOfTheAlbumIsTheAlbum() {
        let deluxe = answer([("Tom Rogerson & Brian Eno", "Finding Shore (Deluxe Edition)", "https://is3-ssl.mzstatic.com/fs.jpg/100x100bb.jpg")])
        XCTAssertNotNil(AppleMusicArtworkLoader.cover(in: deluxe, artists: chainHome.artists, album: chainHome.album))
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
        XCTAssertEqual(AppleMusicArtworkLoader.key(artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore (Deluxe Edition)"),
                       AppleMusicArtworkLoader.key(artists: ["tom rogerson & brian eno"], album: "Finding Shore"))
        XCTAssertNotEqual(AppleMusicArtworkLoader.key(artists: ["Brian Eno"], album: "Finding Shore"),
                          AppleMusicArtworkLoader.key(artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore"))
        XCTAssertNil(AppleMusicArtworkLoader.key(artists: [], album: "Finding Shore"))
        XCTAssertNil(AppleMusicArtworkLoader.key(artists: ["Brian Eno"], album: ""))
    }

    // MARK: - Loading

    private func load(_ song: (artists: [String], album: String)) -> NSImage? {
        let answered = expectation(description: "answered")
        var cover: NSImage?
        loader.load(artists: song.artists, album: song.album) { image in
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
        loader.load(artists: chainHome.artists, album: chainHome.album) { image in
            XCTAssertNotNil(image)
            both.fulfill()
        }
        // The popover and the strip read the cover for one song
        loader.load(artists: chainHome.artists, album: chainHome.album) { image in
            XCTAssertNotNil(image)
            both.fulfill()
        }
        wait(for: [both], timeout: 1)
        XCTAssertEqual(requests.count, 2)
    }

    func testAnAlbumAppleHasNotIsNotAskedForAgain() {
        searchAnswer = answer([("Brian Eno", "Another Green World", "https://is1-ssl.mzstatic.com/agw.jpg/100x100bb.jpg")])
        XCTAssertNil(load(chainHome))
        XCTAssertEqual(requests.count, 1, "no cover to download")
        XCTAssertNil(load(chainHome))
        XCTAssertEqual(requests.count, 1, "the popover reads again on every update, and mustn't search each time")
        XCTAssertTrue(loader.isEmpty)
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

    func testASongWithNoAlbumAsksNothing() {
        XCTAssertNil(load((artists: ["Tom Rogerson & Brian Eno"], album: "")))
        XCTAssertNil(load((artists: [], album: "Finding Shore")))
        XCTAssertTrue(requests.isEmpty)
    }

    func testTheSharedLoaderNeverReachesTheNetworkUnderTests() {
        let answered = expectation(description: "answered")
        AppleMusicArtworkLoader.shared.load(artists: chainHome.artists, album: "A Test Album Nobody Has") { image in
            XCTAssertNil(image)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 1)
    }

}
