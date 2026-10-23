//
//  SpotifyAuth.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-10-23.
//

import Foundation
import CryptoKit
import Security
import os

/// The pieces of Spotify's sign-in that don't need a window or the network: the PKCE pair,
/// the authorisation URL, the token requests and the parsing of their answers.
///
/// Spotify's Web API is the only way to like a song: its AppleScript can't, and `starred`
/// raises. The sign-in is the Authorization Code flow with PKCE, which needs no client secret,
/// so nothing secret ships in the app. Each user registers their own app on Spotify's
/// developer dashboard and pastes its client ID into Preferences: since Spotify's February
/// 2026 changes, an app in Development Mode serves at most five users, so one shared ID
/// would stop working at the sixth.
enum SpotifyAuth {

    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let callbackScheme = "starbar"
    /// What the user registers on their app in Spotify's dashboard. Spotify allows a custom
    /// scheme for native apps, though it prefers https where there is a web page to go to.
    static let redirectURI = "starbar://spotify-callback"
    /// Reading whether a song is liked, and liking it. Nothing else.
    static let scopes = ["user-library-read", "user-library-modify"]
    static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    /// A PKCE code verifier and its S256 challenge (RFC 7636)
    struct PKCE: Equatable {
        let verifier: String
        let challenge: String

        init(verifier: String) {
            self.verifier = verifier
            self.challenge = SpotifyAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }

        /// 32 random bytes, base64url-encoded: 43 characters, the shortest RFC 7636 allows
        static func random() -> PKCE {
            return PKCE(verifier: SpotifyAuth.randomToken())
        }
    }

    /// The page the user signs in on
    static func authorizationURL(clientID: String, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    enum CallbackError: Error, Equatable {
        /// The user pressed Cancel on Spotify's page, or Spotify refused
        case denied(String)
        /// Not the sign-in this app started
        case stateMismatch
        case noCode
    }

    /// The code from the redirect Spotify sends back, once its `state` is checked
    static func code(fromCallback url: URL, expectedState: String) -> Result<String, CallbackError> {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { return .failure(.stateMismatch) }
        if let error = value("error") { return .failure(.denied(error)) }
        guard let code = value("code"), !code.isEmpty else { return .failure(.noCode) }
        return .success(code)
    }

    /// Exchange the sign-in's code for tokens
    static func tokenRequest(code: String, clientID: String, verifier: String) -> URLRequest {
        return formRequest([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", verifier),
        ])
    }

    /// Swap a refresh token for a new access token
    static func refreshRequest(refreshToken: String, clientID: String) -> URLRequest {
        return formRequest([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID),
        ])
    }

    private static func formRequest(_ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(fields.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&").utf8)
        request.timeoutInterval = SpotifyLibrary.timeout
        return request
    }

    /// Percent-encoding for a form body: everything but RFC 3986's unreserved characters
    static func formEncode(_ string: String) -> String {
        // Spelled out: CharacterSet.alphanumerics includes letters outside ASCII
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    static func base64URL(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 32 random bytes, base64url-encoded, for the PKCE verifier and the sign-in's state
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "No random bytes for the Spotify sign-in")
        return base64URL(Data(bytes))
    }

}

/// What Spotify's token endpoint hands back, and what is kept between launches
struct SpotifyToken: Codable, Equatable {

    var accessToken: String
    /// Spotify may or may not send a new one on refresh; when it doesn't, the old one stands
    var refreshToken: String
    var expiresAt: Date

    /// An access token this close to expiring is refreshed before use rather than after a 401
    static let expiryMargin: TimeInterval = 60

    func isExpired(at now: Date) -> Bool {
        return now.addingTimeInterval(SpotifyToken.expiryMargin) >= expiresAt
    }

    /// Parse a token endpoint answer. A refresh may leave out the refresh token, so the one
    /// it replaces is passed in.
    static func parse(_ data: Data, now: Date, previousRefreshToken: String? = nil) -> SpotifyToken? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty,
              let refresh = (object["refresh_token"] as? String) ?? previousRefreshToken,
              let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue else { return nil }
        return SpotifyToken(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(expiresIn))
    }

    /// The `error` of a token endpoint failure: "invalid_grant" means the refresh token is
    /// dead (revoked, or the app's ID changed), and only signing in again helps
    static func errorCode(_ data: Data?) -> String? {
        guard let data = data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["error"] as? String
    }

}

/// Where the tokens are kept between launches. A file in the app's container; a dictionary in
/// tests.
protocol SpotifyTokenStore: AnyObject {
    func load(clientID: String) -> SpotifyToken?
    func save(_ token: SpotifyToken, clientID: String)
    func delete(clientID: String)
}

/// The tokens as a small JSON file in Application Support, which the sandbox puts inside
/// StarBar's own container, readable by the user alone.
///
/// Not the Keychain, though that was the first home: measured 2026-10-23, every update of an
/// ad hoc signed build showed a Keychain prompt, because the Keychain ties an item to the
/// exact code that made it and each ad hoc build is new code. A prompt after every update
/// teaches people to click Allow unread. Other sandboxed apps can't reach the container; an
/// unsandboxed process running as the user could, and the most it could do with the tokens
/// is like and unlike songs. Revisit this if releases get a Developer ID signature, which the
/// Keychain recognises across updates.
final class FileSpotifyTokenStore: SpotifyTokenStore {

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spotify", isDirectory: true)
    }

    /// One file per client ID, so a sign-in made with another ID is never picked up. The ID
    /// is reduced to letters and digits before it becomes a file name.
    func url(clientID: String) -> URL {
        let safe = String(clientID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
        return directory.appendingPathComponent("sign-in-\(safe).json")
    }

    func load(clientID: String) -> SpotifyToken? {
        guard let data = try? Data(contentsOf: url(clientID: clientID)) else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    func save(_ token: SpotifyToken, clientID: String) {
        do {
            let data = try JSONEncoder().encode(token)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = url(clientID: clientID)
            try data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't keep the Spotify sign-in: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
        }
    }

    func delete(clientID: String) {
        try? FileManager.default.removeItem(at: url(clientID: clientID))
    }

}
