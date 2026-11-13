//
//  LastfmAPI.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation
import CryptoKit

/// Last.fm's web service, as far as StarBar uses it: the requests and how to read the answers.
/// Pure, like `SpotifyAuth`: nothing here touches the network, the clock or the disk.
///
/// Every call is a form-encoded POST to one address, named by its `method` parameter, and
/// signed: `api_sig` is the MD5 of every parameter's name and value run together in order of
/// name, with the app's shared secret on the end. It is not OAuth. A sign-in is a token
/// (`auth.getToken`), which the user approves on last.fm (`authorizationURL`), and which
/// `auth.getSession` then turns into a session key that never expires.
///
/// Read `docs/lastfm.md` before changing anything here.
enum LastfmAPI {

    static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    /// The page where the user lets StarBar scrobble for them
    static let authorizePage = URL(string: "https://www.last.fm/api/auth/")!
    static let timeout: TimeInterval = 10
    /// The most scrobbles Last.fm takes in one `track.scrobble`
    static let maxBatch = 50

    /// The app's own key and secret, from Last.fm's API account page. The key is public and
    /// goes in every request; the secret only ever signs (`LastfmCredentials`).
    struct Credentials: Equatable {
        let apiKey: String
        let sharedSecret: String
    }

    /// Why a call failed, sorted by what the caller should do about it
    enum Failure: Error, Equatable {
        /// No answer at all. Try again later.
        case network
        /// Last.fm is down or busy: its error 11 (service offline), 16 (temporarily
        /// unavailable) or 29 (rate limit), or an HTTP 5xx with no error of Last.fm's own.
        /// Carries Last.fm's code, or the HTTP status when it gave none. Try again later.
        case temporary(Int)
        /// Error 9: the session key is no good. The user has to connect again; what is
        /// waiting to be sent is kept for them.
        case sessionInvalid
        /// Error 10, 13 or 26: Last.fm won't take this API key or signature. Nothing the
        /// user can do; what is waiting is kept.
        case credentialsRejected(Int)
        /// Error 14, from `auth.getSession` only: the user hasn't approved the token yet
        case tokenNotAuthorized
        /// Anything else, with Last.fm's code or the HTTP status: this request will never be
        /// taken, so it is not sent again
        case refused(Int)
    }

    /// What Last.fm said about a batch of scrobbles
    struct ScrobbleSummary: Equatable {
        var accepted: Int
        var ignored: Int
        /// The `ignoredMessage` code of each scrobble it ignored (1 artist, 2 track,
        /// 3 timestamp too old, 4 timestamp too new, 5 daily limit), for the log
        var ignoredCodes: [Int]
    }

    // MARK: - Signing

    /// `api_sig` for `parameters`: the MD5, in lowercase hex, of each name and value run
    /// together with no separators, in order of name, then `secret`. All UTF-8.
    ///
    /// `format` and `callback` are never part of it. Names are ordered by their UTF-8 bytes,
    /// not alphabetically: "artist[10]" comes before "artist[1]", because "0" sorts before
    /// "]", and a signature made in any other order is refused with error 13.
    static func signature(of parameters: [String: String], secret: String) -> String {
        let names = parameters.keys
            .filter { $0 != "format" && $0 != "callback" }
            .sorted(by: precedesInUTF8)
        var text = ""
        for name in names {
            text += name
            text += parameters[name] ?? ""
        }
        text += secret
        return Insecure.MD5.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Last.fm's order of names: byte by byte in UTF-8, as its own servers compare them
    private static func precedesInUTF8(_ first: String, _ second: String) -> Bool {
        return Array(first.utf8).lexicographicallyPrecedes(Array(second.utf8))
    }

    /// What StarBar calls itself in every request, as Last.fm asks API clients to
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "StarBar/\(version)"
    }()

    /// A signed POST of `method`: `parameters` plus `method`, `api_key`, `sk` when there is a
    /// session, `api_sig` over all of those, and `format=json`, form-encoded as UTF-8 in the
    /// body (`application/x-www-form-urlencoded; charset=utf-8`), with `timeout`.
    ///
    /// Percent-encoding leaves only letters, digits, "-", ".", "_" and "~" alone: a "+" or
    /// "&" in a song's name must not reach Last.fm as a space or a separator.
    static func request(method: String, parameters: [String: String] = [:], credentials: Credentials, sessionKey: String? = nil) -> URLRequest {
        var fields = parameters
        fields["method"] = method
        fields["api_key"] = credentials.apiKey
        if let sessionKey = sessionKey {
            fields["sk"] = sessionKey
        }
        // Over the raw values, before any percent-encoding
        fields["api_sig"] = signature(of: fields, secret: credentials.sharedSecret)
        fields["format"] = "json"

        // Sorted only so that a body reads the same every time
        let body = fields
            .sorted { precedesInUTF8($0.key, $1.key) }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = timeout
        return request
    }

    /// Percent-encoding for the form body: everything but ASCII letters, digits and "-._~".
    /// Spelled out, because `CharacterSet.alphanumerics` takes in letters outside ASCII and
    /// `.urlQueryAllowed` leaves "+" and "&" alone.
    static func formEncode(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: formUnreserved) ?? string
    }

    private static let formUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// The parameters a request's body carries, decoded again. For tests.
    static func formParameters(of request: URLRequest) -> [String: String] {
        guard let body = request.httpBody, let text = String(data: body, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0])
            let value = parts.count > 1 ? String(parts[1]) : ""
            fields[name.removingPercentEncoding ?? name] = value.removingPercentEncoding ?? value
        }
        return fields
    }

    // MARK: - Signing in

    /// `auth.getToken`: a token for the user to approve. Lasts 60 minutes, used once.
    static func tokenRequest(credentials: Credentials) -> URLRequest {
        return request(method: "auth.getToken", credentials: credentials)
    }

    /// Where the user approves `token`: `authorizePage` with `api_key` and `token`
    static func authorizationURL(apiKey: String, token: String) -> URL {
        guard var components = URLComponents(url: authorizePage, resolvingAgainstBaseURL: false) else { return authorizePage }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token),
        ]
        return components.url ?? authorizePage
    }

    /// `auth.getSession`: the session for an approved `token`. Answers `tokenNotAuthorized`
    /// until the user has approved it, which leaves the token good for another ask.
    static func sessionRequest(token: String, credentials: Credentials) -> URLRequest {
        return request(method: "auth.getSession", parameters: ["token": token], credentials: credentials)
    }

    /// The token in the answer to `tokenRequest`: `{"token": "..."}`
    static func parseToken(_ data: Data) -> String? {
        guard let token = jsonObject(data)?["token"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// The session in the answer to `sessionRequest`:
    /// `{"session": {"name": "...", "key": "...", "subscriber": 0}}`
    static func parseSession(_ data: Data) -> LastfmSession? {
        guard let session = jsonObject(data)?["session"] as? [String: Any],
              let name = session["name"] as? String, !name.isEmpty,
              let key = session["key"] as? String, !key.isEmpty else { return nil }
        return LastfmSession(name: name, key: key)
    }

    // MARK: - Scrobbling

    /// `track.updateNowPlaying` for `track`: `artist`, `track`, and `album`, `albumArtist`,
    /// `trackNumber` and `duration` (whole seconds) when it has them
    static func nowPlayingRequest(_ track: Scrobble.Track, credentials: Credentials, sessionKey: String) -> URLRequest {
        return request(method: "track.updateNowPlaying", parameters: trackParameters(track), credentials: credentials, sessionKey: sessionKey)
    }

    /// `track.scrobble` for up to `maxBatch` scrobbles, the first `maxBatch` of more: each
    /// one's `artist[i]`, `track[i]`, `timestamp[i]` and what else it has (`album[i]`,
    /// `albumArtist[i]`, `trackNumber[i]`, `duration[i]`), numbered from 0. `chosenByUser` is
    /// left out, which Last.fm reads as the user's own choice.
    static func scrobbleRequest(_ scrobbles: [Scrobble], credentials: Credentials, sessionKey: String) -> URLRequest {
        var parameters: [String: String] = [:]
        for (index, scrobble) in scrobbles.prefix(maxBatch).enumerated() {
            parameters.merge(trackParameters(scrobble.track, index: index)) { _, new in new }
            parameters["timestamp[\(index)]"] = String(scrobble.timestamp)
        }
        return request(method: "track.scrobble", parameters: parameters, credentials: credentials, sessionKey: sessionKey)
    }

    /// What Last.fm is told about `track`, under plain names for "now playing" or with
    /// `[index]` on the end for a scrobble. Optional fields go only when they say something:
    /// an empty album, a track number of 0 (which Music gives for none) or a length that
    /// rounds to no seconds is left out rather than sent.
    private static func trackParameters(_ track: Scrobble.Track, index: Int? = nil) -> [String: String] {
        func name(_ base: String) -> String {
            guard let index = index else { return base }
            return "\(base)[\(index)]"
        }
        func said(_ value: String?) -> String? {
            guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        var parameters = [name("artist"): track.artist, name("track"): track.title]
        if let album = said(track.album) {
            parameters[name("album")] = album
        }
        if let albumArtist = said(track.albumArtist) {
            parameters[name("albumArtist")] = albumArtist
        }
        if let number = track.trackNumber, number > 0 {
            parameters[name("trackNumber")] = String(number)
        }
        // Int() of an infinite or NaN length would trap
        if let duration = track.duration, duration.isFinite, duration.rounded() >= 1 {
            parameters[name("duration")] = String(Int(duration.rounded()))
        }
        return parameters
    }

    /// `track.love`, or `track.unlove` when `loved` is false
    static func loveRequest(title: String, artist: String, loved: Bool, credentials: Credentials, sessionKey: String) -> URLRequest {
        return request(method: loved ? "track.love" : "track.unlove", parameters: ["track": title, "artist": artist], credentials: credentials, sessionKey: sessionKey)
    }

    /// The summary in the answer to `scrobbleRequest`:
    /// `{"scrobbles": {"@attr": {"accepted": 1, "ignored": 0}, "scrobble": {...}}}`, where
    /// `scrobble` is one object for one scrobble and an array for several, each with an
    /// `ignoredMessage` of `{"code": "0", "#text": ""}`. Last.fm sends numbers as numbers in
    /// some answers and as strings in others, so both are read.
    static func parseScrobbles(_ data: Data) -> ScrobbleSummary? {
        guard let scrobbles = jsonObject(data)?["scrobbles"] as? [String: Any] else { return nil }
        let counts = scrobbles["@attr"] as? [String: Any]
        let entries: [[String: Any]]
        if let many = scrobbles["scrobble"] as? [[String: Any]] {
            entries = many
        } else if let one = scrobbles["scrobble"] as? [String: Any] {
            entries = [one]
        } else {
            entries = []
        }
        let ignoredCodes = entries
            .compactMap { ($0["ignoredMessage"] as? [String: Any]).flatMap { integer($0["code"]) } }
            .filter { $0 != 0 }
        return ScrobbleSummary(accepted: integer(counts?["accepted"]) ?? 0,
                               ignored: integer(counts?["ignored"]) ?? 0,
                               ignoredCodes: ignoredCodes)
    }

    // MARK: - Reading answers

    /// Why a call failed, or nil when it worked: an HTTP 2xx whose body is a JSON object
    /// with no `error` in it (`track.love` answers `{}`).
    ///
    /// Last.fm reports its own errors as `{"error": 9, "message": "..."}`, usually under an
    /// HTTP 4xx, so the body is read whatever the status, and its code decides. With no code:
    /// no response is `.network`, a 5xx is `.temporary(status)`, any other status is
    /// `.refused(status)`, and a 2xx that isn't a JSON object is `.temporary(status)`.
    static func failure(data: Data?, response: HTTPURLResponse?) -> Failure? {
        let object = data.flatMap(jsonObject)
        if let code = integer(object?["error"]) {
            return failure(code: code)
        }
        guard let response = response else { return .network }
        let status = response.statusCode
        switch status {
        case 200..<300:
            // An `error` Last.fm sent but that can't be read as a code is no success either
            if let object = object, object["error"] == nil {
                return nil
            }
            return .temporary(status)
        case 500..<600:
            return .temporary(status)
        default:
            return .refused(status)
        }
    }

    /// Which `Failure` one of Last.fm's error codes is
    static func failure(code: Int) -> Failure {
        switch code {
        case 9:
            return .sessionInvalid
        case 11, 16, 29:
            return .temporary(code)
        case 10, 13, 26:
            return .credentialsRejected(code)
        case 14:
            return .tokenNotAuthorized
        default:
            return .refused(code)
        }
    }

    /// The body as a JSON object, or nil when it is empty, not JSON, or JSON of another shape
    private static func jsonObject(_ data: Data) -> [String: Any]? {
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// A number Last.fm sent as a number or as a string of digits
    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

}
