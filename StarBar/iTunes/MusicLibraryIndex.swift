//
//  MusicLibraryIndex.swift
//  StarBar
//
//  Every song in the user's Music library, read in bulk, for finding the song another player
//  is playing.
//

import AppKit
import ScriptingBridge
import iTunesLibrary
import os

/// The user's Music library as plain values, ready for `SongMatcher`.
///
/// Read with one Apple Event per property over the whole library playlist. Measured on
/// 2026-10-28 with a library of 8,092 tracks: each such read took 14 to 48 ms, and the
/// properties the matcher needs about 250 ms together. Asking Music about one song at a time
/// instead (`whose`) would apply Music's idea of equal names, not the matcher's, so a
/// remaster would never find the original.
///
/// - The reads run on a background queue with a connection of their own, addressed to
///   Music's process ID once `NSRunningApplication` says it is running, so a Music that has
///   quit is never launched again. An `SBApplication` made from a bundle ID would launch it.
/// - The index goes stale on either library notification, or when Music is a different
///   process from the one it was read from, and is read again the next time it is asked
///   for. It is never polled: see "Library changes are event-driven" in AGENTS.md.
/// - Its ratings are only good for choosing between copies of a song. Anything that shows a
///   rating or writes one reads the chosen track again by persistent ID, because the index
///   can be a notification behind, and the legacy notification has come ten seconds late.
///
/// State is read and written on the main thread only. Only `Columns` and `LibrarySong`
/// values cross from the background queue.
final class MusicLibraryIndex {

    static let shared = MusicLibraryIndex()

    /// The properties read, one Apple Event each. Cocoa keys from Music's dictionary, the
    /// same names as the vendored header's.
    static let keys = ["persistentID", "name", "artist", "albumArtist", "album", "duration",
                       "rating", "ratingKind", "playedCount", "mediaKind"]

    /// One bulk read: an array per key, every one in library order and the same length.
    /// Values are whatever Scripting Bridge decoded them to; `songs(from:)` sorts that out.
    typealias Columns = [String: [Any]]

    /// How long one Apple Event of the read may take, in ticks of 1/60 s. Each took at most
    /// 48 ms when measured; this is for a Music that has hung, so the queue is not held.
    static let readTimeout = 600

    private let queue = DispatchQueue(label: "com.rossshannon.starbar.library-index", qos: .userInitiated)

    /// The last good read, as a matcher
    private var matcher: SongMatcher?
    /// The Music process `matcher` was read from
    private var readFromPID: pid_t?
    /// Set by a library notification, cleared by a read that started after it
    private var isStale = true
    /// Bumped by every library notification, so a read that one overtook is known to be stale
    private var generation = 0
    private var isReading = false
    /// Callers waiting for the read in flight
    private var waiting: [(SongMatcher?) -> Void] = []

    /// Reads the library, on the background queue
    private let readLibrary: (pid_t) -> [LibrarySong]?
    /// Music's process, or nil when it isn't running
    private let musicPID: () -> pid_t?

    /// Same test as `iTunesRadioStation`'s: tests are hosted in the app, and a library edit
    /// in the real Music during a run must not reach them
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// The parameters are for the tests, which count reads and play at Music launching and
    /// quitting without touching the real one
    init(readLibrary: @escaping (pid_t) -> [LibrarySong]? = MusicLibraryIndex.readSongs(pid:),
         musicPID: @escaping () -> pid_t? = MusicLibraryIndex.runningMusicPID) {
        self.readLibrary = readLibrary
        self.musicPID = musicPID
    }

    /// Subscribe to both library notifications. Never under tests: they subscribe a private
    /// centre instead. Reads nothing; the first read waits until something asks.
    func start() {
        guard !MusicLibraryIndex.isRunningTests else { return }
        observeLibraryChanges(in: DistributedNotificationCenter.default())
    }

    /// The two names `iTunesRadioStation` observes, for the same reason: neither says which
    /// song changed, and the documented one has come ten seconds before the legacy one.
    func observeLibraryChanges(in center: NotificationCenter) {
        center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: .ITLibraryDidChange, object: nil)
        center.addObserver(self, selector: #selector(libraryDidChange(_:)), name: NSNotification.Name("com.apple.iTunes.libraryChanged"), object: nil)
    }

    @objc func libraryDidChange(_ notification: Notification) {
        // Distributed notifications arrive on the main thread, where this state lives
        generation += 1
        isStale = true
    }

    /// Whether the next `withMatcher` will read Music first
    var needsRead: Bool {
        return matcher == nil || isStale || readFromPID != musicPID()
    }

    /// Hand `completion` a matcher over the library, reading Music first when the library has
    /// changed since the last read. Main thread; `completion` runs on the main thread, with
    /// nil when Music isn't running or couldn't be read. It runs before this returns when
    /// nothing needs reading, or when there is no Music to read.
    func withMatcher(_ completion: @escaping (SongMatcher?) -> Void) {
        guard needsRead else { return completion(matcher) }
        waiting.append(completion)
        guard !isReading else { return }
        read()
    }

    private func read() {
        guard let pid = musicPID() else {
            matcher = nil
            readFromPID = nil
            return finish(with: nil)
        }
        isReading = true
        let generation = self.generation
        let readLibrary = self.readLibrary
        queue.async { [weak self] in
            let started = Date()
            let songs = readLibrary(pid)
            let readDone = Date()
            let matcher = songs.map { SongMatcher(library: $0) }
            let built = Date()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isReading = false
                if let songs = songs, let matcher = matcher {
                    os_log("%{public}s[%{public}ld], %{public}s: indexed %{public}ld songs in %{public}.0f ms (%{public}.0f ms reading Music)", ((#file as NSString).lastPathComponent), #line, #function, songs.count, built.timeIntervalSince(started) * 1000, readDone.timeIntervalSince(started) * 1000)
                    self.matcher = matcher
                    self.readFromPID = pid
                    // A notification that came while the read was out leaves it stale: the
                    // change may or may not be in it
                    self.isStale = self.generation != generation
                } else {
                    // Keep nothing from a failed read, and don't hand out the last good one
                    // either: Music may have gone, and nothing would be there to rate
                    self.matcher = nil
                    self.readFromPID = nil
                }
                self.finish(with: matcher)
            }
        }
    }

    private func finish(with matcher: SongMatcher?) {
        let callers = waiting
        waiting = []
        callers.forEach { $0(matcher) }
    }

    static func runningMusicPID() -> pid_t? {
        return NSRunningApplication.runningApplications(withBundleIdentifier: OSVersionHelper.bundleIdentifier)
            .first(where: { !$0.isTerminated })?.processIdentifier
    }

    // MARK: - Reading Music

    /// What one try at reading the library came to, boxed so it survives `ExceptionCatcher`,
    /// which treats a nil result as an exception
    private struct Reading {
        var columns: Columns?
    }

    /// Counts the Apple Events Music answered with an error. Scripting Bridge reports a
    /// failure here instead of raising, and hands back an empty list, which would leave one
    /// column shorter than the rest or, all of them failing, look like an empty library.
    private final class FailureCounter: NSObject, SBApplicationDelegate {
        private(set) var failures = 0
        func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
            failures += 1
            os_log(.error, "%{public}s[%{public}ld], %{public}s: reading the library failed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            return nil
        }
    }

    /// The library's songs, or nil when Music can't be read or its library changed under the
    /// read twice running. Background queue only.
    static func readSongs(pid: pid_t) -> [LibrarySong]? {
        for attempt in 1...2 {
            guard let columns = readColumns(pid: pid) else { return nil }
            if let songs = songs(from: columns) {
                return songs
            }
            os_log("%{public}s[%{public}ld], %{public}s: the library changed during read %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, attempt)
        }
        return nil
    }

    /// One bulk read, or nil when any Apple Event in it failed. Background queue only.
    private static func readColumns(pid: pid_t) -> Columns? {
        guard let application = SBApplication(processIdentifier: pid) else { return nil }
        let failures = FailureCounter()
        application.delegate = failures
        application.timeout = readTimeout
        do {
            let reading = try ExceptionCatcher.catchException {
                guard let source = iTunesRadioStation.librarySource(of: application),
                      let playlist = iTunesRadioStation.libraryPlaylist(of: source),
                      let tracks = playlist.tracks?() else { return Reading() }
                var columns = Columns()
                for key in MusicLibraryIndex.keys {
                    columns[key] = tracks.arrayByApplying(NSSelectorFromString(key))
                }
                // The IDs once more, last. If they still match the first read, no track was
                // added, removed or moved between the reads, so row i is one track in every
                // column. A count check alone would miss one song deleted and another added.
                columns[MusicLibraryIndex.recheckKey] = tracks.arrayByApplying(NSSelectorFromString("persistentID"))
                return Reading(columns: columns)
            } as? Reading
            guard failures.failures == 0 else { return nil }
            return reading?.columns
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: reading the library raised: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            return nil
        }
    }

    /// The persistent IDs as read again after every other column
    static let recheckKey = "persistentID (again)"

    // MARK: - Columns to songs

    /// The library's songs, from one bulk read. Only songs: not music videos, podcasts or the
    /// rest, which no music player's song should match.
    ///
    /// Nil when the columns don't line up, which means the library changed during the read:
    /// pairing one track's name with another's persistent ID would aim a rating at the wrong
    /// song. Also nil for no tracks at all, because a read that went wrong quietly looks
    /// exactly like that, and an empty index would match nothing until the next library edit.
    static func songs(from columns: Columns) -> [LibrarySong]? {
        guard let ids = columns["persistentID"], !ids.isEmpty,
              keys.allSatisfy({ columns[$0]?.count == ids.count }),
              let recheck = columns[recheckKey], (recheck as NSArray).isEqual(to: ids) else { return nil }
        let names = columns["name"] ?? []
        let artists = columns["artist"] ?? []
        let albumArtists = columns["albumArtist"] ?? []
        let albums = columns["album"] ?? []
        let durations = columns["duration"] ?? []
        let ratings = columns["rating"] ?? []
        let ratingKinds = columns["ratingKind"] ?? []
        let playedCounts = columns["playedCount"] ?? []
        let mediaKinds = columns["mediaKind"] ?? []

        var songs: [LibrarySong] = []
        songs.reserveCapacity(ids.count)
        for row in ids.indices {
            guard code(mediaKinds[row]) == iTunesEMdK.music.rawValue,
                  let persistentID = ids[row] as? String, !persistentID.isEmpty,
                  let name = names[row] as? String,
                  let artist = artists[row] as? String else { continue }
            songs.append(LibrarySong(
                persistentID: persistentID,
                name: name,
                artist: artist,
                albumArtist: albumArtists[row] as? String ?? "",
                album: albums[row] as? String ?? "",
                duration: (durations[row] as? NSNumber)?.doubleValue,
                rating: (ratings[row] as? NSNumber)?.intValue ?? 0,
                isRatingComputed: code(ratingKinds[row]) == iTunesERtK.computed.rawValue,
                playedCount: (playedCounts[row] as? NSNumber)?.intValue ?? 0
            ))
        }
        return songs
    }

    /// An enumerated value's four-character code. Scripting Bridge hands one back as a number
    /// or as a descriptor depending on how it was asked for, so take either, like
    /// `SpotifyPlayer.state(_:)`.
    static func code(_ value: Any) -> FourCharCode? {
        if let number = value as? NSNumber {
            return number.uint32Value
        }
        if let descriptor = value as? NSAppleEventDescriptor {
            return descriptor.enumCodeValue != 0 ? descriptor.enumCodeValue : descriptor.typeCodeValue
        }
        return nil
    }

}
