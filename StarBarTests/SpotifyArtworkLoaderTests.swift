//
//  SpotifyArtworkLoaderTests.swift
//  StarBarTests
//
//  Which artwork URLs are fetched, and that each is fetched once. No network: the fetch is
//  a fake.
//

import XCTest
@testable import StarBar

final class SpotifyArtworkLoaderTests: XCTestCase {

    private var requests: [URL] = []
    private var pending: [(Data?) -> Void] = []
    private var loader: SpotifyArtworkLoader!

    override func setUp() {
        super.setUp()
        requests = []
        pending = []
        loader = SpotifyArtworkLoader(fetch: { [unowned self] url, completion in
            self.requests.append(url)
            self.pending.append(completion)
        })
    }

    private let sleeve = URL(string: "https://i.scdn.co/image/ab67616d0000b273abcdef")!

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

    func testOnlyHTTPSOnSpotifysImageHostIsAllowed() {
        XCTAssertTrue(SpotifyArtworkLoader.isAllowed(sleeve))
        XCTAssertTrue(SpotifyArtworkLoader.isAllowed(URL(string: "https://mosaic.scdn.co/640/abc")!))
        XCTAssertFalse(SpotifyArtworkLoader.isAllowed(URL(string: "http://i.scdn.co/image/abc")!))
        XCTAssertFalse(SpotifyArtworkLoader.isAllowed(URL(string: "https://example.com/i.scdn.co/abc")!))
        XCTAssertFalse(SpotifyArtworkLoader.isAllowed(URL(string: "https://notscdn.co/abc")!))
        XCTAssertFalse(SpotifyArtworkLoader.isAllowed(URL(string: "file:///etc/passwd")!))
    }

    func testADisallowedURLIsNeverFetched() {
        var answered = false
        loader.load(URL(string: "https://example.com/a.jpg")!) { image in
            answered = true
            XCTAssertNil(image)
        }

        XCTAssertTrue(answered)
        XCTAssertTrue(requests.isEmpty)
    }

    func testASleeveIsFetchedOnceAndThenCached() {
        let loaded = expectation(description: "loaded")
        loader.load(sleeve) { image in
            XCTAssertNotNil(image)
            loaded.fulfill()
        }
        loader.load(sleeve) { _ in }
        XCTAssertEqual(requests.count, 1, "a second request while the first is in flight waits for it")

        pending.first?(png)
        wait(for: [loaded], timeout: 1)

        XCTAssertNotNil(loader.cachedImage(for: sleeve))
        loader.load(sleeve) { _ in }
        XCTAssertEqual(requests.count, 1)
    }

    func testAFailedDownloadAnswersNilAndIsNotCached() {
        let answered = expectation(description: "answered")
        loader.load(sleeve) { image in
            XCTAssertNil(image)
            answered.fulfill()
        }

        pending.first?(nil)
        wait(for: [answered], timeout: 1)

        XCTAssertNil(loader.cachedImage(for: sleeve))
    }

    func testAnOversizedDownloadIsRefused() {
        let answered = expectation(description: "answered")
        loader.load(sleeve) { image in
            XCTAssertNil(image)
            answered.fulfill()
        }

        pending.first?(Data(count: SpotifyArtworkLoader.maximumBytes + 1))
        wait(for: [answered], timeout: 1)
    }

}
