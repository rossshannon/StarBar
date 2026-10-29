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

/// The names in the user's Music library, ready for `SongMatcher` to find the copies of a
/// song by.
///
/// Read with one Apple Event per property over the whole library playlist. Asking Music
/// about one song at a time instead (`whose`) would apply Music's idea of equal names, not
/// the matcher's, so a remaster would never find the original.
///
/// Only what finding a song takes is read here: the persistent ID, name, artist and album
/// artist. What chooses between copies (album, length, rating, plays) and whether a copy is
/// a song at all are read for the few copies a song has (`readCopies`). Measured
/// 2026-10-28 on 8,092 tracks, a bulk read took 14 to 48 ms; on 2026-10-29, on the same
/// library, the ten properties first read took 0.35 s, 4.4 s and 25 s at three launches.
/// Music answers Apple Events one at a time, so while one of these is out, every other
/// read StarBar makes waits behind it. Each read's timing is logged.
///
/// - The reads run on a background queue with a connection of their own, addressed to
///   Music's process ID once `NSRunningApplication` says it is running, so a Music that has
///   quit is never launched again. An `SBApplication` made from a bundle ID would launch it.
/// - The index goes stale on either library notification, or when Music is a different
///   process from the one it was read from, and is read again the next time it is asked
///   for. It is never polled: see "Library changes are event-driven" in AGENTS.md.
/// - Nothing it holds is shown or written. Anything that shows a rating or writes one reads
///   the chosen track again by persistent ID, because the index can be a notification
///   behind, and the legacy notification has come ten seconds late.
///
/// State is read and written on the main thread only. Only `Columns` and `LibrarySong`
/// values cross from the background queue.
final class MusicLibraryIndex {

    static let shared = MusicLibraryIndex()

    /// The properties read, one Apple Event each. Cocoa keys from Music's dictionary, the
    /// same names as the vendored header's.
    static let keys = ["persistentID", "name", "artist", "albumArtist"]

    /// The columns a song can't do without. A short one of these makes the whole read
    /// useless; a short one of the rest is only left out of it (`unpairedColumns(in:)`).
    static let requiredKeys: Set<String> = ["persistentID", "name", "artist"]

    /// One bulk read: an array per key, in library order. Values are whatever Scripting
    /// Bridge decoded them to; `songs(from:)` sorts that out. **A column can be shorter than
    /// the library**: Scripting Bridge leaves a missing value out of the array rather than
    /// hold its place. Measured 2026-10-29 on 8,093 tracks: three songs with no length left
    /// `duration` with 8,090 values, and every one after the first gap belonged to the row
    /// before.
    typealias Columns = [String: [Any]]

    /// How long one Apple Event of the read may take, in ticks of 1/60 s. This is for a Music
    /// that has hung, so the queue is not held.
    static let readTimeout = 600

    /// The same for reading a few copies, whose events each ask for one value of one track.
    /// Measured 2026-10-29, the slowest took over a second after Music sat idle for seven
    /// minutes; a Music that takes longer has stopped answering for now, and the finder asks
    /// again later.
    static let copiesTimeout = 180

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
    /// Reads a few library songs from Music, on the background queue
    private let readCopiesOfSong: (pid_t, [LibrarySong], Bool) -> [LibrarySong?]?
    /// Music's process, or nil when it isn't running
    private let musicPID: () -> pid_t?

    /// Same test as `iTunesRadioStation`'s: tests are hosted in the app, and a library edit
    /// in the real Music during a run must not reach them
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// The parameters are for the tests, which count reads and play at Music launching and
    /// quitting without touching the real one
    init(readLibrary: @escaping (pid_t) -> [LibrarySong]? = MusicLibraryIndex.readSongs(pid:),
         readCopies: @escaping (pid_t, [LibrarySong], Bool) -> [LibrarySong?]? = MusicLibraryIndex.readCopies(pid:of:choosing:),
         musicPID: @escaping () -> pid_t? = MusicLibraryIndex.runningMusicPID) {
        self.readLibrary = readLibrary
        self.readCopiesOfSong = readCopies
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
        markStale()
    }

    /// The library has changed, or something has shown it has before its notification came:
    /// the next `withMatcher` reads it again. Main thread.
    func markStale() {
        generation += 1
        isStale = true
    }

    /// Whether the next `withMatcher` will read Music first
    var needsRead: Bool {
        return matcher == nil || isStale || readFromPID != musicPID()
    }

    /// Whether Music is running, which tells a `withMatcher` nil for a read that failed from
    /// one for no Music to read
    var isMusicRunning: Bool {
        return musicPID() != nil
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
        let previous = matcher
        queue.async { [weak self] in
            let started = Date()
            let songs = readLibrary(pid)
            let readDone = Date()
            let matcher = songs.map { SongMatcher(library: $0, reusing: previous) }
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

    /// What Music says now about each of `songs`, the copies of one song, with what
    /// `LibrarySong.reading(_:choosing:)` reads. On the index's queue and connection, so a
    /// Music slow to answer holds no thread anything else waits on: these are several Apple
    /// Events per copy, and Music has taken over a second to answer the first after a spell
    /// idle.
    ///
    /// `completion` runs on the main thread with an entry per song, nil for one that has
    /// gone, has changed or isn't a song; or with nil when Music isn't running or didn't
    /// answer, which says nothing about the songs. Before this returns when there is no Music.
    func readCopies(_ songs: [LibrarySong], choosing: Bool, completion: @escaping ([LibrarySong?]?) -> Void) {
        guard let pid = musicPID() else { return completion(nil) }
        let readCopies = readCopiesOfSong
        queue.async {
            let started = Date()
            let copies = readCopies(pid, songs, choosing)
            let elapsed = Date().timeIntervalSince(started) * 1000
            DispatchQueue.main.async {
                os_log("%{public}s[%{public}ld], %{public}s: read %{public}ld library copies in %{public}.0f ms%{public}s", ((#file as NSString).lastPathComponent), #line, #function, songs.count, elapsed, copies == nil ? ", but Music didn't answer" : "")
                completion(copies)
            }
        }
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
        /// Milliseconds each column took, in the order read
        var timings: [(key: String, ms: Double)] = []
    }

    /// Counts the Apple Events Music answered with an error. Scripting Bridge reports a
    /// failure here instead of raising, and hands back an empty list, which would leave one
    /// column shorter than the rest or, all of them failing, look like an empty library.
    ///
    /// After the first failure the read is thrown away whatever follows, so the rest of its
    /// events are given a timeout of one tick: a Music that has stopped answering would
    /// otherwise hold the queue for the whole timeout once for every event still to send.
    private final class FailureCounter: NSObject, SBApplicationDelegate {
        private(set) var failures = 0
        private weak var application: SBApplication?

        init(_ application: SBApplication) {
            self.application = application
        }

        func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
            failures += 1
            application?.timeout = 1
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
                let unpaired = unpairedColumns(in: columns)
                if !unpaired.isEmpty, let count = columns["persistentID"]?.count {
                    let counts = unpaired.map { "\($0) has \(columns[$0]?.count ?? 0)" }.joined(separator: ", ")
                    os_log("%{public}s[%{public}ld], %{public}s: %{public}ld tracks, but %{public}s, so Music left a value out and those can't be paired with their tracks; read without them", ((#file as NSString).lastPathComponent), #line, #function, count, counts)
                }
                return songs
            }
            os_log(.error, "%{public}s[%{public}ld], %{public}s: read %{public}ld can't be used: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, attempt, misalignment(in: columns) ?? "no reason found")
        }
        return nil
    }

    /// One bulk read, or nil when any Apple Event in it failed. Background queue only.
    private static func readColumns(pid: pid_t) -> Columns? {
        guard let application = SBApplication(processIdentifier: pid) else { return nil }
        let failures = FailureCounter(application)
        application.delegate = failures
        application.timeout = readTimeout
        do {
            let reading = try ExceptionCatcher.catchException {
                guard let source = iTunesRadioStation.librarySource(of: application),
                      let playlist = iTunesRadioStation.libraryPlaylist(of: source),
                      let tracks = playlist.tracks?() else { return Reading() }
                var reading = Reading(columns: Columns())
                func read(_ key: String, as name: String) {
                    let started = DispatchTime.now().uptimeNanoseconds
                    reading.columns?[name] = MusicLibraryIndex.column(key, of: tracks)
                    reading.timings.append((name, Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000))
                }
                for key in MusicLibraryIndex.keys {
                    read(key, as: key)
                }
                // The IDs once more, last. If they still match the first read, no track was
                // added, removed or moved between the reads, so row i is one track in every
                // column. A count check alone would miss one song deleted and another added.
                read("persistentID", as: MusicLibraryIndex.recheckKey)
                return reading
            } as? Reading
            if let timings = reading?.timings, !timings.isEmpty {
                os_log("%{public}s[%{public}ld], %{public}s: read %{public}s", ((#file as NSString).lastPathComponent), #line, #function, timings.map { String(format: "%@ in %.0f ms", $0.key, $0.ms) }.joined(separator: ", "))
            }
            guard failures.failures == 0 else { return nil }
            return reading?.columns
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: reading the library raised: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            return nil
        }
    }

    /// What one try at reading copies came to, boxed for `ExceptionCatcher` like `Reading`
    private struct CopiesReading {
        var playlist: iTunesPlaylist?
        var copies: [LibrarySong?]?
    }

    /// The connection and library playlist the last `readCopies` read through, kept for the
    /// next one in the same Music process: finding the playlist is four Apple Events, nearly as
    /// many as reading a copy takes. Dropped after any failure, so a read that failed
    /// finds it afresh. Index queue only.
    private static var copiesConnection: (pid: pid_t, application: SBApplication, playlist: iTunesPlaylist)?

    /// `readCopies(_:choosing:completion:)`'s read. Each copy is found by persistent ID (a
    /// `whose` search, never `object(withID:)`) and must still have the index's name and
    /// artist. Nil when any Apple Event failed: Scripting Bridge answers a timed-out search
    /// with an empty list, which would look like a song that has gone. Background queue only.
    ///
    /// Each copy is one event for the search, resolved with `get()`, which hands back Music's
    /// own reference to the track, by ID, so the reads after it don't search the library
    /// again; then one for each property `LibrarySong.reading(_:choosing:)` reads, four for a
    /// song with no rating and nothing to choose between. Music answers each in 15 to 25 ms
    /// when idle, and far slower after a busy spell: on 2026-10-29 the eight events of an
    /// earlier build took 122 to 200 ms with Music idle, and 0.46 to 2.1 s while it was still
    /// slow from a run of live tests.
    static func readCopies(pid: pid_t, of songs: [LibrarySong], choosing: Bool) -> [LibrarySong?]? {
        let kept = copiesConnection?.pid == pid ? copiesConnection : nil
        copiesConnection = nil
        guard let application = kept?.application ?? SBApplication(processIdentifier: pid) else { return nil }
        let failures = FailureCounter(application)
        application.delegate = failures
        // The delegate isn't retained, and the connection outlives this read
        defer { application.delegate = nil }
        application.timeout = copiesTimeout
        do {
            let reading = try ExceptionCatcher.catchException {
                guard let playlist = kept?.playlist ?? iTunesRadioStation.libraryPlaylistByID(of: application),
                      let tracks = playlist.tracks?() else { return CopiesReading() }
                return CopiesReading(playlist: playlist, copies: songs.map { song -> LibrarySong? in
                    // The read is thrown away after a failure: ask Music nothing more
                    guard failures.failures == 0 else { return nil }
                    // The name and artist are checked by the search itself, which saves an
                    // event for each
                    let predicate = NSPredicate(format: "persistentID == %@ AND name == %@ AND artist == %@",
                                                song.persistentID, song.name, song.artist)
                    let search = tracks.perform(#selector(NSArray.filtered(using:)), with: predicate)?
                        .takeUnretainedValue() as? SBElementArray
                    let found = search?.get() as? [iTunesTrack] ?? []
                    guard found.count == 1, let track = found.first else {
                        os_log("%{public}s[%{public}ld], %{public}s: library song %{public}s is not \u{201C}%{public}s\u{201D} by %{public}s any more (%{public}ld found)", ((#file as NSString).lastPathComponent), #line, #function, song.persistentID, song.name, song.artist, found.count)
                        return nil
                    }
                    guard let read = song.reading(track, choosing: choosing) else {
                        os_log("%{public}s[%{public}ld], %{public}s: library track %{public}s, \u{201C}%{public}s\u{201D} by %{public}s, isn't a song", ((#file as NSString).lastPathComponent), #line, #function, song.persistentID, song.name, song.artist)
                        return nil
                    }
                    return read
                })
            } as? CopiesReading
            guard failures.failures == 0 else { return nil }
            if let playlist = reading?.playlist {
                copiesConnection = (pid: pid, application: application, playlist: playlist)
            }
            return reading?.copies
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: reading library copies raised: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            return nil
        }
    }

    /// The persistent IDs as read again after every other column
    static let recheckKey = "persistentID (again)"

    private static let arrayByApplyingSelector = NSSelectorFromString("arrayByApplyingSelector:")

    /// One property of every track, in one Apple Event: `-[SBElementArray
    /// arrayByApplyingSelector:]`. Called by its Objective-C name, which is the documented
    /// one: Xcode 16.4's SDK has no `arrayByApplying(_:)`. Nil when the method isn't there.
    /// Background queue only.
    private static func column(_ key: String, of tracks: SBElementArray) -> [Any]? {
        typealias Apply = @convention(c) (AnyObject, Selector, Selector) -> NSArray?
        guard tracks.responds(to: arrayByApplyingSelector) else { return nil }
        let apply = unsafeBitCast(tracks.method(for: arrayByApplyingSelector), to: Apply.self)
        return apply(tracks, arrayByApplyingSelector, NSSelectorFromString(key)) as? [Any]
    }

    // MARK: - Columns to songs

    /// The library's tracks, from one bulk read: names only, with the album, length, rating
    /// and plays left for `LibraryMatchFinder` to read for the copies it finds. Every kind
    /// of track, music videos included, since telling them apart is another column; the
    /// finder checks that a copy is a song before it is shown or rated.
    ///
    /// Nil when the columns a song needs don't line up, which means the library changed
    /// during the read or Music left one of those values out: pairing one track's name with
    /// another's persistent ID would aim a rating at the wrong song. Also nil for no tracks
    /// at all, because a read that went wrong quietly looks exactly like that, and an empty
    /// index would match nothing until the next library edit. Any other column that doesn't
    /// line up is left out, as if every track lacked that value: the songs lose only a way
    /// of choosing between copies.
    static func songs(from columns: Columns) -> [LibrarySong]? {
        guard misalignment(in: columns) == nil, let ids = columns["persistentID"] else { return nil }
        let unpaired = Set(unpairedColumns(in: columns))
        let none = [Any](repeating: NSNull(), count: ids.count)
        func column(_ key: String) -> [Any] {
            return unpaired.contains(key) ? none : columns[key] ?? none
        }
        let names = column("name")
        let artists = column("artist")
        let albumArtists = column("albumArtist")

        var songs: [LibrarySong] = []
        songs.reserveCapacity(ids.count)
        for row in ids.indices {
            guard let persistentID = ids[row] as? String, !persistentID.isEmpty,
                  let name = names[row] as? String,
                  let artist = artists[row] as? String else { continue }
            songs.append(LibrarySong(persistentID: persistentID, name: name, artist: artist,
                                     albumArtist: albumArtists[row] as? String ?? ""))
        }
        return songs
    }

    /// Why a bulk read can't be used, in words for the log, or nil when the columns a song
    /// needs line up. The causes look alike from outside -- each makes the read useless --
    /// but not when working out why every read fails.
    static func misalignment(in columns: Columns) -> String? {
        guard let ids = columns["persistentID"] else { return "no persistent ID column" }
        guard !ids.isEmpty else { return "no tracks" }
        let required = keys.filter { requiredKeys.contains($0) }
        let missing = required.filter { columns[$0] == nil }
        guard missing.isEmpty else { return "no column for " + missing.joined(separator: ", ") }
        let uneven = required.filter { columns[$0]?.count != ids.count }
        guard uneven.isEmpty else {
            return "\(ids.count) persistent IDs, but " + uneven.map { "\($0) has \(columns[$0]?.count ?? 0)" }.joined(separator: ", ")
        }
        guard let recheck = columns[recheckKey] else { return "the persistent IDs weren't read again" }
        guard !(recheck as NSArray).isEqual(to: ids) else { return nil }
        guard recheck.count == ids.count else { return "\(ids.count) persistent IDs, then \(recheck.count) when read again" }
        let row = ids.indices.first(where: { !(ids[$0] as AnyObject).isEqual(recheck[$0]) }) ?? 0
        return "the persistent IDs read again differ from row \(row): \(ids[row]) (\(type(of: ids[row]))) then \(recheck[row]) (\(type(of: recheck[row])))"
    }

    /// The columns other than `requiredKeys` that don't have a value for every track, which
    /// `songs(from:)` leaves out. Only `duration` has been seen short (it isn't read any
    /// more), for songs Music had no length for, but any property Music can answer "missing
    /// value" for can be.
    static func unpairedColumns(in columns: Columns) -> [String] {
        guard let count = columns["persistentID"]?.count else { return [] }
        return keys.filter { !requiredKeys.contains($0) && columns[$0]?.count != count }
    }

}
