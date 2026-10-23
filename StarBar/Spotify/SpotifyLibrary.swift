//
//  SpotifyLibrary.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-10-23.
//

import Foundation
import os

/// Whether a Spotify song is in the user's Liked Songs, and liking or unliking it, through
/// Spotify's Web API.
///
/// Since February 2026 that is one set of endpoints for every kind of item, addressed by URI:
/// `GET /me/library/contains`, `PUT /me/library` and `DELETE /me/library`, each with a `uris`
/// query parameter. The Track ID in Spotify's own notification is that URI already, so no
/// search or lookup is needed. Only songs and episodes are sent: a local file has no ID the
/// Web API knows.
///
/// The access token lasts an hour. One about to expire is refreshed first, and a 401 is
/// refreshed and tried once more. A refresh Spotify refuses with `invalid_grant` means the
/// sign-in is gone (revoked on spotify.com, or the app deleted), so the tokens are dropped.
/// A 429 stops all requests until its `Retry-After` has passed: the quota is per developer
/// app, and hammering it would only lengthen the wait.
///
/// Main thread only. The transport's completion may run anywhere; the client hops to main.
final class SpotifyLibrary {

    /// Sends a request. `URLSession` in the app; a fake in tests.
    typealias Transport = (_ request: URLRequest, _ completion: @escaping (Data?, HTTPURLResponse?) -> Void) -> Void

    static let libraryURL = URL(string: "https://api.spotify.com/v1/me/library")!
    static let timeout: TimeInterval = 10
    /// How long to stop after a 429 that doesn't say
    static let defaultRetryAfter: TimeInterval = 30

    enum Failure: Error, Equatable {
        /// No tokens: the user hasn't connected, or disconnected
        case notSignedIn
        /// Spotify refused the refresh token. Connecting again is the only way back.
        case signInExpired
        case rateLimited(until: Date)
        /// Not a URI the Web API can like (a local file, an ad)
        case unsupported
        /// No answer, or one that couldn't be read
        case network
        case http(Int)
    }

    let clientID: String
    private(set) var token: SpotifyToken?
    /// Called whenever the tokens change, to keep them; with nil when the sign-in is gone
    var tokenDidChange: ((SpotifyToken?) -> Void)?

    private let transport: Transport
    private let now: () -> Date
    private var blockedUntil: Date?
    /// Callers waiting on a refresh already under way, so a burst of requests refreshes once
    private var refreshWaiters: [(Result<String, Failure>) -> Void]?

    init(clientID: String, token: SpotifyToken?, transport: @escaping Transport = SpotifyLibrary.urlSessionTransport, now: @escaping () -> Date = Date.init) {
        self.clientID = clientID
        self.token = token
        self.transport = transport
        self.now = now
    }

    /// True for a URI the Web API can save: a song or an episode, with a base-62 ID
    static func canLike(_ uri: String) -> Bool {
        for prefix in ["spotify:track:", "spotify:episode:"] where uri.hasPrefix(prefix) {
            let id = uri.dropFirst(prefix.count)
            return !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        return false
    }

    /// Whether `uri` is in the user's library
    func contains(_ uri: String, completion: @escaping (Result<Bool, Failure>) -> Void) {
        send("GET", path: "contains", uri: uri) { result in
            completion(result.flatMap { (data: Data?) -> Result<Bool, Failure> in
                guard let data = data,
                      let answer = (try? JSONSerialization.jsonObject(with: data)) as? [Bool],
                      let first = answer.first else { return .failure(.network) }
                return .success(first)
            })
        }
    }

    /// Add `uri` to the user's library, or take it out
    func setLiked(_ liked: Bool, uri: String, completion: @escaping (Result<Void, Failure>) -> Void) {
        send(liked ? "PUT" : "DELETE", path: nil, uri: uri) { result in
            completion(result.map { _ in () })
        }
    }

    /// The request for one URI. Its query is encoded the way Spotify's examples are.
    static func request(method: String, path: String?, uri: String, accessToken: String) -> URLRequest {
        let url = path.map { libraryURL.appendingPathComponent($0) } ?? libraryURL
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = "uris=" + SpotifyAuth.formEncode(uri)
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if method != "GET" {
            // An empty body rather than none, so a Content-Length goes with it: Spotify has
            // answered 411 to a bodiless PUT on its older library endpoints
            request.httpBody = Data()
        }
        request.timeoutInterval = timeout
        return request
    }

}

// MARK: - Requests

extension SpotifyLibrary {

    private func send(_ method: String, path: String?, uri: String, isRetry: Bool = false, completion: @escaping (Result<Data?, Failure>) -> Void) {
        guard SpotifyLibrary.canLike(uri) else {
            completion(.failure(.unsupported))
            return
        }
        if let until = blockedUntil, now() < until {
            completion(.failure(.rateLimited(until: until)))
            return
        }
        accessToken(forceRefresh: isRetry) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let failure):
                completion(.failure(failure))
            case .success(let accessToken):
                let request = SpotifyLibrary.request(method: method, path: path, uri: uri, accessToken: accessToken)
                self.perform(request) { data, response in
                    guard let response = response else {
                        completion(.failure(.network))
                        return
                    }
                    switch response.statusCode {
                    case 200..<300:
                        completion(.success(data))
                    case 401 where !isRetry:
                        os_log("%{public}s[%{public}ld], %{public}s: Spotify answered 401; refreshing the token and trying once more", ((#file as NSString).lastPathComponent), #line, #function)
                        self.send(method, path: path, uri: uri, isRetry: true, completion: completion)
                    case 429:
                        let until = self.now().addingTimeInterval(SpotifyLibrary.retryAfter(response))
                        self.blockedUntil = until
                        os_log(.error, "%{public}s[%{public}ld], %{public}s: Spotify is rate limiting StarBar until %{public}s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: until))
                        completion(.failure(.rateLimited(until: until)))
                    default:
                        os_log(.error, "%{public}s[%{public}ld], %{public}s: Spotify answered %{public}ld to %{public}s", ((#file as NSString).lastPathComponent), #line, #function, response.statusCode, method)
                        completion(.failure(.http(response.statusCode)))
                    }
                }
            }
        }
    }

    /// `Retry-After` in seconds, or the default when it's missing or unreadable
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)), seconds > 0 else {
            return defaultRetryAfter
        }
        return seconds
    }

    /// A usable access token: the one held, unless it is about to expire or was just refused
    private func accessToken(forceRefresh: Bool, completion: @escaping (Result<String, Failure>) -> Void) {
        guard let token = token else {
            completion(.failure(.notSignedIn))
            return
        }
        if !forceRefresh, !token.isExpired(at: now()) {
            completion(.success(token.accessToken))
            return
        }
        if refreshWaiters != nil {
            refreshWaiters?.append(completion)
            return
        }
        refreshWaiters = [completion]
        let request = SpotifyAuth.refreshRequest(refreshToken: token.refreshToken, clientID: clientID)
        perform(request) { [weak self] data, response in
            guard let self = self else { return }
            let result = self.refreshed(data: data, response: response, previous: token)
            let waiters = self.refreshWaiters ?? []
            self.refreshWaiters = nil
            waiters.forEach { $0(result) }
        }
    }

    private func refreshed(data: Data?, response: HTTPURLResponse?, previous: SpotifyToken) -> Result<String, Failure> {
        guard let response = response else { return .failure(.network) }
        if response.statusCode == 200, let data = data,
           let token = SpotifyToken.parse(data, now: now(), previousRefreshToken: previous.refreshToken) {
            self.token = token
            tokenDidChange?(token)
            return .success(token.accessToken)
        }
        if response.statusCode == 400, SpotifyToken.errorCode(data) == "invalid_grant" {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Spotify refused the refresh token; the user must connect again", ((#file as NSString).lastPathComponent), #line, #function)
            token = nil
            tokenDidChange?(nil)
            return .failure(.signInExpired)
        }
        os_log(.error, "%{public}s[%{public}ld], %{public}s: refreshing the Spotify token failed with %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, response.statusCode)
        return .failure(.http(response.statusCode))
    }

    /// Send through the transport and answer on the main thread
    private func perform(_ request: URLRequest, completion: @escaping (Data?, HTTPURLResponse?) -> Void) {
        transport(request) { data, response in
            if Thread.isMainThread {
                completion(data, response)
            } else {
                DispatchQueue.main.async { completion(data, response) }
            }
        }
    }

    static func urlSessionTransport(_ request: URLRequest, completion: @escaping (Data?, HTTPURLResponse?) -> Void) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                os_log(.error, "%{public}s[%{public}ld], %{public}s: %{public}s failed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, request.url?.host ?? "?", error.localizedDescription)
            }
            completion(data, response as? HTTPURLResponse)
        }.resume()
    }

}
