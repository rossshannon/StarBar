//
//  LastfmAPITests.swift
//  StarBarTests
//
//  Last.fm's requests, their signatures and the reading of its answers. Pure: no network.
//  The signature vectors were worked out independently, with Python's hashlib, not with the
//  code under test.
//

import XCTest
@testable import StarBar

final class LastfmAPITests: XCTestCase {

    private let credentials = LastfmAPI.Credentials(apiKey: "abc123", sharedSecret: "s3cret")

    // MARK: - Signing

    func testTheSignatureOfASessionRequestMatchesAnIndependentMD5() {
        let parameters = ["method": "auth.getSession", "api_key": "abc123", "token": "tok456"]
        XCTAssertEqual(LastfmAPI.signature(of: parameters, secret: "s3cret"), "587126e04c34e93bfc8a19d75a3ed088",
                       "names and values run together in order of name, then the secret, as lowercase MD5 hex")
    }

    /// Catches a signature over anything but UTF-8, and one that takes in `format` or
    /// `callback`: with them it would be 2c98829fcc537152d09f7e23bbdf5f63
    func testTheSignatureIsOverUTF8AndLeavesOutFormatAndCallback() {
        let parameters = [
            "method": "track.love", "api_key": "abc123", "sk": "sess",
            "track": "Für Elise", "artist": "Beyoncé & JAY-Z",
            "format": "json", "callback": "x",
        ]
        let signature = LastfmAPI.signature(of: parameters, secret: "s3cret")
        XCTAssertEqual(signature, "8f3feaa72a76b10ff36f3df65a672075", "non-ASCII names are signed as UTF-8, without format and callback")
        XCTAssertNotEqual(signature, "2c98829fcc537152d09f7e23bbdf5f63", "format and callback must not be signed")
    }

    /// Catches a numeric-aware sort, which puts artist[1] before artist[10] and is refused
    /// by Last.fm with error 13
    func testTheSignatureOrdersNamesByTheirBytes() {
        var parameters = ["method": "track.scrobble", "api_key": "k", "sk": "s"]
        for index in 0...10 {
            parameters["artist[\(index)]"] = "A\(index)"
            parameters["track[\(index)]"] = "T\(index)"
            parameters["timestamp[\(index)]"] = "\(1000 + index)"
        }
        let signature = LastfmAPI.signature(of: parameters, secret: "x")
        XCTAssertEqual(signature, "d75fdf553c3faa6a44bee5a67437a960", "\"artist[10]\" sorts before \"artist[1]\" by bytes")
        XCTAssertNotEqual(signature, "5e688aa3db0fd078c99083c5a2d254e9", "that is the numeric-aware order, which Last.fm refuses")
    }

    func testTheSignatureOfNothingIsTheMD5OfTheEmptyString() {
        XCTAssertEqual(LastfmAPI.signature(of: [:], secret: ""), "d41d8cd98f00b204e9800998ecf8427e")
    }

    // MARK: - The request

    func testARequestIsASignedFormPostWithJSONAsked() {
        let request = LastfmAPI.request(method: "auth.getToken", credentials: credentials)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, LastfmAPI.endpoint)
        XCTAssertEqual(request.url?.absoluteString, "https://ws.audioscrobbler.com/2.0/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        XCTAssertEqual(request.timeoutInterval, LastfmAPI.timeout)
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("StarBar/") ?? false, "Last.fm asks clients to say who they are")

        let fields = LastfmAPI.formParameters(of: request)
        XCTAssertEqual(fields["method"], "auth.getToken")
        XCTAssertEqual(fields["api_key"], "abc123")
        XCTAssertEqual(fields["format"], "json", "without it Last.fm answers in XML")
        XCTAssertNil(fields["sk"], "no session, no sk")
        XCTAssertFalse(fields.values.contains("s3cret"), "the secret only signs; it is never sent")
    }

    func testTheSignatureCoversEveryOtherFieldButFormat() throws {
        let request = LastfmAPI.request(method: "track.love", parameters: ["track": "Song", "artist": "Artist"], credentials: credentials, sessionKey: "sess")
        var fields = LastfmAPI.formParameters(of: request)
        let sent = try XCTUnwrap(fields.removeValue(forKey: "api_sig"))
        XCTAssertEqual(fields["sk"], "sess", "a session's key goes with the call")
        XCTAssertEqual(sent, LastfmAPI.signature(of: fields, secret: "s3cret"), "api_sig is over the body's other fields")

        // And independently: over method, api_key, sk, track and artist, not format
        let expected = LastfmAPI.signature(of: ["method": "track.love", "api_key": "abc123", "sk": "sess", "track": "Song", "artist": "Artist"], secret: "s3cret")
        XCTAssertEqual(sent, expected)
    }

    /// Catches `.urlQueryAllowed` (which sends "+" and "&" as they are) and a signature over
    /// the percent-encoded values
    func testAwkwardCharactersRoundTripAndAreSignedRaw() throws {
        let title = "Rock & Roll + Blues = Life? Für Élise/ünïcødé"
        let request = LastfmAPI.request(method: "track.love", parameters: ["track": title, "artist": "AC/DC"], credentials: credentials, sessionKey: "sess")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("+"), "a plus would arrive as a space")
        XCTAssertFalse(body.contains(" "))
        XCTAssertTrue(body.contains("track=Rock%20%26%20Roll%20%2B%20Blues%20%3D%20Life%3F%20F%C3%BCr"), "body was \(body)")
        XCTAssertEqual(body.components(separatedBy: "&").count, 7, "only the separators between fields are bare ampersands")

        var fields = LastfmAPI.formParameters(of: request)
        XCTAssertEqual(fields["track"], title)
        XCTAssertEqual(fields["artist"], "AC/DC")
        let sent = fields.removeValue(forKey: "api_sig")
        XCTAssertEqual(sent, LastfmAPI.signature(of: fields, secret: "s3cret"), "signed over the raw values")
    }

    func testTheBodyIsTheSameEveryTime() {
        let first = LastfmAPI.request(method: "track.love", parameters: ["track": "a", "artist": "b"], credentials: credentials, sessionKey: "s")
        let second = LastfmAPI.request(method: "track.love", parameters: ["track": "a", "artist": "b"], credentials: credentials, sessionKey: "s")
        XCTAssertEqual(first.httpBody, second.httpBody, "fields are written in a stable order")
    }

    // MARK: - Signing in

    func testTheTokenRequestAsksForAToken() {
        let fields = LastfmAPI.formParameters(of: LastfmAPI.tokenRequest(credentials: credentials))
        XCTAssertEqual(fields["method"], "auth.getToken")
        XCTAssertNotNil(fields["api_sig"])
    }

    func testTheSessionRequestSendsTheToken() {
        let fields = LastfmAPI.formParameters(of: LastfmAPI.sessionRequest(token: "tok456", credentials: credentials))
        XCTAssertEqual(fields["method"], "auth.getSession")
        XCTAssertEqual(fields["token"], "tok456")
        XCTAssertEqual(fields["api_sig"], "587126e04c34e93bfc8a19d75a3ed088", "the worked vector, through the real request")
    }

    func testTheApprovalPageCarriesTheKeyAndToken() throws {
        let url = LastfmAPI.authorizationURL(apiKey: "abc123", token: "tok 456&x")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.host, "www.last.fm")
        XCTAssertEqual(components.path, "/api/auth/")
        XCTAssertEqual(query["api_key"], "abc123")
        XCTAssertEqual(query["token"], "tok 456&x")
        XCTAssertEqual(query.count, 2)
    }

    func testATokenAnswerParses() {
        XCTAssertEqual(LastfmAPI.parseToken(Data(#"{"token":"cf45fe5a3e3cebe168480a086d7fe481"}"#.utf8)), "cf45fe5a3e3cebe168480a086d7fe481")
        XCTAssertNil(LastfmAPI.parseToken(Data(#"{"error":8,"message":"Operation failed"}"#.utf8)))
        XCTAssertNil(LastfmAPI.parseToken(Data(#"{"token":""}"#.utf8)))
        XCTAssertNil(LastfmAPI.parseToken(Data("<html>".utf8)))
    }

    func testASessionAnswerParses() {
        let data = Data(#"{"session":{"name":"listener","key":"d580d57f32848f5dcf574d1ce18d78b2","subscriber":0}}"#.utf8)
        XCTAssertEqual(LastfmAPI.parseSession(data), LastfmSession(name: "listener", key: "d580d57f32848f5dcf574d1ce18d78b2"))
        XCTAssertNil(LastfmAPI.parseSession(Data(#"{"error":14,"message":"Unauthorized Token"}"#.utf8)))
        XCTAssertNil(LastfmAPI.parseSession(Data(#"{"session":{"name":"listener"}}"#.utf8)), "no key, no session")
    }

    // MARK: - Scrobbling

    func testNowPlayingLeavesOutWhatTheSongDoesNotHaveAndRoundsTheLength() {
        let bare = Scrobble.Track(title: "Song", artist: "Artist", album: "", albumArtist: nil, trackNumber: nil, duration: nil)
        let fields = LastfmAPI.formParameters(of: LastfmAPI.nowPlayingRequest(bare, credentials: credentials, sessionKey: "sess"))
        XCTAssertEqual(fields["method"], "track.updateNowPlaying")
        XCTAssertEqual(fields["track"], "Song")
        XCTAssertEqual(fields["artist"], "Artist")
        XCTAssertEqual(fields["sk"], "sess")
        for missing in ["album", "albumArtist", "trackNumber", "duration"] {
            XCTAssertNil(fields[missing], "\(missing) is sent only when the song has one")
        }

        let full = Scrobble.Track(title: "Song", artist: "Artist", album: "Album", albumArtist: "Various", trackNumber: 3, duration: 241.6)
        let fullFields = LastfmAPI.formParameters(of: LastfmAPI.nowPlayingRequest(full, credentials: credentials, sessionKey: "sess"))
        XCTAssertEqual(fullFields["album"], "Album")
        XCTAssertEqual(fullFields["albumArtist"], "Various")
        XCTAssertEqual(fullFields["trackNumber"], "3")
        XCTAssertEqual(fullFields["duration"], "242", "whole seconds, rounded")
    }

    func testANonPositiveLengthIsLeftOut() {
        for duration in [0, -5, 0.2, Double.infinity, Double.nan] {
            let track = Scrobble.Track(title: "Song", artist: "Artist", duration: duration)
            let fields = LastfmAPI.formParameters(of: LastfmAPI.nowPlayingRequest(track, credentials: credentials, sessionKey: "sess"))
            XCTAssertNil(fields["duration"], "a length of \(duration) says nothing")
        }
    }

    func testABatchOfThreeIsNumberedFromZeroWithItsStartTimes() {
        let scrobbles = (0..<3).map { index in
            Scrobble(track: .test("Song \(index)", artist: "Artist \(index)", album: index == 1 ? nil : "Album"),
                     startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 300 + 0.7),
                     source: "music")
        }
        let fields = LastfmAPI.formParameters(of: LastfmAPI.scrobbleRequest(scrobbles, credentials: credentials, sessionKey: "sess"))
        XCTAssertEqual(fields["method"], "track.scrobble")
        for index in 0..<3 {
            XCTAssertEqual(fields["track[\(index)]"], "Song \(index)")
            XCTAssertEqual(fields["artist[\(index)]"], "Artist \(index)")
            XCTAssertEqual(fields["timestamp[\(index)]"], String(1_700_000_000 + index * 300), "the start, in whole seconds")
            XCTAssertEqual(fields["duration[\(index)]"], "240")
        }
        XCTAssertEqual(fields["album[0]"], "Album")
        XCTAssertNil(fields["album[1]"], "a song with no album sends none")
        XCTAssertNil(fields["track[3]"])
        XCTAssertNil(fields["track"], "a scrobble's fields are always indexed")
        XCTAssertNil(fields["source[0]"], "where it was heard is not Last.fm's business")
    }

    func testABatchIsCutToFifty() {
        let scrobbles = (0..<60).map { Scrobble(track: .test("Song \($0)"), startedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 300), source: "music") }
        let fields = LastfmAPI.formParameters(of: LastfmAPI.scrobbleRequest(scrobbles, credentials: credentials, sessionKey: "sess"))
        XCTAssertEqual(fields["track[49]"], "Song 49")
        XCTAssertNil(fields["track[50]"], "Last.fm takes at most \(LastfmAPI.maxBatch) at once")
        XCTAssertEqual(fields.keys.filter { $0.hasPrefix("track[") }.count, 50)
    }

    func testLoveAndUnlovePickTheirMethods() {
        let love = LastfmAPI.formParameters(of: LastfmAPI.loveRequest(title: "Song", artist: "Artist", loved: true, credentials: credentials, sessionKey: "sess"))
        XCTAssertEqual(love["method"], "track.love")
        XCTAssertEqual(love["track"], "Song")
        XCTAssertEqual(love["artist"], "Artist")
        XCTAssertEqual(love["sk"], "sess")

        let unlove = LastfmAPI.formParameters(of: LastfmAPI.loveRequest(title: "Song", artist: "Artist", loved: false, credentials: credentials, sessionKey: "sess"))
        XCTAssertEqual(unlove["method"], "track.unlove", "clearing the heart must not love the song")
    }

    // MARK: - Reading scrobble answers

    func testOneScrobbleAnswerParses() {
        let data = Data(#"""
        {"scrobbles":{"@attr":{"accepted":1,"ignored":0},"scrobble":{"artist":{"corrected":"0","#text":"Artist"},"ignoredMessage":{"code":"0","#text":""},"timestamp":"1287140447"}}}
        """#.utf8)
        XCTAssertEqual(LastfmAPI.parseScrobbles(data), LastfmAPI.ScrobbleSummary(accepted: 1, ignored: 0, ignoredCodes: []))
    }

    func testSeveralScrobblesAnswerAsAnArrayWithTheirIgnoredCodes() {
        let data = Data(#"""
        {"scrobbles":{"@attr":{"accepted":1,"ignored":2},"scrobble":[
          {"ignoredMessage":{"code":"0","#text":""}},
          {"ignoredMessage":{"code":"3","#text":"Timestamp too old"}},
          {"ignoredMessage":{"code":5,"#text":"Daily scrobble limit exceeded"}}]}}
        """#.utf8)
        XCTAssertEqual(LastfmAPI.parseScrobbles(data), LastfmAPI.ScrobbleSummary(accepted: 1, ignored: 2, ignoredCodes: [3, 5]),
                       "codes are read as strings and as numbers, and zero means not ignored")
    }

    func testCountsSentAsStringsAreRead() {
        let data = Data(#"{"scrobbles":{"@attr":{"accepted":"2","ignored":"1"},"scrobble":[{"ignoredMessage":{"code":"1"}},{},{}]}}"#.utf8)
        XCTAssertEqual(LastfmAPI.parseScrobbles(data), LastfmAPI.ScrobbleSummary(accepted: 2, ignored: 1, ignoredCodes: [1]))
    }

    func testAnAnswerWithNoScrobblesIsNotASummary() {
        XCTAssertNil(LastfmAPI.parseScrobbles(Data("{}".utf8)))
        XCTAssertNil(LastfmAPI.parseScrobbles(Data("not json".utf8)))
    }

    // MARK: - Failures

    private func response(_ status: Int) -> HTTPURLResponse {
        return HTTPURLResponse(url: LastfmAPI.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    func testAnEmptyObjectUnder200Worked() {
        XCTAssertNil(LastfmAPI.failure(data: Data("{}".utf8), response: response(200)), "track.love answers {}")
    }

    func testAScrobblesAnswerUnder200Worked() {
        let data = Data(#"{"scrobbles":{"@attr":{"accepted":1,"ignored":0}}}"#.utf8)
        XCTAssertNil(LastfmAPI.failure(data: data, response: response(200)))
    }

    func testError9Under403IsAnInvalidSession() {
        let data = Data(#"{"error":9,"message":"Invalid session key - Please re-authenticate"}"#.utf8)
        XCTAssertEqual(LastfmAPI.failure(data: data, response: response(403)), .sessionInvalid)
    }

    func testError14Under400IsATokenNotYetApproved() {
        let data = Data(#"{"error":14,"message":"Unauthorized Token - This token has not been issued"}"#.utf8)
        XCTAssertEqual(LastfmAPI.failure(data: data, response: response(400)), .tokenNotAuthorized)
    }

    /// Catches reading only the status: Last.fm can put an error under a 200
    func testAnErrorUnder200StillCounts() {
        XCTAssertEqual(LastfmAPI.failure(data: Data(#"{"error":29,"message":"Rate limit exceeded"}"#.utf8), response: response(200)), .temporary(29))
        XCTAssertEqual(LastfmAPI.failure(data: Data(#"{"error":"9","message":"Invalid session key"}"#.utf8), response: response(200)), .sessionInvalid,
                       "the code may come as a string")
    }

    func testA503WithNoJSONIsTemporary() {
        XCTAssertEqual(LastfmAPI.failure(data: Data("<html>Service Unavailable</html>".utf8), response: response(503)), .temporary(503))
    }

    func testA404WithNoJSONIsRefused() {
        XCTAssertEqual(LastfmAPI.failure(data: Data("Not Found".utf8), response: response(404)), .refused(404))
    }

    func testNoAnswerIsTheNetwork() {
        XCTAssertEqual(LastfmAPI.failure(data: nil, response: nil), .network)
    }

    /// Catches taking any 200 as success: a proxy's login page is not Last.fm's answer
    func testA200ThatIsNotJSONIsTemporary() {
        XCTAssertEqual(LastfmAPI.failure(data: Data("<html>captive portal</html>".utf8), response: response(200)), .temporary(200))
        XCTAssertEqual(LastfmAPI.failure(data: nil, response: response(200)), .temporary(200))
    }

    func testEachErrorCodeIsSortedByWhatToDo() {
        XCTAssertEqual(LastfmAPI.failure(code: 9), .sessionInvalid)
        XCTAssertEqual(LastfmAPI.failure(code: 11), .temporary(11))
        XCTAssertEqual(LastfmAPI.failure(code: 16), .temporary(16))
        XCTAssertEqual(LastfmAPI.failure(code: 29), .temporary(29))
        XCTAssertEqual(LastfmAPI.failure(code: 10), .credentialsRejected(10))
        XCTAssertEqual(LastfmAPI.failure(code: 13), .credentialsRejected(13))
        XCTAssertEqual(LastfmAPI.failure(code: 26), .credentialsRejected(26))
        XCTAssertEqual(LastfmAPI.failure(code: 14), .tokenNotAuthorized)
        for code in [4, 6, 8, 15] {
            XCTAssertEqual(LastfmAPI.failure(code: code), .refused(code), "error \(code) will never be taken")
        }
    }

}
