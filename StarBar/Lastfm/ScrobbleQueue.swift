//
//  ScrobbleQueue.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation
import os

/// What is waiting to be sent to Last.fm for one user, kept on disk so that a play made
/// offline, or just before a quit, is sent when Last.fm can next be reached.
///
/// It holds scrobbles, oldest first; hearts set or cleared in StarBar (`LoveChange`); and,
/// per player, the last play scrobbled (`PlayTracker.Earlier`), so a song still playing when
/// StarBar opens again isn't scrobbled a second time.
///
/// Nothing leaves the queue until Last.fm has answered for it: `nextBatch()` only looks, and
/// `finished(_:)` removes. Every change is handed to the store at once.
///
/// Last.fm ignores a scrobble whose time is more than about two weeks old, so one older than
/// `maxAge` is dropped rather than sent, and so is the oldest once there are more than
/// `maxScrobbles`. Main thread only. Covered by `ScrobbleQueueTests`.
final class ScrobbleQueue {

    /// A heart set or cleared in StarBar, to love or unlove the song on Last.fm
    struct LoveChange: Codable, Equatable {
        var title: String
        var artist: String
        var loved: Bool

        /// True for a change to the same song, whichever way: same title and artist,
        /// compared without case
        func isForSameSong(as other: LoveChange) -> Bool {
            return ScrobbleQueue.sameName(title, other.title) && ScrobbleQueue.sameName(artist, other.artist)
        }
    }

    /// What is kept on disk
    struct Contents: Codable, Equatable {
        var scrobbles: [Scrobble] = []
        var loves: [LoveChange] = []
        /// The last play scrobbled, by player (`PlayerKind` raw value)
        var lastScrobbled: [String: PlayTracker.Earlier] = [:]

        fileprivate enum CodingKeys: String, CodingKey {
            case scrobbles, loves, lastScrobbled
        }
    }

    static let maxAge: TimeInterval = 14 * 24 * 60 * 60
    static let maxScrobbles = 5000
    static let maxLoves = 500

    let user: String
    private(set) var contents: Contents

    private let store: ScrobbleQueueStore
    private let now: () -> Date

    /// Reads what the store has for `user`, or starts empty, and drops what has grown too old
    /// to send while StarBar was closed
    init(user: String, store: ScrobbleQueueStore, now: @escaping () -> Date = Date.init) {
        self.user = user
        self.store = store
        self.now = now
        self.contents = store.load(user: user) ?? Contents()
        if dropTooOld() {
            save()
        }
    }

    /// Keep a play to send. One with the same song and start time as one already waiting is
    /// not added twice, and one Last.fm would never take (no title or no artist) not at all.
    /// It goes in order of when it started, since two players can finish plays out of order.
    func add(_ scrobble: Scrobble) {
        guard scrobble.track.canBeSent else { return }
        let isDuplicate = contents.scrobbles.contains { waiting in
            waiting.timestamp == scrobble.timestamp
                && Self.sameName(waiting.track.title, scrobble.track.title)
                && Self.sameName(waiting.track.artist, scrobble.track.artist)
        }
        guard !isDuplicate else { return }

        // After every one that started at the same time or before, so equal times keep the
        // order they were added in
        let index = contents.scrobbles.firstIndex { $0.startedAt > scrobble.startedAt } ?? contents.scrobbles.endIndex
        contents.scrobbles.insert(scrobble, at: index)

        let over = contents.scrobbles.count - Self.maxScrobbles
        if over > 0 {
            contents.scrobbles.removeFirst(over)
            os_log("%{public}s[%{public}ld], %{public}s: dropped the %{public}ld oldest scrobbles waiting, past the limit of %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, over, Self.maxScrobbles)
        }
        save()
    }

    /// Up to `LastfmAPI.maxBatch` scrobbles to send next, oldest first, after dropping those
    /// too old to be taken. They stay in the queue.
    func nextBatch() -> [Scrobble] {
        if dropTooOld() {
            save()
        }
        return Array(contents.scrobbles.prefix(LastfmAPI.maxBatch))
    }

    /// Last.fm answered for `batch`, or will never take it: remove those scrobbles
    func finished(_ batch: [Scrobble]) {
        guard !batch.isEmpty else { return }
        let before = contents.scrobbles.count
        contents.scrobbles.removeAll { batch.contains($0) }
        if contents.scrobbles.count != before {
            save()
        }
    }

    /// Keep a heart to send. It replaces a change still waiting for the same song, so a
    /// heart set and cleared while offline sends only where it ended up. One with no title or
    /// no artist is ignored, since Last.fm takes nothing without them.
    func add(_ change: LoveChange) {
        guard !change.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !change.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var loves = contents.loves.filter { !$0.isForSameSong(as: change) }
        loves.append(change)
        let over = loves.count - Self.maxLoves
        if over > 0 {
            loves.removeFirst(over)
            os_log("%{public}s[%{public}ld], %{public}s: dropped the %{public}ld oldest hearts waiting, past the limit of %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, over, Self.maxLoves)
        }
        // The same change added again, already last, changes nothing
        guard loves != contents.loves else { return }
        contents.loves = loves
        save()
    }

    /// The oldest heart waiting, which stays in the queue
    var nextLove: LoveChange? {
        return contents.loves.first
    }

    /// Last.fm answered for `change`, or will never take it: remove it. A newer change for
    /// the same song, added while this one was being sent, stays, because it replaced this
    /// one and so nothing equal to `change` is left to remove.
    func finished(_ change: LoveChange) {
        guard let index = contents.loves.firstIndex(of: change) else { return }
        contents.loves.remove(at: index)
        save()
    }

    /// Remember the last play scrobbled for `player` (a `PlayerKind` raw value)
    func noteScrobbled(_ play: PlayTracker.Earlier, player: String) {
        guard contents.lastScrobbled[player] != play else { return }
        contents.lastScrobbled[player] = play
        save()
    }

    func lastScrobbled(player: String) -> PlayTracker.Earlier? {
        return contents.lastScrobbled[player]
    }

    /// True when no scrobble and no heart is waiting. The last play scrobbled per player
    /// doesn't count, since nothing is sent for it.
    var isEmpty: Bool {
        return contents.scrobbles.isEmpty && contents.loves.isEmpty
    }

    /// Forget everything, here and on disk: the user disconnected
    func deleteAll() {
        contents = Contents()
        store.delete(user: user)
    }

    // MARK: - Private

    /// Drops scrobbles older than `maxAge`, which Last.fm would ignore. True if any went.
    private func dropTooOld() -> Bool {
        let oldest = now().addingTimeInterval(-Self.maxAge)
        let before = contents.scrobbles.count
        contents.scrobbles.removeAll { $0.startedAt < oldest }
        let dropped = before - contents.scrobbles.count
        if dropped > 0 {
            os_log("%{public}s[%{public}ld], %{public}s: dropped %{public}ld scrobbles too old for Last.fm to take", ((#file as NSString).lastPathComponent), #line, #function, dropped)
        }
        return dropped > 0
    }

    private func save() {
        store.save(contents, user: user)
    }

    fileprivate static func sameName(_ a: String, _ b: String) -> Bool {
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

}

extension ScrobbleQueue.Contents {

    /// Read by hand, in an extension so the memberwise initialiser stays: a file from a build
    /// that kept less still reads, and what it lacks starts empty. Left to the compiler,
    /// a file missing one key would be thrown away, and the plays waiting in it with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scrobbles: try container.decodeIfPresent([Scrobble].self, forKey: .scrobbles) ?? [],
            loves: try container.decodeIfPresent([ScrobbleQueue.LoveChange].self, forKey: .loves) ?? [],
            lastScrobbled: try container.decodeIfPresent([String: PlayTracker.Earlier].self, forKey: .lastScrobbled) ?? [:]
        )
    }

}

/// Keeps a user's queue between launches
protocol ScrobbleQueueStore {
    func load(user: String) -> ScrobbleQueue.Contents?
    func save(_ contents: ScrobbleQueue.Contents, user: String)
    func delete(user: String)
    /// Returns once every save and delete so far is on disk. Called as the app quits.
    func synchronize()
}

/// A queue as a 0600 JSON file per user in `LastfmFiles.directory`, written atomically.
///
/// `save` and `delete` return at once and do their work in order on a queue of their own,
/// because every scrobble saves and a write on the main thread can cost a frame of whatever
/// is moving on screen. `load` waits for the writes before it, so it never reads a file that
/// is behind. A file that can't be read (damaged, or from a newer version) is treated as
/// empty and replaced at the next save.
final class FileScrobbleQueueStore: ScrobbleQueueStore {

    private let directory: URL
    private let queue = DispatchQueue(label: "com.rossshannon.starbar.lastfm-queue", qos: .utility)

    init(directory: URL? = nil) {
        self.directory = directory ?? LastfmFiles.directory
    }

    /// `queue-<user>.json`, with the user's name reduced to ASCII letters, digits, "-" and
    /// "_" and put in lower case, since Last.fm's names are not case-sensitive. A name with
    /// none of those left is `queue-unnamed.json`.
    func url(user: String) -> URL {
        let safe = String(user.lowercased().unicodeScalars.filter { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        })
        return directory.appendingPathComponent("queue-\(safe.isEmpty ? "unnamed" : safe).json")
    }

    func load(user: String) -> ScrobbleQueue.Contents? {
        // A sync from the store's own queue would deadlock
        dispatchPrecondition(condition: .notOnQueue(queue))
        let file = url(user: user)
        return queue.sync { () -> ScrobbleQueue.Contents? in
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            do {
                let data = try Data(contentsOf: file)
                return try Self.decoder().decode(ScrobbleQueue.Contents.self, from: data)
            } catch {
                os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't read the Last.fm queue for %{public}s, starting empty: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, user, error.localizedDescription)
                return nil
            }
        }
    }

    func save(_ contents: ScrobbleQueue.Contents, user: String) {
        let data: Data
        do {
            data = try Self.encoder().encode(contents)
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't encode the Last.fm queue for %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, user, error.localizedDescription)
            return
        }
        let directory = self.directory
        let file = url(user: user)
        queue.async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try data.write(to: file, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch {
                os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't keep the Last.fm queue for %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, user, error.localizedDescription)
            }
        }
    }

    func delete(user: String) {
        let file = url(user: user)
        queue.async {
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                os_log(.error, "%{public}s[%{public}ld], %{public}s: couldn't remove the Last.fm queue for %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, user, error.localizedDescription)
            }
        }
    }

    func synchronize() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        queue.sync {}
    }

    // The same date form both ways, set rather than left to the default, so a file written by
    // one build is read by the next
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

}
