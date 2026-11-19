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

    private let center = NotificationCenter()
    private var finishImage: ((Data?) -> Void)?
    private var holdImage = false
    private var previous: PlayInfo?
    private var requests: [URL] = []
    private var searchAnswer: Data?
    /// Answers by search term, ahead of `searchAnswer`
    private var answersByTerm: [String: Data?] = [:]
    private var coverAnswer: Data?
    private var clock = Date(timeIntervalSinceReferenceDate: 0)
    private var loader: AppleMusicArtworkLoader!

    override func setUp() {
        super.setUp()
        requests = []
        searchAnswer = finding
        answersByTerm = [:]
        coverAnswer = png
        clock = Date(timeIntervalSinceReferenceDate: 0)
        loader = AppleMusicArtworkLoader(fetch: { [unowned self] url, completion in
            self.requests.append(url)
            guard url.host == "itunes.apple.com" else {
                if self.holdImage {
                    self.finishImage = completion
                } else {
                    let data = self.coverAnswer
                    DispatchQueue.main.async { completion(data) }
                }
                return
            }
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "term" })?.value ?? ""
            completion(self.answersByTerm[term] ?? self.searchAnswer)
        }, country: "IE", now: { [unowned self] in self.clock }, center: center)
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

    // MARK: - From Music's notification to the strip

    private var payload: [String: Any] {
        ["Name": chainHome.title, "Artist": chainHome.artists[0], "Album": chainHome.album, "Player State": "Playing"]
    }

    private func notify(_ fields: [String: Any], enabled: Bool = true,
                        name: Notification.Name = iTunesRadioStation.playerInfoNotification,
                        onUpdate: () -> Void = {}) {
        let note = Notification(name: name, userInfo: fields)
        iTunesRadioStation.handlePlayInfo(note, previous: previous, announcementsEnabled: enabled, covers: loader) { info, _, _ in
            previous = info
            onUpdate()
        }
    }

    func testPlayingWithoutAnIDAsksBeforeThePlayerUpdateAndUsesTheAlbumArtist() {
        let fields = payload.merging(["Album Artist": "Ensemble"]) { $1 }
        searchAnswer = answer([("Ensemble", chainHome.album, "https://is3-ssl.mzstatic.com/fs/100x100bb.jpg")])
        notify(fields) {
            XCTAssertEqual(self.terms(), ["Tom Rogerson & Brian Eno Chain Home"])
            XCTAssertEqual(self.requests.last?.host, "is3-ssl.mzstatic.com", "only the Album Artist matches the search result")
        }
        notify(fields)
        XCTAssertEqual(requests.count, 2, "one search and one download")
    }

    func testPlayingWithAPersistentIDDoesNotAsk() {
        notify(payload.merging(["Persistent ID": 123]) { $1 })
        XCTAssertTrue(requests.isEmpty)
    }

    func testPausedWaitsForPlaying() {
        notify(payload.merging(["Player State": "Paused"]) { $1 })
        XCTAssertTrue(requests.isEmpty)
        notify(payload)
        XCTAssertEqual(terms().count, 1)
    }

    func testDisabledAnnouncementsDoNotAsk() {
        notify(payload, enabled: false)
        XCTAssertTrue(requests.isEmpty)
    }

    func testARepeatDoesNotStartEvenAColdSearch() {
        notify(payload, enabled: false)
        notify(payload)
        XCTAssertTrue(requests.isEmpty)
    }

    func testOnlyNamedSongsInPlayerInfoCanStartTheSearch() {
        for field in ["Name", "Artist", "Album"] {
            notify(payload.merging([field: "", "Album Artist": "Ensemble"]) { $1 })
        }
        notify(payload, name: Notification.Name("com.apple.iTunes.sourceSaved"))
        XCTAssertTrue(requests.isEmpty)
    }

    private func catalogTrack(albumArtist: String = "") -> FakeTrack {
        let track = FakeTrack(name: chainHome.title, artist: chainHome.artists[0], album: chainHome.album, albumArtist: albumArtist)
        track.objectClassCode = MusicTrackClass.urlTrack
        return track
    }

    private func strip(for playing: PlayingTrack, presenter: FakePresenter, clock: FakeClock) -> TrackAnnouncementController {
        TrackAnnouncementController(
            readPlayer: { self.previous.map(TrackAnnouncementController.PlayerSnapshot.init(playInfo:)) },
            loadLiveTrack: { identity, artwork in
                AppDelegate.loadAnnouncementLiveTrack(playing, for: identity, artwork: artwork, covers: self.loader, failedEvents: { 0 })
            },
            readCurrentIdentity: { $0 }, readPosition: { nil }, presenter: presenter, clock: clock,
            accessibility: { (false, false) }, isEnabled: true
        )
    }

    private func runQueuedCompletions() {
        let delivered = expectation(description: "queued cover callbacks ran")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 1)
    }

    func testSleeveJoinsTheNotificationSearchAndPublishesOnceToTheShowingStrip() throws {
        holdImage = true
        let track = catalogTrack()
        let playing = PlayingTrack(track: track, libraryCopy: { _ in nil })
        let presenter = FakePresenter(), frames = FakeClock()
        let controller = strip(for: playing, presenter: presenter, clock: frames)
        notify(payload) { controller.playerDidUpdate() }
        let announcement = try XCTUnwrap(presenter.shown.first)
        XCTAssertNil(announcement.artwork)
        XCTAssertNil(playing.sleeve(covers: loader), "a second reader must not publish again")
        frames.runFrames(for: 0.1)

        var posts = 0
        let observer = center.addObserver(forName: .appleMusicCoverDidLoad, object: nil, queue: nil) { note in
            posts += 1
            let identities = note.userInfo?[AppleMusicArtworkLoader.identitiesKey] as? [String]
            XCTAssertEqual(identities, [track.persistentID, announcement.identity])
            if let cover = note.userInfo?[AppleMusicArtworkLoader.imageKey] as? NSImage {
                for id in identities ?? [] { controller.attachArtwork(cover, identity: id) }
            }
        }
        defer { center.removeObserver(observer) }
        try XCTUnwrap(finishImage)(coverAnswer)
        runQueuedCompletions()
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(presenter.refreshed.count, 1)
        XCTAssertNotNil(presenter.refreshed.first?.artwork)
        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertEqual(terms().count, 1)
    }

    func testCoverDecodedBeforeTheStripReadIsInTheInitialPresentation() throws {
        holdImage = true
        notify(payload)
        try XCTUnwrap(finishImage)(coverAnswer)
        let presenter = FakePresenter(), frames = FakeClock()
        let controller = strip(for: PlayingTrack(track: catalogTrack(), libraryCopy: { _ in nil }), presenter: presenter, clock: frames)
        controller.playerDidUpdate()
        XCTAssertNotNil(presenter.shown.first?.artwork, "ready before the first slide frame, without pumping the main queue")
        frames.runFrames(for: 1.0 / 60)
        XCTAssertTrue(presenter.refreshed.isEmpty)
        XCTAssertEqual(terms().count, 1)
    }

    func testCoverDecodedDuringTheHeartReadIsInTheInitialPresentation() throws {
        holdImage = true
        let track = catalogTrack()
        notify(payload)
        let finish = try XCTUnwrap(finishImage)
        track.whenRead = { finish(self.coverAnswer) }
        let presenter = FakePresenter()
        let controller = strip(for: PlayingTrack(track: track, libraryCopy: { _ in nil }), presenter: presenter, clock: FakeClock())
        controller.playerDidUpdate()
        XCTAssertNotNil(presenter.shown.first?.artwork)
        XCTAssertEqual(terms().count, 1)
    }

    func testEarlyAppleCoverCannotStandInForASameAlbumLibraryCopy() throws {
        holdImage = true
        notify(payload)
        let ownCover = try XCTUnwrap(NSImage(data: png))
        let copy = FakeTrack(album: chainHome.album)
        let playing = PlayingTrack(track: catalogTrack(), readArtwork: { $0 === copy ? ownCover : nil }, libraryCopy: { _ in copy })
        XCTAssertTrue(playing.sleeve(covers: loader) === ownCover)
        var posts = 0
        let observer = center.addObserver(forName: .appleMusicCoverDidLoad, object: nil, queue: nil) { _ in posts += 1 }
        defer { center.removeObserver(observer) }
        try XCTUnwrap(finishImage)(coverAnswer)
        runQueuedCompletions()
        XCTAssertEqual(posts, 0)
        let presenter = FakePresenter()
        let controller = strip(for: playing, presenter: presenter, clock: FakeClock())
        controller.playerDidUpdate()
        XCTAssertEqual(presenter.shown.count, 1)
        XCTAssertTrue(presenter.shown.first?.artwork === ownCover, "a warmed cache must not replace the owned sleeve")
    }

    func testRetryFinishingDuringTheHeartReadSupersedesMusicsFallbackBeforeShow() throws {
        searchAnswer = nil
        XCTAssertNil(load(chainHome))
        clock += AppleMusicArtworkLoader.retryAfter
        holdImage = true
        searchAnswer = finding
        notify(payload)
        // An image with no representation still stands as the fallback, without consulting
        // the hosted app's live song history for a fingerprint comparison.
        let music = NSImage()
        guard SleeveFingerprint(image: music) == nil else { return XCTFail("expected an empty image") }
        let track = catalogTrack()
        let finish = try XCTUnwrap(finishImage)
        track.whenRead = { finish(self.coverAnswer) }
        let playing = PlayingTrack(track: track, readArtwork: { _ in music }, libraryCopy: { _ in nil })
        let presenter = FakePresenter()
        let controller = strip(for: playing, presenter: presenter, clock: FakeClock())
        controller.playerDidUpdate()
        let apple = try XCTUnwrap(loader.cachedCover(artists: chainHome.artists, album: chainHome.album))
        XCTAssertTrue(presenter.shown.first?.artwork === apple)
    }

    func testAnEarlyMissStillChecksMusicForThePreviousSongsCover() throws {
        let leftOver = try XCTUnwrap(NSImage(data: png))
        let oldSong = PlayingTrack(track: FakeTrack(album: "Another Album", persistentID: "0011"), readArtwork: { _ in leftOver })
        let playing = PlayingTrack(track: catalogTrack(), readArtwork: { _ in leftOver }, libraryCopy: { _ in nil })
        searchAnswer = answer([])
        notify(payload)
        let observer = center.addObserver(forName: .appleMusicCoverDidLoad, object: nil, queue: nil) { _ in
            XCTFail("the previous song's cover reached the strip")
        }
        defer { center.removeObserver(observer) }
        let history = SleeveHistory()
        XCTAssertNil(playing.sleeve(history: history, previousSong: { _ in oldSong }, covers: loader))
        runQueuedCompletions()
        XCTAssertNil(playing.sleeve(history: history, previousSong: { _ in oldSong }, covers: loader))
    }

    private func assertLiveAlbumArtistIdentifiesEarlyResult(afterMiss: Bool) {
        searchAnswer = answer([("Ensemble", chainHome.album, "https://is3-ssl.mzstatic.com/fs/100x100bb.jpg")])
        notify(payload)
        if afterMiss { runQueuedCompletions() }
        let playing = PlayingTrack(track: catalogTrack(albumArtist: "Ensemble"), libraryCopy: { _ in nil })
        let posted = expectation(forNotification: .appleMusicCoverDidLoad, object: nil, notificationCenter: center) { note in
            note.userInfo?[AppleMusicArtworkLoader.imageKey] is NSImage
        }
        XCTAssertNil(playing.sleeve(covers: loader))
        wait(for: [posted], timeout: 1)
        XCTAssertEqual(terms().count, 1, "the same search result already contains the right album")
    }

    func testLiveAlbumArtistCanMatchAnOutstandingSearch() {
        assertLiveAlbumArtistIdentifiesEarlyResult(afterMiss: false)
    }

    func testLiveAlbumArtistCanMatchACompletedSearch() {
        assertLiveAlbumArtistIdentifiesEarlyResult(afterMiss: true)
    }

    func testLiveAlbumArtistCanUseTheFullTitleResultEvenIfTheShortSearchFails() {
        let title = chainHome.title + " (Edit)"
        answersByTerm[chainHome.artists[0] + " " + title] = answer([
            ("Ensemble", chainHome.album, "https://is3-ssl.mzstatic.com/fs/100x100bb.jpg")
        ])
        searchAnswer = nil
        notify(payload.merging(["Name": title]) { $1 })
        runQueuedCompletions()
        let song = (title: title, artists: chainHome.artists + ["Ensemble"], album: chainHome.album)
        XCTAssertFalse(loader.hasFailedBefore(title: song.title, artists: song.artists, album: song.album),
                       "the full-title result was usable, so the first sleeve read should still wait for Apple")
        XCTAssertNotNil(load(song))
        XCTAssertEqual(terms(), [chainHome.artists[0] + " " + title, chainHome.artists[0] + " " + chainHome.title])
    }

    // MARK: - The search

    func testNewStripStartsOneSearchBeforeReadingTheHeart() {
        let track = FakeTrack(name: chainHome.title, artist: chainHome.artists[0], album: chainHome.album)
        track.objectClassCode = MusicTrackClass.urlTrack
        let playing = PlayingTrack(track: track, libraryCopy: { _ in nil })
        let identity = [track.name, track.artist, track.album].joined(separator: "|")
        let newStrip = TrackAnnouncementController.ArtworkRead.forNewStrip(listed: false)

        _ = AppDelegate.loadAnnouncementLiveTrack(playing, for: "another|artist|album", artwork: newStrip, covers: loader, failedEvents: { 0 })
        _ = AppDelegate.loadAnnouncementLiveTrack(playing, for: identity, artwork: .skip, covers: loader, failedEvents: { 0 })
        XCTAssertTrue(requests.isEmpty, "a stale notification and a refresh ask nothing")

        var searchesAtHeartRead: [Int] = []
        track.whenRead = { searchesAtHeartRead.append(self.terms().count) }
        let arrived = expectation(forNotification: .appleMusicCoverDidLoad, object: nil, notificationCenter: center) { note in
            let identities = note.userInfo?[AppleMusicArtworkLoader.identitiesKey] as? [String]
            return identities == [track.persistentID, identity] && note.userInfo?[AppleMusicArtworkLoader.imageKey] is NSImage
        }
        _ = AppDelegate.loadAnnouncementLiveTrack(playing, for: identity, artwork: newStrip, covers: loader, failedEvents: { 0 })
        XCTAssertEqual(searchesAtHeartRead, [1])
        XCTAssertNil(playing.sleeve(covers: loader), "the popover leaves the outstanding ask alone")
        wait(for: [arrived], timeout: 1)
        XCTAssertNotNil(playing.sleeve(covers: loader), "the answer is ready for a later presentation")
        XCTAssertEqual(terms().count, 1)
    }

    func testOwnedCopyOnThePlayingAlbumDoesNotStartAnAppleSearch() {
        let track = FakeTrack()
        track.objectClassCode = MusicTrackClass.urlTrack
        let copy = FakeTrack()
        let playing = PlayingTrack(track: track, libraryCopy: { _ in copy })
        _ = AppDelegate.loadAnnouncementLiveTrack(playing, for: track.persistentID, artwork: .forNewStrip(listed: true), covers: loader, failedEvents: { 0 })
        XCTAssertTrue(requests.isEmpty)
    }

    func testACopyOnAnotherReleaseSuppliesTheRatingWhileAppleFindsThePlayingCover() {
        let track = FakeTrack(name: chainHome.title, artist: chainHome.artists[0], album: chainHome.album, persistentID: "00000000000000F2")
        track.objectClassCode = MusicTrackClass.urlTrack
        let copy = FakeTrack(album: "Compilation", rating: 80)
        let playing = PlayingTrack(track: track, libraryCopy: { _ in copy })
        var searchesAtRead: [Int] = []
        copy.whenRead = { searchesAtRead.append(self.terms().count) }

        let arrived = expectation(forNotification: .appleMusicCoverDidLoad, object: nil, notificationCenter: center) { note in
            let identities = note.userInfo?[AppleMusicArtworkLoader.identitiesKey] as? [String]
            return identities?.first == track.persistentID
        }
        let load = AppDelegate.loadAnnouncementLiveTrack(playing, for: track.persistentID, artwork: .forNewStrip(listed: false), covers: loader, failedEvents: { 0 })
        guard case .loaded(let live) = load else { return XCTFail("same catalog song") }
        XCTAssertEqual(live.rating, 80)
        XCTAssertNil(live.artwork)
        wait(for: [arrived], timeout: 1)
        XCTAssertEqual(searchesAtRead, [1, 1], "the search is in flight for both the rating and the heart")
    }

    func testACatalogSongWithNoLiveIDDoesNotStartAnAppleSearch() {
        let track = FakeTrack(persistentID: "")
        track.objectClassCode = MusicTrackClass.urlTrack
        let playing = PlayingTrack(track: track, libraryCopy: { _ in nil })
        let identity = [track.name, track.artist, track.album].joined(separator: "|")
        _ = AppDelegate.loadAnnouncementLiveTrack(playing, for: identity, artwork: .forNewStrip(listed: true), covers: loader, failedEvents: { 0 })
        XCTAssertTrue(requests.isEmpty)
    }

    func testAppleStartsBeforeTheFallbackAndARetryKeepsMusicsCover() {
        let music = NSImage(size: NSSize(width: 8, height: 8))
        let apple = NSImage(size: music.size)
        for retry in [false, true] {
            var answer: ((NSImage?) -> Void)?
            var published: [NSImage?] = []
            let initial = PlayingTrack.requestCover(isRetry: retry, start: { answer = $0 }, readFallback: {
                XCTAssertNotNil(answer, "the search must be in flight before Music's fallback read")
                return music
            }, publish: { published.append($0 ?? $1) })
            XCTAssertTrue(initial === (retry ? music : nil))
            XCTAssertTrue(published.isEmpty)
            answer?(apple)
            XCTAssertEqual(published.count, 1)
            XCTAssertTrue(published.first == apple)
        }
    }

    func testAnImmediateAppleAnswerUsesTheCheckedFallbackOnce() {
        let music = NSImage(size: NSSize(width: 8, height: 8))
        let apple = NSImage(size: music.size)
        for answer in [apple, nil] {
            var reads = 0
            var publications = 0
            let initial = PlayingTrack.requestCover(isRetry: false, start: { $0(answer) }, readFallback: {
                reads += 1
                return music
            }, publish: { cover, fallback in
                XCTAssertEqual(reads, 1)
                XCTAssertTrue(cover === answer)
                XCTAssertTrue(fallback === music)
                publications += 1
            })
            XCTAssertTrue(initial === (answer ?? music))
            XCTAssertEqual(reads, 1)
            XCTAssertEqual(publications, 1)
        }
    }

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

    func testTheNinthDecodedAlbumEvictsOnlyTheOldestCover() {
        for n in 1...9 {
            let album = "Album \(n)"
            searchAnswer = answer([("Artist", album, "https://is3-ssl.mzstatic.com/\(n)/100x100bb.jpg")])
            XCTAssertNotNil(load((title: "Song", artists: ["Artist"], album: album)))
        }
        XCTAssertNil(loader.cachedCover(artists: ["Artist"], album: "Album 1"))
        for n in 2...9 {
            XCTAssertNotNil(loader.cachedCover(artists: ["Artist"], album: "Album \(n)"))
        }
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
        XCTAssertEqual(terms().count, 2, "not straight away")
        clock += AppleMusicArtworkLoader.retryAfter
        XCTAssertNil(load(bowie))
        XCTAssertEqual(terms().count, 4, "a failed search is tried again")
        clock += AppleMusicArtworkLoader.retryAfter

        answersByTerm = [:]
        XCTAssertNil(load(bowie))
        XCTAssertEqual(terms().count, 6)
        XCTAssertNil(load(bowie))
        XCTAssertEqual(terms().count, 6, "both answered without the album, so it isn't asked again")
    }

    func testAFailedSearchIsTriedAgainOnceTheWaitIsOver() {
        searchAnswer = nil
        XCTAssertNil(load(chainHome))
        searchAnswer = finding
        // Music's own cover is shown meanwhile, and the popover reads again on every update
        XCTAssertNil(load(chainHome))
        XCTAssertEqual(requests.count, 1, "a failure isn't tried again on every read")
        clock += AppleMusicArtworkLoader.retryAfter - 1
        XCTAssertNil(load(chainHome))
        XCTAssertEqual(requests.count, 1)
        clock += 1
        XCTAssertNotNil(load(chainHome))
        XCTAssertEqual(requests.count, 3)
    }

    func testAFailedDownloadIsNotKept() {
        coverAnswer = nil
        XCTAssertNil(load(chainHome))
        XCTAssertTrue(loader.isEmpty)
        clock += AppleMusicArtworkLoader.retryAfter
        coverAnswer = Data("not an image".utf8)
        XCTAssertNil(load(chainHome))
        XCTAssertTrue(loader.isEmpty)
        XCTAssertEqual(requests.count, 4)
        XCTAssertNil(load(chainHome))
        XCTAssertEqual(requests.count, 4, "a failed download waits like a failed search")
    }

    // MARK: - Whether to wait for Apple

    func testASongIsUnansweredUntilAppleHasSaidSomething() {
        // Nils Frahm's "Some", 2026-11-03: Music gave Coda's cover, and Apple had Solo's first
        let some = (title: "Some", artists: ["Nils Frahm"], album: "Solo")
        XCTAssertFalse(loader.hasAnswered(title: some.title, artists: some.artists, album: some.album))
        searchAnswer = answer([("Nils Frahm", "Solo", "https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/96/solo.jpg/100x100bb.jpg")])
        XCTAssertNotNil(load(some))
        XCTAssertNotNil(loader.cachedCover(artists: some.artists, album: some.album), "a found cover answers through the cache")
        XCTAssertEqual(requests.count, 2)
    }

    func testASongAppleHasNotIsAnswered() {
        searchAnswer = answer([("Brian Eno", "Another Green World", "https://is1-ssl.mzstatic.com/agw.jpg/100x100bb.jpg")])
        XCTAssertNil(load(chainHome))
        XCTAssertTrue(loader.hasAnswered(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
        clock += AppleMusicArtworkLoader.retryAfter * 10
        XCTAssertTrue(loader.hasAnswered(title: chainHome.title, artists: chainHome.artists, album: chainHome.album),
                      "for the rest of the session")
        XCTAssertFalse(loader.hasAnswered(title: "Marble Hill", artists: chainHome.artists, album: chainHome.album),
                       "another song of the album is another search")
    }

    func testASongAFailedSearchWasForIsAnsweredForAWhile() {
        searchAnswer = nil
        XCTAssertFalse(loader.hasFailedBefore(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
        XCTAssertNil(load(chainHome))
        XCTAssertTrue(loader.hasAnswered(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
        clock += AppleMusicArtworkLoader.retryAfter
        XCTAssertFalse(loader.hasAnswered(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
        XCTAssertTrue(loader.hasFailedBefore(title: chainHome.title, artists: chainHome.artists, album: chainHome.album),
                      "so Music's cover can stay on show while it is asked again")
    }

    func testASongAppleHasNotHasNotFailed() {
        searchAnswer = answer([("Brian Eno", "Another Green World", "https://is1-ssl.mzstatic.com/agw.jpg/100x100bb.jpg")])
        XCTAssertNil(load(chainHome))
        XCTAssertFalse(loader.hasFailedBefore(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
    }

    func testASongIsBeingAskedForUntilItsCoverComes() {
        // The answers come on the main queue, so the ask is still out when `load` returns
        let marbleHill = (title: "Marble Hill", artists: chainHome.artists, album: chainHome.album)
        XCTAssertFalse(loader.hasWaitingReader(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
        let both = expectation(description: "both answered")
        both.expectedFulfillmentCount = 2
        loader.load(title: chainHome.title, artists: chainHome.artists, album: chainHome.album) { _ in both.fulfill() }
        XCTAssertTrue(loader.hasWaitingReader(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
        XCTAssertFalse(loader.hasWaitingReader(title: marbleHill.title, artists: marbleHill.artists, album: marbleHill.album),
                       "another song of the album hasn't asked, so nothing would say when its cover comes")
        loader.load(title: marbleHill.title, artists: marbleHill.artists, album: marbleHill.album) { _ in both.fulfill() }
        XCTAssertTrue(loader.hasWaitingReader(title: marbleHill.title, artists: marbleHill.artists, album: marbleHill.album))
        wait(for: [both], timeout: 1)
        XCTAssertFalse(loader.hasWaitingReader(title: chainHome.title, artists: chainHome.artists, album: chainHome.album))
        XCTAssertFalse(loader.hasWaitingReader(title: marbleHill.title, artists: marbleHill.artists, album: marbleHill.album))
        XCTAssertEqual(requests.count, 2, "one search and one download for the album")
    }

    func testASongThatCantBeAskedAboutIsNeverBeingAskedFor() {
        XCTAssertFalse(loader.hasWaitingReader(title: "Chain Home", artists: ["Tom Rogerson & Brian Eno"], album: ""))
    }

    func testASongThatCantBeAskedAboutIsAnswered() {
        // Music's own cover stands at once, with nothing to wait for
        XCTAssertTrue(loader.hasAnswered(title: "Chain Home", artists: ["Tom Rogerson & Brian Eno"], album: ""))
        XCTAssertTrue(loader.hasAnswered(title: "Chain Home", artists: [], album: "Finding Shore"))
        XCTAssertTrue(loader.hasAnswered(title: "", artists: ["Tom Rogerson & Brian Eno"], album: "Finding Shore"))
        XCTAssertTrue(requests.isEmpty)
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
