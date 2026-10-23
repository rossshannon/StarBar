//
//  SpotifyLibraryTests.swift
//  StarBarTests
//
//  The Web API client and the account's liked songs, driven through a fake transport. No
//  network, no Keychain, no sign-in window.
//

import XCTest
@testable import StarBar

/// Answers requests from a queue the test fills, and records what was sent
final class FakeSpotifyTransport {

    struct Answer {
        var status: Int
        var body: String = ""
        var headers: [String: String] = [:]
    }

    private(set) var requests: [URLRequest] = []
    var answers: [Answer] = []
    /// When false, requests wait in `pending` until the test answers them
    var answersAtOnce = true
    private(set) var pending: [(URLRequest, (Data?, HTTPURLResponse?) -> Void)] = []

    lazy var transport: SpotifyLibrary.Transport = { [unowned self] request, completion in
        self.requests.append(request)
        if self.answersAtOnce {
            self.answer(request, completion)
        } else {
            self.pending.append((request, completion))
        }
    }

    func answerPending() {
        let waiting = pending
        pending = []
        waiting.forEach { answer($0.0, $0.1) }
    }

    private func answer(_ request: URLRequest, _ completion: (Data?, HTTPURLResponse?) -> Void) {
        guard !answers.isEmpty else {
            completion(nil, nil)
            return
        }
        let answer = answers.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)
        completion(Data(answer.body.utf8), response)
    }

    var summary: [String] {
        return requests.map { "\($0.httpMethod ?? "?") \($0.url?.absoluteString ?? "")" }
    }

}

final class FakeSpotifyTokenStore: SpotifyTokenStore {
    var tokens: [String: SpotifyToken] = [:]
    func load(clientID: String) -> SpotifyToken? { tokens[clientID] }
    func save(_ token: SpotifyToken, clientID: String) { tokens[clientID] = token }
    func delete(clientID: String) { tokens[clientID] = nil }
}

final class SpotifyLibraryTests: XCTestCase {

    private let song = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var fake: FakeSpotifyTransport!
    private var library: SpotifyLibrary!
    private var tokenChanges: [SpotifyToken?] = []

    override func setUp() {
        super.setUp()
        fake = FakeSpotifyTransport()
        tokenChanges = []
        library = makeLibrary(expiresIn: 3600)
    }

    private func makeLibrary(expiresIn: TimeInterval) -> SpotifyLibrary {
        let token = SpotifyToken(accessToken: "A1", refreshToken: "R1", expiresAt: now.addingTimeInterval(expiresIn))
        let library = SpotifyLibrary(clientID: "abc123", token: token, transport: fake.transport, now: { [unowned self] in self.now })
        library.tokenDidChange = { [unowned self] in self.tokenChanges.append($0) }
        return library
    }

    private func contains() -> Result<Bool, SpotifyLibrary.Failure>? {
        var result: Result<Bool, SpotifyLibrary.Failure>?
        library.contains(song) { result = $0 }
        return result
    }

    func testOnlySongsAndEpisodesCanBeLiked() {
        XCTAssertTrue(SpotifyLibrary.canLike(song))
        XCTAssertTrue(SpotifyLibrary.canLike("spotify:episode:512ojhOuo1ktJprKbVcKyQ"))
        XCTAssertFalse(SpotifyLibrary.canLike("spotify:local:Artist:Album:Song:215"))
        XCTAssertFalse(SpotifyLibrary.canLike("spotify:ad:abc"))
        XCTAssertFalse(SpotifyLibrary.canLike("spotify:track:"))
        XCTAssertFalse(SpotifyLibrary.canLike("spotify:track:abc,spotify:track:def"))
        XCTAssertFalse(SpotifyLibrary.canLike("spotify:track:abc&uris=x"))
    }

    func testAnUnsupportedURIIsNeverSent() {
        var result: Result<Bool, SpotifyLibrary.Failure>?
        library.contains("spotify:local:a:b:c:1") { result = $0 }
        XCTAssertEqual(result, .failure(.unsupported))
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testContainsAsksTheLibraryEndpointWithTheBearerToken() throws {
        fake.answers = [.init(status: 200, body: "[true]")]

        XCTAssertEqual(contains(), .success(true))
        let request = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.spotify.com/v1/me/library/contains?uris=spotify%3Atrack%3A4uLU6hMCjMI75M1A2tKUQC")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer A1")
    }

    func testLikingPutsAndUnlikingDeletes() {
        fake.answers = [.init(status: 200), .init(status: 200)]
        var results: [Result<Void, SpotifyLibrary.Failure>] = []
        library.setLiked(true, uri: song) { results.append($0) }
        library.setLiked(false, uri: song) { results.append($0) }

        XCTAssertEqual(fake.summary, [
            "PUT https://api.spotify.com/v1/me/library?uris=spotify%3Atrack%3A4uLU6hMCjMI75M1A2tKUQC",
            "DELETE https://api.spotify.com/v1/me/library?uris=spotify%3Atrack%3A4uLU6hMCjMI75M1A2tKUQC",
        ])
        XCTAssertEqual(results.count, 2)
        XCTAssertNotNil(fake.requests.first?.httpBody, "a PUT goes with a body, so it has a Content-Length")
    }

    func testATokenAboutToExpireIsRefreshedFirst() {
        library = makeLibrary(expiresIn: 30)
        fake.answers = [
            .init(status: 200, body: #"{"access_token":"A2","expires_in":3600,"refresh_token":"R2"}"#),
            .init(status: 200, body: "[false]"),
        ]

        XCTAssertEqual(contains(), .success(false))
        XCTAssertEqual(fake.requests.map { $0.url?.host }, ["accounts.spotify.com", "api.spotify.com"])
        XCTAssertEqual(fake.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer A2")
        XCTAssertEqual(tokenChanges.count, 1)
        XCTAssertEqual(tokenChanges.first??.refreshToken, "R2")
    }

    func testA401IsRefreshedAndTriedOnceMore() {
        fake.answers = [
            .init(status: 401),
            .init(status: 200, body: #"{"access_token":"A2","expires_in":3600}"#),
            .init(status: 200, body: "[true]"),
        ]

        XCTAssertEqual(contains(), .success(true))
        XCTAssertEqual(fake.requests.count, 3)
        // The refresh answer had no refresh token, so the old one is kept
        XCTAssertEqual(library.token?.refreshToken, "R1")
    }

    func testASecond401IsNotRetriedAgain() {
        fake.answers = [
            .init(status: 401),
            .init(status: 200, body: #"{"access_token":"A2","expires_in":3600}"#),
            .init(status: 401),
        ]

        XCTAssertEqual(contains(), .failure(.http(401)))
        XCTAssertEqual(fake.requests.count, 3)
    }

    func testARevokedSignInDropsTheTokens() {
        library = makeLibrary(expiresIn: 0)
        fake.answers = [.init(status: 400, body: #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#)]

        XCTAssertEqual(contains(), .failure(.signInExpired))
        XCTAssertNil(library.token)
        XCTAssertEqual(tokenChanges.count, 1)
        XCTAssertNil(tokenChanges[0])

        // And nothing more is sent
        XCTAssertEqual(contains(), .failure(.notSignedIn))
        XCTAssertEqual(fake.requests.count, 1)
    }

    /// A refresh that fails for another reason (Spotify down) keeps the sign-in
    func testAFailedRefreshKeepsTheSignIn() {
        library = makeLibrary(expiresIn: 0)
        fake.answers = [.init(status: 503)]

        XCTAssertEqual(contains(), .failure(.http(503)))
        XCTAssertNotNil(library.token)
        XCTAssertTrue(tokenChanges.isEmpty)
    }

    func testRequestsDuringOneRefreshShareIt() {
        library = makeLibrary(expiresIn: 0)
        fake.answersAtOnce = false
        var results: [Result<Bool, SpotifyLibrary.Failure>] = []
        library.contains(song) { results.append($0) }
        library.contains("spotify:track:0000000000000000000000") { results.append($0) }
        XCTAssertEqual(fake.pending.count, 1, "one refresh for both")

        fake.answers = [.init(status: 200, body: #"{"access_token":"A2","expires_in":3600}"#)]
        fake.answerPending()
        XCTAssertEqual(fake.pending.count, 2)
        fake.answers = [.init(status: 200, body: "[true]"), .init(status: 200, body: "[false]")]
        fake.answerPending()

        XCTAssertEqual(results, [.success(true), .success(false)])
    }

    func testA429StopsRequestsUntilRetryAfterHasPassed() {
        fake.answers = [.init(status: 429, headers: ["Retry-After": "120"])]
        let until = now.addingTimeInterval(120)

        XCTAssertEqual(contains(), .failure(.rateLimited(until: until)))
        now = now.addingTimeInterval(60)
        XCTAssertEqual(contains(), .failure(.rateLimited(until: until)))
        XCTAssertEqual(fake.requests.count, 1)

        now = now.addingTimeInterval(61)
        fake.answers = [.init(status: 200, body: "[true]")]
        XCTAssertEqual(contains(), .success(true))
    }

    func testA429WithoutRetryAfterWaitsTheDefault() {
        fake.answers = [.init(status: 429)]
        XCTAssertEqual(contains(), .failure(.rateLimited(until: now.addingTimeInterval(SpotifyLibrary.defaultRetryAfter))))
    }

    func testNoAnswerIsANetworkFailure() {
        XCTAssertEqual(contains(), .failure(.network))
        fake.answers = [.init(status: 200, body: "not json")]
        XCTAssertEqual(contains(), .failure(.network))
    }

}

final class SpotifyAccountLikeTests: XCTestCase {

    private let song = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
    private var fake: FakeSpotifyTransport!
    private var account: SpotifyAccount!
    private var likeChanges: [String] = []
    private var observer: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        fake = FakeSpotifyTransport()
        account = SpotifyAccount(store: FakeSpotifyTokenStore(), transport: fake.transport)
        likeChanges = []
        observer = NotificationCenter.default.addObserver(forName: .spotifyLikeDidChange, object: account, queue: nil) { [unowned self] notification in
            self.likeChanges.append(notification.userInfo?[SpotifyPlayer.identityKey] as? String ?? "")
        }
    }

    override func tearDown() {
        observer.map(NotificationCenter.default.removeObserver)
        super.tearDown()
    }

    private func signIn() {
        account.restore(SpotifyToken(accessToken: "A1", refreshToken: "R1", expiresAt: Date().addingTimeInterval(3600)), clientID: "abc123")
    }

    func testNothingIsKnownOrSentWithoutASignIn() {
        account.refreshLike(for: song)
        XCTAssertNil(account.isLiked(song))
        XCTAssertFalse(account.canLike(song))
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testASongIsAskedAboutOnce() {
        signIn()
        fake.answers = [.init(status: 200, body: "[true]")]
        account.refreshLike(for: song)
        account.refreshLike(for: song)

        XCTAssertEqual(account.isLiked(song), true)
        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertEqual(likeChanges, [song])
    }

    func testABurstOfNotificationsAsksOnce() {
        signIn()
        fake.answersAtOnce = false
        account.refreshLike(for: song)
        account.refreshLike(for: song)
        XCTAssertEqual(fake.pending.count, 1)
    }

    func testLikingShowsAtOnce() {
        signIn()
        fake.answers = [.init(status: 200, body: "[false]")]
        account.refreshLike(for: song)
        fake.answersAtOnce = false

        account.toggleLike(song)
        XCTAssertEqual(account.isLiked(song), true, "before Spotify has answered")
        XCTAssertEqual(fake.requests.last?.httpMethod, "PUT")

        fake.answers = [.init(status: 200)]
        fake.answerPending()
        XCTAssertEqual(account.isLiked(song), true)
        XCTAssertNil(account.lastProblem)
    }

    func testARefusedLikeIsPutBack() {
        signIn()
        fake.answers = [.init(status: 200, body: "[true]"), .init(status: 403)]
        account.refreshLike(for: song)

        account.toggleLike(song)

        XCTAssertEqual(fake.requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(account.isLiked(song), true)
        XCTAssertNotNil(account.lastProblem)
    }

    func testARevokedSignInDisconnects() {
        signIn()
        // Expired at once, and Spotify refuses the refresh
        account.restore(SpotifyToken(accessToken: "A1", refreshToken: "R1", expiresAt: Date()), clientID: "abc123")
        fake.answers = [.init(status: 400, body: #"{"error":"invalid_grant"}"#)]

        account.refreshLike(for: song)

        XCTAssertEqual(account.state, .disconnected)
        XCTAssertNil(account.isLiked(song))
        XCTAssertNotNil(account.lastProblem)
    }

    func testDisconnectingForgetsWhatWasLiked() {
        signIn()
        fake.answers = [.init(status: 200, body: "[true]")]
        account.refreshLike(for: song)

        account.disconnect()

        XCTAssertEqual(account.state, .disconnected)
        XCTAssertNil(account.isLiked(song))
        account.toggleLike(song)
        XCTAssertEqual(fake.requests.count, 1)
    }

}
