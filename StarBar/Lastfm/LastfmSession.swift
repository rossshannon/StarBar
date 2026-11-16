//
//  LastfmSession.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation
import os

/// A Last.fm sign-in: the user's name and the session key that signs calls for them.
/// The key never expires; it ends only when the user removes StarBar under Applications in
/// their Last.fm settings, which a call then reports as `LastfmAPI.Failure.sessionInvalid`.
struct LastfmSession: Codable, Equatable {
    let name: String
    let key: String
}

/// Keeps the sign-in between launches. Called off the main thread.
protocol LastfmSessionStore {
    /// The sign-in kept for this API key, or nil
    func load(apiKey: String) -> LastfmSession?
    func save(_ session: LastfmSession, apiKey: String)
    func delete(apiKey: String)
}

/// Where Last.fm's files are kept: `Application Support/Lastfm`, which for the sandboxed app
/// is inside its container. The sign-in and the scrobbles waiting to be sent
/// (`FileScrobbleQueueStore`) share it.
enum LastfmFiles {
    static var directory: URL {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lastfm", isDirectory: true)
    }
}

/// The sign-in as a 0600 JSON file per API key, in a 0700 folder, written atomically. A file
/// and not the Keychain for the reason `FileSpotifyTokenStore` gives: the Keychain ties an
/// item to the exact code that made it, so every ad hoc update would show a Keychain prompt.
/// What the key can do if another process running as the user reads it: scrobble, and love
/// and unlove songs, as that user.
final class FileLastfmSessionStore: LastfmSessionStore {

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? LastfmFiles.directory
    }

    /// One file per API key, so a sign-in made with another key is never picked up. The key
    /// is reduced to ASCII letters and digits before it becomes a file name.
    func url(apiKey: String) -> URL {
        let safe = String(apiKey.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) })
        return directory.appendingPathComponent("sign-in-\(safe).json")
    }

    func load(apiKey: String) -> LastfmSession? {
        let file = url(apiKey: apiKey)
        guard let data = try? Data(contentsOf: file) else { return nil }
        do {
            return try JSONDecoder().decode(LastfmSession.self, from: data)
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't read the Last.fm sign-in: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            return nil
        }
    }

    func save(_ session: LastfmSession, apiKey: String) {
        do {
            let data = try JSONEncoder().encode(session)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = url(apiKey: apiKey)
            try data.write(to: file, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't keep the Last.fm sign-in: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
        }
    }

    func delete(apiKey: String) {
        let file = url(apiKey: apiKey)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't remove the Last.fm sign-in: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
        }
    }

}
