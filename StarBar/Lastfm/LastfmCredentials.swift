//
//  LastfmCredentials.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation

/// StarBar's own key and secret for Last.fm's API, so that nobody using StarBar has to
/// register an app of their own.
///
/// The API key is public: it goes in the address of the approval page and in every request,
/// and is committed here. The shared secret signs requests and is **not in the repository**.
/// `build.sh` reads it from the environment (`LASTFM_SHARED_SECRET`) or from a file on the
/// Mac that builds, and passes it to the build as the `STARBAR_LASTFM_SECRET` setting, which
/// `Info.plist` holds under `LastfmSharedSecret`. A build made without it can't connect, and
/// Preferences says so (`LastfmAccount.canConnect`).
///
/// The secret is in every copy of the app all the same, as it is in every desktop scrobbler:
/// anyone who takes it out of the binary can sign requests as StarBar, which lets them
/// scrobble to their own account under StarBar's name and nothing else, since acting for a
/// user also takes that user's session key. So it is only kept out of plain sight: what the
/// build stores is the secret's bytes XORed with `pad`, in hex (`conceal`), which keeps it
/// out of `strings` and out of a search of the bundle for the secret itself. The pad is in
/// this public repository, so the concealed form is as good as the secret to anyone who has
/// it: neither may ever reach a command line or a log, which is why `build.sh` hands it to
/// Xcode through a file. Nothing here logs either.
enum LastfmCredentials {

    /// StarBar's API key on Last.fm. Empty until the API account exists.
    static let builtInAPIKey = ""

    /// The `Info.plist` key holding the concealed secret
    static let secretInfoKey = "LastfmSharedSecret"

    /// What the secret's bytes are XORed with, repeating. `build.sh` has the same bytes.
    static let pad: [UInt8] = [0x53, 0x74, 0x61, 0x72, 0x42, 0x61, 0x72, 0x2A, 0x4C, 0x61, 0x73, 0x74, 0x2E, 0x66, 0x6D, 0x21]

    /// The key and secret to use, or nil when either is missing.
    ///
    /// The hidden defaults `lastfmAPIKey` and `lastfmSharedSecret` (plain text) replace the
    /// built-in ones, for someone with a Last.fm API account of their own and for testing a
    /// build made without the secret. Sessions are kept per API key, so changing it means
    /// connecting again.
    static func current() -> LastfmAPI.Credentials? {
        let defaults = UserDefaults.standard
        return credentials(builtInKey: builtInAPIKey,
                           concealedSecret: Bundle.main.object(forInfoDictionaryKey: secretInfoKey) as? String,
                           overrideKey: defaults.lastfmAPIKey,
                           overrideSecret: defaults.lastfmSharedSecret)
    }

    /// The same, from given values, so tests don't read the app's own.
    ///
    /// Every value is trimmed of whitespace first. The key is `overrideKey` when it isn't
    /// empty, else `builtInKey`; the secret is `overrideSecret` when it isn't empty, else the
    /// built-in one revealed. Each override stands on its own, so a secret alone serves a
    /// build made without one. A key alone is the caller's mistake: it is paired with the
    /// built-in secret, which belongs to another key, and Last.fm refuses every signature
    /// (error 13). Nothing here can tell, so nothing tries.
    static func credentials(builtInKey: String, concealedSecret: String?, overrideKey: String, overrideSecret: String) -> LastfmAPI.Credentials? {
        let overrideKey = overrideKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let overrideSecret = overrideSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = overrideKey.isEmpty ? builtInKey.trimmingCharacters(in: .whitespacesAndNewlines) : overrideKey
        let secret: String
        if !overrideSecret.isEmpty {
            secret = overrideSecret
        } else {
            secret = concealedSecret.flatMap(reveal)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !key.isEmpty, !secret.isEmpty else { return nil }
        return LastfmAPI.Credentials(apiKey: key, sharedSecret: secret)
    }

    /// The secret as the build stores it: each UTF-8 byte XORed with `pad`, in lowercase hex
    static func conceal(_ secret: String) -> String {
        let hexDigits = Array("0123456789abcdef")
        var hex = ""
        for (index, byte) in Array(secret.utf8).enumerated() {
            let concealed = byte ^ pad[index % pad.count]
            hex.append(hexDigits[Int(concealed >> 4)])
            hex.append(hexDigits[Int(concealed & 0x0F)])
        }
        return hex
    }

    /// The secret from what the build stored, or nil when that is empty, isn't hex, or
    /// doesn't come out as text.
    ///
    /// Whitespace around it is ignored. A value still holding `$(` is a build setting that
    /// was never expanded, which is never a secret, so it is nil too, though Xcode puts an
    /// empty string in place of an undefined setting.
    static func reveal(_ concealed: String) -> String? {
        let hex = concealed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty, !hex.contains("$("), hex.utf8.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.utf8.count / 2)
        var high: UInt8?
        for character in hex.utf8 {
            guard let nibble = hexValue(character) else { return nil }
            if let first = high {
                let index = bytes.count
                bytes.append(((first << 4) | nibble) ^ pad[index % pad.count])
                high = nil
            } else {
                high = nibble
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// The value of one hex digit, either case, or nil
    private static func hexValue(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return character - UInt8(ascii: "A") + 10
        default:
            return nil
        }
    }

}
