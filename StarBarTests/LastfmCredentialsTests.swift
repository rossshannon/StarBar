//
//  LastfmCredentialsTests.swift
//  StarBarTests
//

import XCTest
@testable import StarBar

final class LastfmCredentialsTests: XCTestCase {

    /// Worked out separately (Python, XOR with the same pad), so a pad or byte order that
    /// drifted from `build.sh`'s would fail here rather than leave every build unable to sign
    private let vectorSecret = "0123456789abcdef0123456789abcdef"
    private let vectorConcealed = "634553417654441d745812164d020847634553417654441d745812164d020847"

    // MARK: - conceal and reveal

    func testConcealMatchesTheIndependentlyComputedVector() {
        XCTAssertEqual(LastfmCredentials.conceal(vectorSecret), vectorConcealed,
                       "conceal must XOR each byte with the pad, repeating, as lowercase hex: build.sh does the same")
    }

    func testRevealUndoesTheIndependentlyComputedVector() {
        XCTAssertEqual(LastfmCredentials.reveal(vectorConcealed), vectorSecret,
                       "reveal must undo what build.sh stored")
    }

    func testRevealAcceptsUpperCaseHex() {
        XCTAssertEqual(LastfmCredentials.reveal(vectorConcealed.uppercased()), vectorSecret,
                       "hex digits in upper case are the same bytes")
    }

    func testRoundTripsSecrets() {
        // The last is longer than the pad, so a pad index that didn't wrap would crash or differ
        let secrets = ["a", "f00dfeedcafebabe1234567890abcdef", "with spaces & symbols +=/", "naïve café ♫",
                       String(repeating: "0123456789abcdef", count: 5) + "xyz"]
        for secret in secrets {
            let concealed = LastfmCredentials.conceal(secret)
            XCTAssertEqual(concealed.count, secret.utf8.count * 2, "two hex digits a byte for \(secret)")
            XCTAssertEqual(LastfmCredentials.reveal(concealed), secret, "round trip of \(secret)")
        }
    }

    func testConcealedFormDoesNotContainTheSecret() {
        // Catches a conceal that returned its input, or hex of the plain bytes
        let concealed = LastfmCredentials.conceal(vectorSecret)
        XCTAssertFalse(concealed.contains(vectorSecret), "the concealed form must not hold the secret as it is")
        XCTAssertNotEqual(concealed, vectorSecret.utf8.map { String(format: "%02x", Int($0)) }.joined(),
                          "the concealed form must not be plain hex of the secret")
    }

    func testConcealOfEmptyIsEmpty() {
        XCTAssertEqual(LastfmCredentials.conceal(""), "", "nothing to conceal gives nothing")
    }

    func testRevealOfEmptyIsNil() {
        XCTAssertNil(LastfmCredentials.reveal(""), "a build without the secret stores an empty string")
        XCTAssertNil(LastfmCredentials.reveal("   \n"), "whitespace alone is no secret")
    }

    func testRevealOfOddLengthIsNil() {
        XCTAssertNil(LastfmCredentials.reveal(String(vectorConcealed.dropLast())), "half a byte is not a secret")
    }

    func testRevealOfNonHexIsNil() {
        XCTAssertNil(LastfmCredentials.reveal("6345zz41"), "z is not a hex digit")
        XCTAssertNil(LastfmCredentials.reveal("63 45"), "a space inside is not hex")
    }

    func testRevealTrimsWhitespace() {
        XCTAssertEqual(LastfmCredentials.reveal("  \(vectorConcealed)\n"), vectorSecret,
                       "whitespace round what the build stored must be ignored")
    }

    func testRevealOfAnUnexpandedBuildSettingIsNil() {
        XCTAssertNil(LastfmCredentials.reveal("$(STARBAR_LASTFM_SECRET)"),
                     "an Info.plist value that was never substituted is no secret")
    }

    func testRevealOfBytesThatAreNotUTF8IsNil() {
        // 0xFF on its own is never valid UTF-8; conceal it by hand with the pad's first byte
        let concealed = String(format: "%02x", Int(UInt8(0xFF) ^ LastfmCredentials.pad[0]))
        XCTAssertNil(LastfmCredentials.reveal(concealed), "bytes that aren't text are no secret")
    }

    // MARK: - credentials

    func testBuiltInKeyAndSecret() {
        let credentials = LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: vectorConcealed,
                                                        overrideKey: "", overrideSecret: "")
        XCTAssertEqual(credentials, LastfmAPI.Credentials(apiKey: "builtinkey", sharedSecret: vectorSecret),
                       "with no overrides, the built-in key and the revealed secret are used")
    }

    func testOverrideKeyAndSecretReplaceTheBuiltInOnes() {
        let credentials = LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: vectorConcealed,
                                                        overrideKey: "mykey", overrideSecret: "mysecret")
        XCTAssertEqual(credentials, LastfmAPI.Credentials(apiKey: "mykey", sharedSecret: "mysecret"),
                       "both hidden defaults set replace both built-in values")
    }

    func testOverrideSecretAloneServesABuildWithoutOne() {
        let credentials = LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: "",
                                                        overrideKey: "", overrideSecret: "mysecret")
        XCTAssertEqual(credentials, LastfmAPI.Credentials(apiKey: "builtinkey", sharedSecret: "mysecret"),
                       "a secret alone pairs with the built-in key")
    }

    func testOverrideKeyAloneKeepsTheBuiltInSecret() {
        // Documented as the caller's mistake; this pins that nothing special happens
        let credentials = LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: vectorConcealed,
                                                        overrideKey: "mykey", overrideSecret: "")
        XCTAssertEqual(credentials, LastfmAPI.Credentials(apiKey: "mykey", sharedSecret: vectorSecret),
                       "a key alone pairs with the built-in secret")
    }

    func testMissingKeyIsNil() {
        XCTAssertNil(LastfmCredentials.credentials(builtInKey: "", concealedSecret: vectorConcealed,
                                                   overrideKey: "", overrideSecret: ""),
                     "no built-in key and no override can't connect")
    }

    func testMissingSecretIsNil() {
        XCTAssertNil(LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: nil,
                                                   overrideKey: "", overrideSecret: ""),
                     "no Info.plist value and no override can't connect")
        XCTAssertNil(LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: "",
                                                   overrideKey: "", overrideSecret: ""),
                     "an empty Info.plist value, from a build without the secret, can't connect")
        XCTAssertNil(LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: "$(STARBAR_LASTFM_SECRET)",
                                                   overrideKey: "", overrideSecret: ""),
                     "an unexpanded build setting can't connect")
    }

    func testWhitespaceOnlyValuesCountAsEmpty() {
        XCTAssertNil(LastfmCredentials.credentials(builtInKey: "  ", concealedSecret: vectorConcealed,
                                                   overrideKey: " \t", overrideSecret: ""),
                     "a key of whitespace is no key")
        let credentials = LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: vectorConcealed,
                                                        overrideKey: "  ", overrideSecret: "\n")
        XCTAssertEqual(credentials, LastfmAPI.Credentials(apiKey: "builtinkey", sharedSecret: vectorSecret),
                       "overrides of whitespace must not replace the built-in values")
    }

    func testValuesAreTrimmed() {
        let credentials = LastfmCredentials.credentials(builtInKey: " builtinkey\n", concealedSecret: " \(vectorConcealed) ",
                                                        overrideKey: "", overrideSecret: "")
        XCTAssertEqual(credentials, LastfmAPI.Credentials(apiKey: "builtinkey", sharedSecret: vectorSecret),
                       "whitespace round a value would break every signature")
        let overridden = LastfmCredentials.credentials(builtInKey: "builtinkey", concealedSecret: vectorConcealed,
                                                       overrideKey: " mykey ", overrideSecret: " mysecret\n")
        XCTAssertEqual(overridden, LastfmAPI.Credentials(apiKey: "mykey", sharedSecret: "mysecret"),
                       "pasted overrides often carry a newline")
    }

}
