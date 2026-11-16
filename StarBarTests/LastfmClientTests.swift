//
//  LastfmClientTests.swift
//  StarBarTests
//
//  The Last.fm client over a fake transport, and the sign-in file in a temporary folder.
//  No network, and nothing outside the temporary folder is written.
//

import XCTest
@testable import StarBar

final class LastfmClientTests: XCTestCase {

    private let credentials = LastfmAPI.Credentials(apiKey: "abc123", sharedSecret: "s3cret")
    private let session = LastfmSession(name: "listener", key: "sess-key")
    private var fake: FakeSpotifyTransport!
    private var client: LastfmClient!

    override func setUp() {
        super.setUp()
        fake = FakeSpotifyTransport()
        client = LastfmClient(credentials: credentials, session: session, transport: fake.transport)
    }

    private func scrobbles(_ count: Int) -> [Scrobble] {
        return (0..<count).map { Scrobble(track: .test("Song \($0)"), startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 300), source: "music") }
    }

    /// Runs `call` and waits for its completion, which the client delivers on a later turn
    /// of the main queue
    private func result<T>(_ call: (@escaping (T) -> Void) -> Void) -> T? {
        let done = expectation(description: "completion")
        var answer: T?
        call { value in
            XCTAssertTrue(Thread.isMainThread, "completions run on the main thread")
            answer = value
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        return answer
    }

    // MARK: - Scrobbling

    func testAScrobbleBatchAnswersWithLastfmsSummary() throws {
        fake.answers = [.init(status: 200, body: #"{"scrobbles":{"@attr":{"accepted":1,"ignored":1},"scrobble":[{"ignoredMessage":{"code":"0"}},{"ignoredMessage":{"code":"3"}}]}}"#)]
        let answer: Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>? = result { client.scrobble(scrobbles(2), completion: $0) }
        XCTAssertEqual(answer, .success(LastfmAPI.ScrobbleSummary(accepted: 1, ignored: 1, ignoredCodes: [3])))

        let request = try XCTUnwrap(fake.requests.first)
        let fields = LastfmAPI.formParameters(of: request)
        XCTAssertEqual(fields["method"], "track.scrobble")
        XCTAssertEqual(fields["sk"], "sess-key", "signed for this user")
        XCTAssertEqual(fields["track[1]"], "Song 1")
    }

    func testAnEmptyBatchSendsNothing() {
        let answer: Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>? = result { client.scrobble([], completion: $0) }
        XCTAssertEqual(answer, .success(LastfmAPI.ScrobbleSummary(accepted: 0, ignored: 0, ignoredCodes: [])))
        XCTAssertTrue(fake.requests.isEmpty, "no request for nothing")
    }

    /// Catches failing a batch Last.fm took but answered oddly: it would be sent again and
    /// every song in it scrobbled twice
    func testAnUnreadableSuccessStillCountsTheBatchAsTaken() {
        fake.answers = [.init(status: 200, body: "{}")]
        let answer: Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>? = result { client.scrobble(scrobbles(3), completion: $0) }
        XCTAssertEqual(answer, .success(LastfmAPI.ScrobbleSummary(accepted: 3, ignored: 0, ignoredCodes: [])))
    }

    func testAnInvalidSessionIsReported() {
        fake.answers = [.init(status: 403, body: #"{"error":9,"message":"Invalid session key - Please re-authenticate"}"#)]
        let answer: Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>? = result { client.scrobble(scrobbles(1), completion: $0) }
        XCTAssertEqual(answer, .failure(.sessionInvalid))
    }

    func testNoAnswerIsTheNetwork() {
        fake.answers = []
        let answer: Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>? = result { client.scrobble(scrobbles(1), completion: $0) }
        XCTAssertEqual(answer, .failure(.network), "kept to send again later")
        XCTAssertEqual(fake.requests.count, 1)
    }

    /// Catches sending a song Last.fm can't take in with others, which could cost the batch
    func testASongWithNoArtistIsLeftOutOfABatch() {
        fake.answers = [.init(status: 200, body: "{}")]
        var batch = scrobbles(2)
        batch.append(Scrobble(track: Scrobble.Track(title: "Untitled", artist: "  "), startedAt: Date(timeIntervalSince1970: 1_700_001_000), source: "music"))
        let answer: Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>? = result { client.scrobble(batch, completion: $0) }
        XCTAssertEqual(answer, .success(LastfmAPI.ScrobbleSummary(accepted: 2, ignored: 1, ignoredCodes: [])))
        let fields = LastfmAPI.formParameters(of: fake.requests[0])
        XCTAssertNil(fields["track[2]"], "only the two that can be sent are")
    }

    // MARK: - Now playing and hearts

    func testNowPlayingSendsTheSong() {
        fake.answers = [.init(status: 200, body: #"{"nowplaying":{}}"#)]
        let answer: Result<Void, LastfmAPI.Failure>? = result { client.updateNowPlaying(.test("Song"), completion: $0) }
        XCTAssertNotNil(try? answer?.get(), "a 200 with a JSON object worked")
        XCTAssertEqual(LastfmAPI.formParameters(of: fake.requests[0])["method"], "track.updateNowPlaying")
    }

    func testASongWithNoArtistIsRefusedWithoutARequest() {
        var answer: Result<Void, LastfmAPI.Failure>?
        client.updateNowPlaying(Scrobble.Track(title: "Song", artist: ""), completion: { answer = $0 })
        XCTAssertEqual(answer.map(describe), describe(.failure(.refused(6))), "Last.fm's own answer to a missing artist")

        var loveAnswer: Result<Void, LastfmAPI.Failure>?
        client.setLoved(true, title: " ", artist: "Artist", completion: { loveAnswer = $0 })
        XCTAssertEqual(loveAnswer.map(describe), describe(.failure(.refused(6))))
        XCTAssertTrue(fake.requests.isEmpty, "nothing is sent for a song Last.fm can't take")
    }

    func testLoveSendsTrackLoveWithTheSessionKey() throws {
        fake.answers = [.init(status: 200, body: "{}")]
        let answer: Result<Void, LastfmAPI.Failure>? = result { client.setLoved(true, title: "Song", artist: "Artist", completion: $0) }
        XCTAssertEqual(answer.map(describe), describe(.success(())))

        let fields = LastfmAPI.formParameters(of: try XCTUnwrap(fake.requests.first))
        XCTAssertEqual(fields["method"], "track.love")
        XCTAssertEqual(fields["sk"], "sess-key")
        XCTAssertEqual(fields["track"], "Song")
        XCTAssertEqual(fields["artist"], "Artist")
    }

    func testUnloveFailureIsPassedOn() {
        fake.answers = [.init(status: 200, body: #"{"error":29,"message":"Rate limit exceeded"}"#)]
        let answer: Result<Void, LastfmAPI.Failure>? = result { client.setLoved(false, title: "Song", artist: "Artist", completion: $0) }
        XCTAssertEqual(answer.map(describe), describe(.failure(.temporary(29))))
        XCTAssertEqual(LastfmAPI.formParameters(of: fake.requests[0])["method"], "track.unlove")
    }

    /// `Result<Void, _>` isn't Equatable, so compare what it says
    private func describe(_ result: Result<Void, LastfmAPI.Failure>) -> String {
        switch result {
        case .success: return "success"
        case .failure(let failure): return "failure \(failure)"
        }
    }

    // MARK: - The sign-in file

    private func temporaryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testTheSignInRoundTripsPerAPIKey() {
        let store = FileLastfmSessionStore(directory: temporaryFolder())
        XCTAssertNil(store.load(apiKey: "abc123"))
        store.save(session, apiKey: "abc123")
        XCTAssertEqual(store.load(apiKey: "abc123"), session)
        XCTAssertNil(store.load(apiKey: "other"), "a sign-in belongs to the key it was made with")
    }

    func testDeletingTheSignInRemovesIt() {
        let store = FileLastfmSessionStore(directory: temporaryFolder())
        store.save(session, apiKey: "abc123")
        store.delete(apiKey: "abc123")
        XCTAssertNil(store.load(apiKey: "abc123"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(apiKey: "abc123").path))
        store.delete(apiKey: "abc123")  // deleting what isn't there is harmless
    }

    func testOnlyTheUserCanReadTheSignIn() throws {
        let folder = temporaryFolder()
        let store = FileLastfmSessionStore(directory: folder)
        store.save(session, apiKey: "abc123")
        let file = try FileManager.default.attributesOfItem(atPath: store.url(apiKey: "abc123").path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directory = try FileManager.default.attributesOfItem(atPath: folder.path)
        XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testAnAPIKeyCannotEscapeTheFolder() {
        let store = FileLastfmSessionStore(directory: URL(fileURLWithPath: "/tmp/lastfm"))
        XCTAssertEqual(store.url(apiKey: "../../etc/pässwd").path, "/tmp/lastfm/sign-in-etcpsswd.json")
    }

}
