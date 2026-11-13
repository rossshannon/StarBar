//
//  LastfmAccountTests.swift
//  StarBarTests
//
//  The Last.fm sign-in, driven with a fake transport, a fake clock for the polling, a session
//  store in memory and a stand-in for the approval page, so no browser opens and nothing
//  reaches Last.fm or the disk.
//

import XCTest
@testable import StarBar

/// The sign-in kept in memory. Locked, because the account reads and writes it on a queue
/// of its own.
private final class MemorySessionStore: LastfmSessionStore {

    private let lock = NSLock()
    private var sessions: [String: LastfmSession] = [:]

    func load(apiKey: String) -> LastfmSession? {
        lock.lock(); defer { lock.unlock() }
        return sessions[apiKey]
    }

    func save(_ session: LastfmSession, apiKey: String) {
        lock.lock(); defer { lock.unlock() }
        sessions[apiKey] = session
    }

    func delete(apiKey: String) {
        lock.lock(); defer { lock.unlock() }
        sessions[apiKey] = nil
    }

}

/// Stands in for the browser. Closing it from StarBar's side reports the close as the real
/// `ASWebAuthenticationSession` does when cancelled, so the account has to tell the two apart.
private final class FakeApprovalPage: LastfmApprovalPage {

    let url: URL
    private let closedByUser: () -> Void
    private(set) var closeCount = 0

    init(url: URL, closedByUser: @escaping () -> Void) {
        self.url = url
        self.closedByUser = closedByUser
    }

    func close() {
        closeCount += 1
        closedByUser()
    }

    /// The user closes the page themselves
    func userCloses() {
        closedByUser()
    }

    func query(_ name: String) -> String? {
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

}

final class LastfmAccountTests: XCTestCase {

    private let testCredentials = LastfmAPI.Credentials(apiKey: "testkey0123456789", sharedSecret: "testsecret")
    private let session = LastfmSession(name: "listener", key: "sessionkey")

    private var fake: FakeSpotifyTransport!
    private var clock: FakeClock!
    private var store: MemorySessionStore!
    private var pages: [FakeApprovalPage] = []
    private var pageOpens = true
    private var currentCredentials: LastfmAPI.Credentials?
    private var account: LastfmAccount!
    private var posts: [[AnyHashable: Any]] = []
    private var observer: NSObjectProtocol?

    private let tokenAnswer = FakeSpotifyTransport.Answer(status: 200, body: #"{"token":"tok1"}"#)
    private let notAuthorised = FakeSpotifyTransport.Answer(status: 403, body: #"{"error":14,"message":"Unauthorized Token - This token has not been authorized"}"#)
    private let sessionAnswer = FakeSpotifyTransport.Answer(status: 200, body: #"{"session":{"name":"listener","key":"sessionkey","subscriber":0}}"#)

    override func setUp() {
        super.setUp()
        fake = FakeSpotifyTransport()
        clock = FakeClock()
        store = MemorySessionStore()
        pages = []
        pageOpens = true
        currentCredentials = testCredentials
        posts = []
        account = LastfmAccount(
            store: store,
            transport: fake.transport,
            credentials: { [unowned self] in self.currentCredentials },
            clock: clock,
            openApprovalPage: { [unowned self] url, _, closedByUser in
                guard self.pageOpens else { return nil }
                let page = FakeApprovalPage(url: url, closedByUser: closedByUser)
                self.pages.append(page)
                return page
            })
        observer = NotificationCenter.default.addObserver(forName: .lastfmAccountDidChange, object: account, queue: nil) { [unowned self] notification in
            self.posts.append(notification.userInfo ?? [:])
        }
    }

    override func tearDown() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        account = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Let the hops to the main queue run, a few rounds deep, then the store's queue
    private func settle() {
        for _ in 0..<4 {
            let done = expectation(description: "main queue drained")
            DispatchQueue.main.async { done.fulfill() }
            wait(for: [done], timeout: 1)
        }
        account.waitForStore()
    }

    /// Press Connect and let Last.fm's token arrive, which opens the page
    @discardableResult
    private func connectToPage(file: StaticString = #filePath, line: UInt = #line) -> FakeApprovalPage? {
        fake.answers = [tokenAnswer]
        account.connect(presentingFrom: nil)
        settle()
        XCTAssertEqual(pages.count, 1, "the approval page should open once the token arrives", file: file, line: line)
        return pages.last
    }

    /// One poll tick and its answer
    private func tick(answer: FakeSpotifyTransport.Answer?) {
        fake.answers = answer.map { [$0] } ?? []
        clock.fireRepeating()
        settle()
    }

    private func method(of index: Int) -> String? {
        guard fake.requests.indices.contains(index) else { return nil }
        return LastfmAPI.formParameters(of: fake.requests[index])["method"]
    }

    private var sessionRequestCount: Int {
        return fake.requests.indices.filter { method(of: $0) == "auth.getSession" }.count
    }

    // MARK: - Connecting

    func testConnectAsksForATokenAndOpensTheApprovalPage() {
        let page = connectToPage()
        XCTAssertEqual(fake.requests.count, 1, "connecting should send one request before any tick")
        XCTAssertEqual(method(of: 0), "auth.getToken", "connecting should start with auth.getToken")
        XCTAssertEqual(page?.query("token"), "tok1", "the approval page should carry the token Last.fm gave")
        XCTAssertEqual(page?.query("api_key"), testCredentials.apiKey, "the approval page should carry the API key")
        XCTAssertEqual(account.state, .connecting)
        XCTAssertEqual(clock.pendingRepeating.count, 1, "asking for the session should be on a repeating timer")
        XCTAssertEqual(clock.pendingRepeating.first?.seconds, LastfmAccount.pollInterval)
    }

    func testNotAuthorisedKeepsAskingUntilASessionConnects() {
        let page = connectToPage()
        tick(answer: notAuthorised)
        XCTAssertEqual(method(of: 1), "auth.getSession", "a tick should ask for the session")
        XCTAssertEqual(fake.requests.count > 1 ? LastfmAPI.formParameters(of: fake.requests[1])["token"] : nil, "tok1", "the ask should name the token")
        XCTAssertEqual(account.state, .connecting, "'not authorised yet' must leave the sign-in going")
        XCTAssertNil(account.lastProblem, "'not authorised yet' is not a problem")
        tick(answer: notAuthorised)
        XCTAssertEqual(sessionRequestCount, 2, "each tick should ask again while the token isn't approved")

        tick(answer: sessionAnswer)
        XCTAssertEqual(account.state, .connected)
        XCTAssertEqual(account.username, "listener")
        XCTAssertNotNil(account.sender, "a connected account should have a sender")
        XCTAssertNil(account.lastProblem)
        // The fake page reports its close as the real one does; counting that as the user
        // closing would send one more ask
        XCTAssertEqual(page?.closeCount, 1, "the page should be closed once the session arrives")
        XCTAssertEqual(store.load(apiKey: testCredentials.apiKey), session, "the session should be saved for the API key")
        XCTAssertTrue(clock.pendingRepeating.isEmpty, "asking should stop once connected")
        clock.fireRepeating()
        settle()
        XCTAssertEqual(sessionRequestCount, 3, "nothing more should be asked once connected")
    }

    func testOnlyOneSessionAskIsInFlightAtATime() {
        connectToPage()
        fake.answersAtOnce = false
        for _ in 0..<5 {
            clock.fireRepeating()
        }
        settle()
        // Catches asking on every tick whatever is still on its way
        XCTAssertEqual(sessionRequestCount, 1, "ticks while an ask is on its way should not ask again")
        fake.answers = [notAuthorised]
        fake.answerPending()
        settle()
        clock.fireRepeating()
        settle()
        XCTAssertEqual(sessionRequestCount, 2, "once the answer is in, the next tick should ask again")
    }

    func testClosingThePageBeforeApprovingEndsQuietlyAfterOneLastAsk() {
        let page = connectToPage()
        fake.answers = [notAuthorised]
        page?.userCloses()
        settle()
        XCTAssertEqual(sessionRequestCount, 1, "closing the page should make one last ask")
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertNil(account.lastProblem, "closing the page is not a problem to show")
        XCTAssertTrue(clock.pendingRepeating.isEmpty, "asking should stop once the page is closed")
        XCTAssertEqual(page?.closeCount, 0, "a page the user closed shouldn't be closed again")
    }

    func testApprovingThenClosingThePageBetweenTicksConnects() {
        let page = connectToPage()
        fake.answers = [sessionAnswer]
        page?.userCloses()
        settle()
        // Catches giving up as soon as the page closes without the last ask
        XCTAssertEqual(account.state, .connected, "the last ask should find the approved session")
        XCTAssertEqual(account.username, "listener")
    }

    func testAnAskOnItsWayWhenThePageClosesIsTheLast() {
        let page = connectToPage()
        fake.answersAtOnce = false
        clock.fireRepeating()
        settle()
        page?.userCloses()
        settle()
        XCTAssertEqual(sessionRequestCount, 1, "with an ask on its way, closing the page shouldn't send another")
        fake.answers = [notAuthorised]
        fake.answerPending()
        settle()
        XCTAssertEqual(account.state, .disconnected, "the ask on its way was the last")
        XCTAssertNil(account.lastProblem)
        XCTAssertEqual(sessionRequestCount, 1)
    }

    private func assertRefusal(code: Int, file: StaticString = #filePath, line: UInt = #line) {
        let page = connectToPage(file: file, line: line)
        tick(answer: FakeSpotifyTransport.Answer(status: 403, body: "{\"error\":\(code),\"message\":\"No\"}"))
        XCTAssertEqual(account.state, .disconnected, "error \(code) should end the sign-in", file: file, line: line)
        XCTAssertEqual(account.lastProblem, "Last.fm refused the sign-in (error \(code)).", file: file, line: line)
        XCTAssertEqual(page?.closeCount, 1, "the page should be closed when Last.fm refuses", file: file, line: line)
        XCTAssertTrue(clock.pendingRepeating.isEmpty, "asking should stop when Last.fm refuses", file: file, line: line)
    }

    func testAnExpiredTokenEndsTheSignIn() {
        assertRefusal(code: 15)
    }

    func testABadTokenEndsTheSignIn() {
        assertRefusal(code: 4)
    }

    func testAskingStopsAfterTheTimeLimit() {
        let page = connectToPage()
        clock.advance(by: LastfmAccount.pollLimit)
        tick(answer: notAuthorised)
        XCTAssertEqual(sessionRequestCount, 0, "a tick past the limit should not ask")
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertEqual(account.lastProblem, "The Last.fm sign-in timed out. Try again.")
        XCTAssertEqual(page?.closeCount, 1, "the page should be closed when time runs out")
    }

    func testAChangedAPIKeyGivesUpTheSignIn() {
        let page = connectToPage()
        currentCredentials = LastfmAPI.Credentials(apiKey: "otherkey", sharedSecret: "othersecret")
        tick(answer: sessionAnswer)
        XCTAssertEqual(sessionRequestCount, 0, "a token for one key should not be asked about under another")
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertEqual(page?.closeCount, 1)
    }

    func testWithoutCredentialsNothingIsSent() {
        currentCredentials = nil
        XCTAssertFalse(account.canConnect, "a build without a key can't connect")
        account.connect(presentingFrom: nil)
        settle()
        XCTAssertTrue(fake.requests.isEmpty, "nothing should be sent without credentials")
        XCTAssertTrue(pages.isEmpty)
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertEqual(account.lastProblem, "This copy of StarBar was built without a Last.fm key, so it can't connect.")
        XCTAssertEqual(posts.count, 1, "the problem should be posted for Preferences")
    }

    func testCanConnectWithCredentials() {
        XCTAssertTrue(account.canConnect)
    }

    func testATokenRequestWithNoAnswerSaysLastfmCouldNotBeReached() {
        fake.answers = []
        account.connect(presentingFrom: nil)
        settle()
        XCTAssertEqual(account.lastProblem, "Couldn't reach Last.fm.")
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertTrue(pages.isEmpty, "no page should open without a token")
    }

    func testATokenRefusedNamesTheError() {
        fake.answers = [FakeSpotifyTransport.Answer(status: 403, body: #"{"error":10,"message":"Invalid API key"}"#)]
        account.connect(presentingFrom: nil)
        settle()
        XCTAssertEqual(account.lastProblem, "Last.fm didn't start the sign-in (error 10).")
        XCTAssertEqual(account.state, .disconnected)
    }

    func testAPageThatCannotOpenSaysSo() {
        pageOpens = false
        fake.answers = [tokenAnswer]
        account.connect(presentingFrom: nil)
        settle()
        XCTAssertEqual(account.lastProblem, "The Last.fm sign-in couldn't open.")
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertTrue(clock.pendingRepeating.isEmpty, "nothing should be asked without a page")
    }

    func testALateSessionAfterDisconnectIsIgnored() {
        let page = connectToPage()
        fake.answersAtOnce = false
        clock.fireRepeating()
        settle()
        account.disconnect()
        fake.answers = [sessionAnswer]
        fake.answerPending()
        settle()
        // Catches a sign-in the user gave up on connecting after all
        XCTAssertEqual(account.state, .disconnected, "an answer for a sign-in given up should be ignored")
        XCTAssertNil(account.username)
        XCTAssertNil(store.load(apiKey: testCredentials.apiKey), "nothing should be saved for a sign-in given up")
        XCTAssertEqual(page?.closeCount, 1, "Disconnect should close the page")
    }

    // MARK: - Signed in

    func testRestoreConnectsWithoutTheNetwork() {
        account.restore(session, credentials: testCredentials)
        XCTAssertEqual(account.state, .connected)
        XCTAssertTrue(account.isConnected)
        XCTAssertEqual(account.username, "listener")
        XCTAssertNotNil(account.sender)
        XCTAssertTrue(fake.requests.isEmpty, "restoring should send nothing")
        XCTAssertEqual(posts.count, 1)
    }

    func testDisconnectForgetsTheSessionAndNamesTheUser() {
        store.save(session, apiKey: testCredentials.apiKey)
        account.restore(session, credentials: testCredentials)
        account.disconnect()
        settle()
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertNil(account.username)
        XCTAssertNil(account.sender)
        XCTAssertNil(store.load(apiKey: testCredentials.apiKey), "Disconnect should delete the stored session")
        XCTAssertEqual(posts.last?[LastfmAccount.disconnectedUserKey] as? String, "listener", "the scrobbler needs the name to drop what was waiting for them")
    }

    func testARejectedSessionKeepsWhatWasWaiting() {
        store.save(session, apiKey: testCredentials.apiKey)
        account.restore(session, credentials: testCredentials)
        account.sessionWasRejected()
        settle()
        XCTAssertEqual(account.state, .disconnected)
        XCTAssertNil(account.username)
        XCTAssertEqual(account.lastProblem, "Last.fm ended the sign-in. Connect again to carry on scrobbling.")
        XCTAssertNil(store.load(apiKey: testCredentials.apiKey), "a rejected session should be deleted")
        // Catches the scrobbler deleting the user's waiting scrobbles on a rejected key
        XCTAssertNil(posts.last?[LastfmAccount.disconnectedUserKey], "a rejected session must not name the user")
    }

    func testARejectedSessionWithNobodySignedInDoesNothing() {
        account.sessionWasRejected()
        XCTAssertTrue(posts.isEmpty)
        XCTAssertNil(account.lastProblem)
    }

    // MARK: - Problems

    func testTheSameProblemTwicePostsOnce() {
        account.note(.network)
        account.note(.network)
        // Catches a loop with the scrobbler, which notes failures and listens to this
        XCTAssertEqual(posts.count, 1, "the same problem again should not post")
        XCTAssertEqual(account.lastProblem, "Couldn't reach Last.fm. What you play is kept and sent later.")
        account.note(.temporary(16))
        XCTAssertEqual(posts.count, 2, "a different problem should post")
        XCTAssertEqual(account.lastProblem, "Last.fm is busy or down. What you play is kept and sent later.")
    }

    func testProblemTexts() {
        account.note(.credentialsRejected(26))
        XCTAssertEqual(account.lastProblem, "Last.fm isn't accepting StarBar's key (error 26).")
        account.note(.refused(6))
        XCTAssertEqual(account.lastProblem, "Last.fm answered with an error (6).")
        account.note(.sessionInvalid)
        account.note(.tokenNotAuthorized)
        XCTAssertEqual(account.lastProblem, "Last.fm answered with an error (6).", "these failures have their own handling and show nothing here")
    }

    func testSuccessClearsTheProblemOnce() {
        account.note(.network)
        posts = []
        account.noteSuccess()
        XCTAssertNil(account.lastProblem)
        XCTAssertEqual(posts.count, 1, "clearing a problem should post")
        account.noteSuccess()
        XCTAssertEqual(posts.count, 1, "with no problem to clear, nothing should post")
    }

}
