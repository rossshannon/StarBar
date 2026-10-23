//
//  SpotifyAuthTests.swift
//  StarBarTests
//
//  The PKCE pair, the sign-in URL, the redirect's checks and the token requests and answers.
//  No network; the token file goes to a temporary folder.
//

import XCTest
@testable import StarBar

final class SpotifyAuthTests: XCTestCase {

    /// The worked example in RFC 7636, appendix B
    func testTheChallengeIsTheRFCsS256OfTheVerifier() {
        let pkce = SpotifyAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testARandomVerifierIsLongEnoughAndURLSafe() {
        let first = SpotifyAuth.PKCE.random()
        let second = SpotifyAuth.PKCE.random()
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertEqual(first.verifier.count, 43)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(first.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testTheSignInURLAsksForTheLibraryScopesOnlyWithPKCE() throws {
        let pkce = SpotifyAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = SpotifyAuth.authorizationURL(clientID: "abc123", pkce: pkce, state: "xyz")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.host, "accounts.spotify.com")
        XCTAssertEqual(components.path, "/authorize")
        XCTAssertEqual(query["client_id"], "abc123")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["redirect_uri"], "starbar://spotify-callback")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(query["scope"], "user-library-read user-library-modify")
        XCTAssertEqual(query["state"], "xyz")
        XCTAssertNil(query["client_secret"])
    }

    func testTheRedirectGivesTheCodeOnlyForThisSignIn() {
        let ok = URL(string: "starbar://spotify-callback?code=AQB123&state=xyz")!
        XCTAssertEqual(SpotifyAuth.code(fromCallback: ok, expectedState: "xyz"), .success("AQB123"))
        XCTAssertEqual(SpotifyAuth.code(fromCallback: ok, expectedState: "other"), .failure(.stateMismatch))

        let denied = URL(string: "starbar://spotify-callback?error=access_denied&state=xyz")!
        XCTAssertEqual(SpotifyAuth.code(fromCallback: denied, expectedState: "xyz"), .failure(.denied("access_denied")))

        // An error with the wrong state is still someone else's redirect
        XCTAssertEqual(SpotifyAuth.code(fromCallback: denied, expectedState: "other"), .failure(.stateMismatch))

        let empty = URL(string: "starbar://spotify-callback?state=xyz")!
        XCTAssertEqual(SpotifyAuth.code(fromCallback: empty, expectedState: "xyz"), .failure(.noCode))
    }

    func testTheTokenRequestIsAFormPostWithTheVerifierAndNoSecret() throws {
        let request = SpotifyAuth.tokenRequest(code: "AQB/1+2", clientID: "abc123", verifier: "ver")
        XCTAssertEqual(request.url?.absoluteString, "https://accounts.spotify.com/api/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertEqual(body, "grant_type=authorization_code&code=AQB%2F1%2B2&redirect_uri=starbar%3A%2F%2Fspotify-callback&client_id=abc123&code_verifier=ver")
    }

    func testTheRefreshRequestSendsTheRefreshToken() throws {
        let request = SpotifyAuth.refreshRequest(refreshToken: "r=1", clientID: "abc123")
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertEqual(body, "grant_type=refresh_token&refresh_token=r%3D1&client_id=abc123")
    }

    func testATokenAnswerParses() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let data = Data(#"{"access_token":"A","token_type":"Bearer","scope":"user-library-read user-library-modify","expires_in":3600,"refresh_token":"R"}"#.utf8)
        let token = try XCTUnwrap(SpotifyToken.parse(data, now: now))
        XCTAssertEqual(token, SpotifyToken(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(3600)))
        XCTAssertFalse(token.isExpired(at: now))
        XCTAssertTrue(token.isExpired(at: now.addingTimeInterval(3600 - SpotifyToken.expiryMargin)))
    }

    /// Spotify may leave the refresh token out of a refresh's answer; the old one stands
    func testARefreshWithoutARefreshTokenKeepsTheOldOne() throws {
        let data = Data(#"{"access_token":"A2","expires_in":3600}"#.utf8)
        XCTAssertNil(SpotifyToken.parse(data, now: Date()))
        XCTAssertEqual(SpotifyToken.parse(data, now: Date(), previousRefreshToken: "R")?.refreshToken, "R")
    }

    func testATokenErrorIsRead() {
        XCTAssertEqual(SpotifyToken.errorCode(Data(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#.utf8)), "invalid_grant")
        XCTAssertNil(SpotifyToken.errorCode(Data("<html>".utf8)))
        XCTAssertNil(SpotifyToken.errorCode(nil))
    }

    func testTheTokenFileRoundTripsPerClientIDAndOnlyTheUserCanReadIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileSpotifyTokenStore(directory: folder)
        let token = SpotifyToken(accessToken: "A", refreshToken: "R", expiresAt: Date(timeIntervalSince1970: 2_000_000_000))

        XCTAssertNil(store.load(clientID: "abc123"))
        store.save(token, clientID: "abc123")
        XCTAssertEqual(store.load(clientID: "abc123"), token)
        XCTAssertNil(store.load(clientID: "other"), "a sign-in belongs to the app it was made with")

        let attributes = try FileManager.default.attributesOfItem(atPath: store.url(clientID: "abc123").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        store.delete(clientID: "abc123")
        XCTAssertNil(store.load(clientID: "abc123"))
    }

    func testAClientIDCannotEscapeTheFolder() {
        let store = FileSpotifyTokenStore(directory: URL(fileURLWithPath: "/tmp/spotify"))
        XCTAssertEqual(store.url(clientID: "../../etc/passwd").path, "/tmp/spotify/sign-in-etcpasswd.json")
    }

}
