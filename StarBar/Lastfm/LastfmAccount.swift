//
//  LastfmAccount.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Cocoa
import AuthenticationServices
import os

extension Notification.Name {
    /// Connected, disconnected, connecting, or a new problem to show. Main thread.
    /// `userInfo[LastfmAccount.disconnectedUserKey]` is the user's name when they pressed
    /// Disconnect, and absent otherwise.
    static let lastfmAccountDidChange = Notification.Name("StarBarLastfmAccountDidChange")
}

/// What the scrobbler needs of the sign-in, so tests can give it a fake
protocol LastfmAccountProviding: AnyObject {
    /// The signed-in user's name, or nil when nobody is signed in
    var username: String? { get }
    /// Sends for the signed-in user, or nil
    var sender: LastfmSending? { get }
    /// Last.fm said the session key is no good: drop the sign-in and say so in Preferences
    func sessionWasRejected()
    /// A request failed, for Preferences
    func note(_ failure: LastfmAPI.Failure)
    /// A request worked: there is no problem to show any more
    func noteSuccess()
}


/// Last.fm's approval page while it is open. A seam so tests can stand in for the browser.
protocol LastfmApprovalPage: AnyObject {
    /// Close the page from StarBar's side. This never counts as the user closing it.
    func close()
}

/// The user's Last.fm sign-in.
///
/// Opt-in, like `SpotifyAccount`: nothing here touches the network until the user presses
/// Connect in Preferences. Connecting is Last.fm's desktop flow, since it has no OAuth:
/// 1. `auth.getToken` gives a token.
/// 2. The user approves it on last.fm, in an `ASWebAuthenticationSession`, so the password
///    goes to Last.fm's own page and never through StarBar.
/// 3. Last.fm's page doesn't send the browser back to the app, so StarBar asks
///    `auth.getSession` every `pollInterval` while the page is open, one ask at a time. Until
///    the user allows access the answer is "not authorised yet", which leaves the token good.
///    When it answers with a session, the page is closed and the session kept.
/// If the user closes the page themselves, one last ask is made, in case they allowed access
/// first. Asking stops after `pollLimit`, a token's own life being an hour.
///
/// A sign-in that is overtaken (Disconnect, or the API key changing under it) ignores the
/// answers still on their way.
///
/// The session key never expires. It is kept in a file (`FileLastfmSessionStore`) per API
/// key, and dropped on Disconnect or when Last.fm rejects it.
///
/// Main thread only.
final class LastfmAccount: NSObject, LastfmAccountProviding {

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
    }

    /// Opens the approval page at a URL over a window. The last argument is called on the
    /// main thread when the user closes the page; nil means the page couldn't open.
    typealias OpenApprovalPage = (_ url: URL, _ window: NSWindow?, _ closedByUser: @escaping () -> Void) -> LastfmApprovalPage?

    static let shared = LastfmAccount()

    static let disconnectedUserKey = "disconnectedUser"
    /// How often `auth.getSession` is asked while the approval page is open
    static let pollInterval: TimeInterval = 2.5
    /// How long it goes on asking
    static let pollLimit: TimeInterval = 10 * 60
    /// The scheme `ASWebAuthenticationSession` is told to wait for. Last.fm's page never
    /// sends the browser to it; the session is closed from here.
    static let callbackScheme = "starbar"

    private(set) var state: State = .disconnected
    /// Why the last connect or request failed, for Preferences. Cleared by the next success.
    private(set) var lastProblem: String?

    /// One sign-in in progress, from the moment Last.fm gave its token
    private final class SignIn {
        let token: String
        let credentials: LastfmAPI.Credentials
        let startedAt: Date
        var timer: RatingReminderTimer?
        /// An `auth.getSession` is on its way
        var isAsking = false
        /// Nil once the page has closed, by the user or from here
        var page: LastfmApprovalPage?
        /// The user closed the page: the ask now on its way, or the one made for this, is the last
        var closedByUser = false

        init(token: String, credentials: LastfmAPI.Credentials, startedAt: Date) {
            self.token = token
            self.credentials = credentials
            self.startedAt = startedAt
        }
    }

    private let store: LastfmSessionStore
    private let transport: SpotifyLibrary.Transport
    private let credentials: () -> LastfmAPI.Credentials?
    private let clock: RatingReminderClock
    private let openApprovalPage: OpenApprovalPage
    private var session: LastfmSession?
    private var client: LastfmClient?
    private var signIn: SignIn?
    /// Counts connects and their endings, so a token answer for a connect that has since been
    /// given up is ignored. Answers to `auth.getSession` are matched by their `SignIn`.
    private var attempt = 0
    private weak var presentationWindow: NSWindow?
    private let storeQueue = DispatchQueue(label: "com.rossshannon.starbar.lastfm-session", qos: .utility)

    /// Same test as `SpotifyAccount`'s: a test run must never sign in or read the stored session
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init(store: LastfmSessionStore = FileLastfmSessionStore(),
         transport: @escaping SpotifyLibrary.Transport = SpotifyLibrary.urlSessionTransport,
         credentials: @escaping () -> LastfmAPI.Credentials? = LastfmCredentials.current,
         clock: RatingReminderClock = RunLoopClock(),
         openApprovalPage: @escaping OpenApprovalPage = WebLastfmApprovalPage.open) {
        self.store = store
        self.transport = transport
        self.credentials = credentials
        self.clock = clock
        self.openApprovalPage = openApprovalPage
        super.init()
    }

    /// The signed-in user's name
    var username: String? {
        return session?.name
    }

    var sender: LastfmSending? {
        return client
    }

    var isConnected: Bool {
        return state == .connected
    }

    /// False when this build has no Last.fm key or secret (`LastfmCredentials.current()`),
    /// so Preferences can say so instead of offering Connect
    var canConnect: Bool {
        return credentials() != nil
    }

    /// Load the session kept from a previous launch, off the main thread. Never under tests
    /// or UI tests.
    func start() {
        guard !LastfmAccount.isRunningTests, !MenuBarRatingControl.isUITesting,
              let apiKey = credentials()?.apiKey else { return }
        storeQueue.async { [weak self, store] in
            guard let session = store.load(apiKey: apiKey) else { return }
            DispatchQueue.main.async {
                // A sign-in made meanwhile, or a key changed meanwhile, wins
                guard let self = self, self.session == nil, self.state != .connecting,
                      let current = self.credentials(), current.apiKey == apiKey else { return }
                self.restore(session, credentials: current)
            }
        }
    }

    /// Sign in with a session kept from before. Internal so tests can start signed in.
    func restore(_ session: LastfmSession, credentials: LastfmAPI.Credentials) {
        os_log("%{public}s[%{public}ld], %{public}s: signed in to Last.fm as %{public}s", ((#file as NSString).lastPathComponent), #line, #function, session.name)
        self.session = session
        client = LastfmClient(credentials: credentials, session: session, transport: transport)
        state = .connected
        lastProblem = nil
        postAccountChange()
    }

    /// Open Last.fm's approval page over `window` and keep the session it leads to
    func connect(presentingFrom window: NSWindow?) {
        guard state != .connecting else { return }
        guard let credentials = credentials() else {
            lastProblem = "This copy of StarBar was built without a Last.fm key, so it can't connect."
            postAccountChange()
            return
        }
        endSignIn()
        let attempt = self.attempt
        presentationWindow = window
        state = .connecting
        lastProblem = nil
        postAccountChange()
        transport(LastfmAPI.tokenRequest(credentials: credentials)) { [weak self] data, response in
            DispatchQueue.main.async {
                self?.tokenArrived(data: data, response: response, credentials: credentials, attempt: attempt)
            }
        }
    }

    /// Forget the sign-in, here and in its file, and say who it was in the notification so
    /// the scrobbler deletes what was waiting for them. Last.fm keeps StarBar's access until
    /// the user removes it under Applications in their Last.fm settings, which Preferences
    /// says.
    func disconnect() {
        let name = session?.name
        signOut()
        lastProblem = nil
        var userInfo: [AnyHashable: Any]?
        if let name = name {
            userInfo = [LastfmAccount.disconnectedUserKey: name]
        }
        postAccountChange(userInfo: userInfo)
    }

    /// As `disconnect()`, but says why in Preferences, and the notification names no user, so
    /// what was waiting to be sent for them is kept for when they connect again
    func sessionWasRejected() {
        guard let name = session?.name else { return }
        os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm rejected the session for %{public}s", ((#file as NSString).lastPathComponent), #line, #function, name)
        signOut()
        lastProblem = "Last.fm ended the sign-in. Connect again to carry on scrobbling."
        postAccountChange()
    }

    /// Posts only when the text shown changes, since the scrobbler calls this for every failed
    /// request and listens to the notification it posts
    func note(_ failure: LastfmAPI.Failure) {
        let problem: String
        switch failure {
        case .network:
            problem = "Couldn't reach Last.fm. What you play is kept and sent later."
        case .temporary:
            problem = "Last.fm is busy or down. What you play is kept and sent later."
        case .credentialsRejected(let code):
            problem = "Last.fm isn't accepting StarBar's key (error \(code))."
        case .refused(let code):
            problem = "Last.fm answered with an error (\(code))."
        case .sessionInvalid, .tokenNotAuthorized:
            return
        }
        guard problem != lastProblem else { return }
        lastProblem = problem
        postAccountChange()
    }

    func noteSuccess() {
        guard lastProblem != nil else { return }
        lastProblem = nil
        postAccountChange()
    }

    /// Wait for the session file's reads and writes queued so far. For tests.
    func waitForStore() {
        storeQueue.sync {}
    }

    // MARK: - Signing in

    private func tokenArrived(data: Data?, response: HTTPURLResponse?, credentials: LastfmAPI.Credentials, attempt: Int) {
        guard attempt == self.attempt, state == .connecting else { return }
        let failure = LastfmAPI.failure(data: data, response: response)
        guard failure == nil, let token = data.flatMap(LastfmAPI.parseToken) else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm gave no sign-in token: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, failure.map { "\($0)" } ?? "unreadable answer")
            switch failure {
            case .some(.network), .some(.temporary):
                fail("Couldn't reach Last.fm.")
            default:
                fail(LastfmAccount.sentence("Last.fm didn't start the sign-in", code: failure.flatMap(LastfmAccount.code(of:))))
            }
            return
        }
        guard self.credentials()?.apiKey == credentials.apiKey else {
            fail(nil)
            return
        }
        let signIn = SignIn(token: token, credentials: credentials, startedAt: clock.now())
        self.signIn = signIn
        let url = LastfmAPI.authorizationURL(apiKey: credentials.apiKey, token: token)
        let page = openApprovalPage(url, presentationWindow) { [weak self, weak signIn] in
            guard let self = self, let signIn = signIn else { return }
            self.pageClosedByUser(signIn)
        }
        guard let opened = page else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: the Last.fm sign-in didn't open", ((#file as NSString).lastPathComponent), #line, #function)
            endSignIn()
            fail("The Last.fm sign-in couldn't open.")
            return
        }
        signIn.page = opened
        signIn.timer = clock.schedule(after: LastfmAccount.pollInterval, repeats: true) { [weak self, weak signIn] in
            guard let self = self, let signIn = signIn else { return }
            self.tick(signIn)
        }
    }

    private func tick(_ signIn: SignIn) {
        guard self.signIn === signIn else { return }
        if clock.now().timeIntervalSince(signIn.startedAt) >= LastfmAccount.pollLimit {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: the Last.fm sign-in timed out", ((#file as NSString).lastPathComponent), #line, #function)
            endSignIn()
            fail("The Last.fm sign-in timed out. Try again.")
            return
        }
        guard credentials()?.apiKey == signIn.credentials.apiKey else {
            // A token for another key can't be turned into a session for this one
            endSignIn()
            fail(nil)
            return
        }
        ask(signIn)
    }

    private func ask(_ signIn: SignIn) {
        guard !signIn.isAsking else { return }
        signIn.isAsking = true
        transport(LastfmAPI.sessionRequest(token: signIn.token, credentials: signIn.credentials)) { [weak self] data, response in
            DispatchQueue.main.async {
                self?.sessionArrived(data: data, response: response, for: signIn)
            }
        }
    }

    private func sessionArrived(data: Data?, response: HTTPURLResponse?, for signIn: SignIn) {
        // An answer for a sign-in given up or replaced says nothing
        guard self.signIn === signIn else { return }
        signIn.isAsking = false
        let failure = LastfmAPI.failure(data: data, response: response)
        if failure == nil, let session = data.flatMap(LastfmAPI.parseSession) {
            finish(signIn, with: session)
            return
        }
        if signIn.closedByUser {
            // As cancelling a Spotify sign-in does, closing the page says nothing went wrong
            os_log("%{public}s[%{public}ld], %{public}s: Last.fm sign-in closed before access was allowed", ((#file as NSString).lastPathComponent), #line, #function)
            endSignIn()
            fail(nil)
            return
        }
        switch failure {
        case .some(.tokenNotAuthorized), .some(.network), .some(.temporary):
            return
        default:
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm refused the sign-in: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, failure.map { "\($0)" } ?? "unreadable answer")
            endSignIn()
            fail(LastfmAccount.sentence("Last.fm refused the sign-in", code: failure.flatMap(LastfmAccount.code(of:))))
        }
    }

    private func pageClosedByUser(_ signIn: SignIn) {
        // A page closed from here, or one for a sign-in already over, says nothing
        guard self.signIn === signIn, signIn.page != nil else { return }
        signIn.page = nil
        signIn.closedByUser = true
        signIn.timer?.invalidate()
        signIn.timer = nil
        // With an ask already on its way, its answer is the last
        ask(signIn)
    }

    private func finish(_ signIn: SignIn, with session: LastfmSession) {
        endSignIn()
        let apiKey = signIn.credentials.apiKey
        storeQueue.async { [store] in store.save(session, apiKey: apiKey) }
        restore(session, credentials: signIn.credentials)
    }

    /// Stop any sign-in in progress: its timer, its page, and the answers still to come
    private func endSignIn() {
        attempt += 1
        guard let signIn = signIn else { return }
        self.signIn = nil
        signIn.timer?.invalidate()
        signIn.timer = nil
        let page = signIn.page
        // Cleared before closing, so the page's own report of closing counts for nothing
        signIn.page = nil
        page?.close()
    }

    /// Drop the sign-in here and in its file, without posting
    private func signOut() {
        endSignIn()
        if let apiKey = client?.credentials.apiKey ?? credentials()?.apiKey {
            storeQueue.async { [store] in store.delete(apiKey: apiKey) }
        }
        session = nil
        client = nil
        state = .disconnected
    }

    private func fail(_ problem: String?) {
        lastProblem = problem
        state = session == nil ? .disconnected : .connected
        postAccountChange()
    }

    private func postAccountChange(userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: .lastfmAccountDidChange, object: self, userInfo: userInfo)
    }

    /// The Last.fm error code or HTTP status a failure carries, for the text Preferences shows
    private static func code(of failure: LastfmAPI.Failure) -> Int? {
        switch failure {
        case .network:
            return nil
        case .temporary(let code), .credentialsRejected(let code), .refused(let code):
            return code
        case .sessionInvalid:
            return 9
        case .tokenNotAuthorized:
            return 14
        }
    }

    private static func sentence(_ text: String, code: Int?) -> String {
        guard let code = code else { return "\(text)." }
        return "\(text) (error \(code))."
    }

}

/// The approval page in an `ASWebAuthenticationSession`, sharing the browser's cookies so
/// someone already signed in to last.fm there only has to press "Yes, allow access".
///
/// Last.fm's page never sends the browser to `LastfmAccount.callbackScheme`, so the session
/// ends only when the user closes it or StarBar does. Main thread only.
final class WebLastfmApprovalPage: NSObject, LastfmApprovalPage, ASWebAuthenticationPresentationContextProviding {

    private var session: ASWebAuthenticationSession?
    private weak var window: NSWindow?
    /// Closed, by either side: the session's completion then says nothing more
    private var isClosed = false

    private init(window: NSWindow?) {
        self.window = window
        super.init()
    }

    /// Open the page at `url` over `window`, or answer nil if it couldn't open
    static func open(_ url: URL, over window: NSWindow?, closedByUser: @escaping () -> Void) -> LastfmApprovalPage? {
        let page = WebLastfmApprovalPage(window: window)
        // Whatever the session reports, it means the page has closed
        let finished: ASWebAuthenticationSession.CompletionHandler = { [weak page] _, _ in
            DispatchQueue.main.async {
                guard let page = page, !page.isClosed else { return }
                page.isClosed = true
                page.session = nil
                closedByUser()
            }
        }
        let session: ASWebAuthenticationSession
        if #available(macOS 14.4, *) {
            session = ASWebAuthenticationSession(url: url, callback: .customScheme(LastfmAccount.callbackScheme), completionHandler: finished)
        } else {
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: LastfmAccount.callbackScheme, completionHandler: finished)
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = page
        page.session = session
        guard session.start() else {
            page.isClosed = true
            page.session = nil
            return nil
        }
        return page
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        session?.cancel()
        session = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window ?? NSApp.keyWindow ?? ASPresentationAnchor()
    }

}
