//
//  SpotifyAccount.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-10-23.
//

import Cocoa
import AuthenticationServices
import os

extension Notification.Name {
    /// Connected, disconnected, or connecting. Main thread.
    static let spotifyAccountDidChange = Notification.Name("StarBarSpotifyAccountDidChange")
    /// What StarBar knows about whether a song is liked changed.
    /// `userInfo[SpotifyPlayer.identityKey]` is its Track ID. Main thread.
    static let spotifyLikeDidChange = Notification.Name("StarBarSpotifyLikeDidChange")
}

/// The user's Spotify sign-in, and what it has found out about their Liked Songs.
///
/// Opt-in: nothing here touches the network until the user pastes a client ID into
/// Preferences and presses Connect. The sign-in runs in `ASWebAuthenticationSession`, so the
/// password goes to Spotify's own page and never through StarBar. Once connected:
/// - each new song or episode in Spotify costs one `contains` request, so the menu bar's heart
///   can say whether it is liked. Nothing is polled: a song liked in Spotify itself shows when
///   it next comes round, or when StarBar's own heart is clicked.
/// - clicking the heart likes or unlikes the song. The heart changes at once and changes back
///   if Spotify refuses.
///
/// Main thread only.
final class SpotifyAccount: NSObject {

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
    }

    static let shared = SpotifyAccount()

    private(set) var state: State = .disconnected
    /// Why the last connect or request failed, for Preferences. Cleared by the next success.
    private(set) var lastProblem: String?

    private let store: SpotifyTokenStore
    private let transport: SpotifyLibrary.Transport
    private var library: SpotifyLibrary?
    private var session: ASWebAuthenticationSession?
    private weak var presentationWindow: NSWindow?
    /// Liked or not, by Track ID, for the last few songs asked about
    private var liked: [(uri: String, isLiked: Bool)] = []
    /// Songs whose `contains` is in flight, so a burst of notifications asks once
    private var asking: Set<String> = []
    private let tokenQueue = DispatchQueue(label: "com.rossshannon.starbar.spotify-tokens", qos: .utility)

    static let likedCacheSize = 32

    /// Same test as `SpotifyPlayer`'s: a test run must never sign in or read the Keychain
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init(store: SpotifyTokenStore = KeychainSpotifyTokenStore(), transport: @escaping SpotifyLibrary.Transport = SpotifyLibrary.urlSessionTransport) {
        self.store = store
        self.transport = transport
        super.init()
    }

    var clientID: String {
        return UserDefaults.standard.spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The user changed the client ID in Preferences. A sign-in made with another one belongs
    /// to a different app on Spotify's side, so it is dropped.
    func clientIDDidChange() {
        guard let library = library, library.clientID != clientID else { return }
        os_log("%{public}s[%{public}ld], %{public}s: client ID changed; disconnecting from Spotify", ((#file as NSString).lastPathComponent), #line, #function)
        disconnect()
    }

    /// Load the tokens kept from a previous launch, off the main thread because the Keychain
    /// can stop to ask. Never under tests.
    func start() {
        guard !SpotifyAccount.isRunningTests, !MenuBarRatingControl.isUITesting else { return }
        let clientID = self.clientID
        guard !clientID.isEmpty else { return }
        tokenQueue.async { [weak self] in
            guard let self = self, let token = self.store.load(clientID: clientID) else { return }
            DispatchQueue.main.async {
                guard self.library == nil, self.clientID == clientID else { return }
                self.restore(token, clientID: clientID)
            }
        }
    }

    /// Sign in with tokens kept from before. Internal so tests can start signed in.
    func restore(_ token: SpotifyToken, clientID: String) {
        os_log("%{public}s[%{public}ld], %{public}s: Spotify sign-in restored", ((#file as NSString).lastPathComponent), #line, #function)
        use(SpotifyLibrary(clientID: clientID, token: token, transport: transport))
    }

    var isConnected: Bool {
        return state == .connected
    }

    /// Whether a song is liked, if StarBar has asked. Nil when not connected or not known yet.
    func isLiked(_ uri: String) -> Bool? {
        guard state == .connected else { return nil }
        return liked.first { $0.uri == uri }?.isLiked
    }

    /// True when clicking the heart for `uri` can like it
    func canLike(_ uri: String?) -> Bool {
        guard state == .connected, let uri = uri else { return false }
        return SpotifyLibrary.canLike(uri)
    }

    /// Ask Spotify whether `uri` is liked, unless that is already known or being asked
    func refreshLike(for uri: String) {
        guard let library = library, SpotifyLibrary.canLike(uri), isLiked(uri) == nil, !asking.contains(uri) else { return }
        asking.insert(uri)
        library.contains(uri) { [weak self, weak library] result in
            guard let self = self else { return }
            self.asking.remove(uri)
            switch result {
            case .success(let isLiked):
                // An answer for a sign-in that has since gone, or been replaced, says nothing
                guard let library = library, self.library === library else { return }
                self.lastProblem = nil
                self.remember(isLiked, for: uri)
            case .failure(let failure):
                self.note(failure)
            }
        }
    }

    /// Like or unlike `uri`. The new state shows at once and is put back if Spotify refuses.
    func toggleLike(_ uri: String) {
        guard let library = library, SpotifyLibrary.canLike(uri) else { return }
        let wasLiked = isLiked(uri) ?? false
        let wantsLiked = !wasLiked
        os_log("%{public}s[%{public}ld], %{public}s: %{public}s %{public}s in Spotify", ((#file as NSString).lastPathComponent), #line, #function, wantsLiked ? "Liking" : "Unliking", uri)
        remember(wantsLiked, for: uri)
        library.setLiked(wantsLiked, uri: uri) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.lastProblem = nil
            case .failure(let failure):
                // Only put it back if nothing has changed it since
                if self.isLiked(uri) == wantsLiked {
                    self.remember(wasLiked, for: uri)
                }
                self.note(failure)
            }
        }
    }

    private func remember(_ isLiked: Bool, for uri: String) {
        liked.removeAll { $0.uri == uri }
        liked.append((uri, isLiked))
        if liked.count > SpotifyAccount.likedCacheSize {
            liked.removeFirst(liked.count - SpotifyAccount.likedCacheSize)
        }
        NotificationCenter.default.post(name: .spotifyLikeDidChange, object: self, userInfo: [SpotifyPlayer.identityKey: uri])
    }

    private func note(_ failure: SpotifyLibrary.Failure) {
        switch failure {
        case .notSignedIn, .unsupported:
            return
        case .signInExpired:
            lastProblem = "Spotify ended the sign-in. Connect again to like songs."
            // The library has already dropped its tokens and said so through tokenDidChange
        case .rateLimited:
            lastProblem = "Spotify is limiting requests from your app for a while."
        case .network:
            lastProblem = "Couldn't reach Spotify."
        case .http(let status):
            lastProblem = status == 403
                ? "Spotify refused (403). Check that your Spotify account is a user of the app in the dashboard."
                : "Spotify answered with an error (\(status))."
        }
        postAccountChange()
    }

    private func use(_ library: SpotifyLibrary?) {
        self.library = library
        liked = []
        asking = []
        let clientID = library?.clientID ?? ""
        library?.tokenDidChange = { [weak self, weak library] token in
            // A library replaced since has no say over the sign-in
            guard let self = self, let library = library, self.library === library else { return }
            if let token = token {
                self.tokenQueue.async { self.store.save(token, clientID: clientID) }
            } else {
                self.tokenQueue.async { self.store.delete(clientID: clientID) }
                self.use(nil)
            }
        }
        state = library == nil ? .disconnected : .connected
        postAccountChange()
        // The song already playing gets its heart without waiting for the next one
        if let uri = SpotifyPlayer.shared.latest?.trackID {
            refreshLike(for: uri)
        }
    }

    private func postAccountChange() {
        NotificationCenter.default.post(name: .spotifyAccountDidChange, object: self)
    }

}

// MARK: - Connecting

extension SpotifyAccount: ASWebAuthenticationPresentationContextProviding {

    /// Open Spotify's sign-in page over `window`, and keep the tokens it leads to
    func connect(presentingFrom window: NSWindow?) {
        let clientID = self.clientID
        guard !clientID.isEmpty, state != .connecting else { return }
        session?.cancel()
        let pkce = SpotifyAuth.PKCE.random()
        let expectedState = SpotifyAuth.randomToken()
        let url = SpotifyAuth.authorizationURL(clientID: clientID, pkce: pkce, state: expectedState)
        let finished: ASWebAuthenticationSession.CompletionHandler = { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                self?.signInFinished(callbackURL: callbackURL, error: error, clientID: clientID, pkce: pkce, expectedState: expectedState)
            }
        }
        let session: ASWebAuthenticationSession
        if #available(macOS 14.4, *) {
            session = ASWebAuthenticationSession(url: url, callback: .customScheme(SpotifyAuth.callbackScheme), completionHandler: finished)
        } else {
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: SpotifyAuth.callbackScheme, completionHandler: finished)
        }
        // Share the browser's cookies, so someone already signed in to Spotify there only
        // has to agree
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = self
        presentationWindow = window
        self.session = session
        lastProblem = nil
        state = .connecting
        postAccountChange()
        if !session.start() {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: the Spotify sign-in didn't start", ((#file as NSString).lastPathComponent), #line, #function)
            fail("The Spotify sign-in couldn't open.")
        }
    }

    /// Forget the sign-in, here and in the Keychain. Spotify keeps the app's access until the
    /// user removes it under Apps on their account page, which Preferences says.
    func disconnect() {
        session?.cancel()
        session = nil
        let clientID = library?.clientID ?? self.clientID
        tokenQueue.async { [store] in store.delete(clientID: clientID) }
        lastProblem = nil
        use(nil)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return presentationWindow ?? NSApp.keyWindow ?? ASPresentationAnchor()
    }

    private func signInFinished(callbackURL: URL?, error: Error?, clientID: String, pkce: SpotifyAuth.PKCE, expectedState: String) {
        session = nil
        if let error = error {
            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            os_log("%{public}s[%{public}ld], %{public}s: Spotify sign-in ended: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            fail(cancelled ? nil : "The Spotify sign-in failed: \(error.localizedDescription)")
            return
        }
        guard let callbackURL = callbackURL else {
            fail("Spotify didn't send StarBar back a sign-in.")
            return
        }
        switch SpotifyAuth.code(fromCallback: callbackURL, expectedState: expectedState) {
        case .failure(.denied(let reason)):
            fail(reason == "access_denied" ? nil : "Spotify refused the sign-in (\(reason)).")
        case .failure:
            fail("Spotify's answer didn't match this sign-in.")
        case .success(let code):
            let request = SpotifyAuth.tokenRequest(code: code, clientID: clientID, verifier: pkce.verifier)
            transport(request) { [weak self] data, response in
                DispatchQueue.main.async {
                    self?.tokensArrived(data: data, response: response, clientID: clientID)
                }
            }
        }
    }

    private func tokensArrived(data: Data?, response: HTTPURLResponse?, clientID: String) {
        guard response?.statusCode == 200, let data = data, let token = SpotifyToken.parse(data, now: Date()) else {
            let code = SpotifyToken.errorCode(data) ?? response.map { "\($0.statusCode)" } ?? "no answer"
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Spotify token exchange failed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, code)
            fail("Spotify didn't accept the sign-in (\(code)).")
            return
        }
        os_log("%{public}s[%{public}ld], %{public}s: connected to Spotify", ((#file as NSString).lastPathComponent), #line, #function)
        tokenQueue.async { [store] in store.save(token, clientID: clientID) }
        lastProblem = nil
        use(SpotifyLibrary(clientID: clientID, token: token, transport: transport))
    }

    private func fail(_ problem: String?) {
        lastProblem = problem
        state = library == nil ? .disconnected : .connected
        postAccountChange()
    }

}
