//
//  iTunesRadioStation.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-6-28.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation
import AppKit
import ScriptingBridge
import os
import MASShortcut
import iTunesLibrary

extension Notification.Name {
//    static let iTunesPlayInfoChanged = Notification.Name("iTunesPlayInfoChanged")
//    static let iTunesRadioDidSetupRating = Notification.Name("iTunesRadioDidSetupRating")
    static let iTunesRadioRequestTrackRatingUp = Notification.Name("iTunesRadioRequestTrackRatingUp")
    static let iTunesRadioRequestTrackRatingDown = Notification.Name("iTunesRadioRequestTrackRatingDown")
    static let iTunesRadioRequestTrackRating5 = Notification.Name("iTunesRadioRequestTrackRating5")
    static let iTunesRadioRequestTrackRating4 = Notification.Name("iTunesRadioRequestTrackRating4")
    static let iTunesRadioRequestTrackRating3 = Notification.Name("iTunesRadioRequestTrackRating3")
    static let iTunesRadioRequestTrackRating2 = Notification.Name("iTunesRadioRequestTrackRating2")
    static let iTunesRadioRequestTrackRating1 = Notification.Name("iTunesRadioRequestTrackRating1")
    static let iTunesRadioRequestTrackRating0 = Notification.Name("iTunesRadioRequestTrackRating0")
}

final class iTunesRadioStation {

    let logger = Logger(subsystem: "iTunesRadioStation", category: "Service")

    // MARK: - Singleton
    static let shared = iTunesRadioStation()

    private lazy var _iTunes: iTunesApplication? = {
        let application = SBApplication(bundleIdentifier: OSVersionHelper.bundleIdentifier)
        application?.delegate = self
        return application
    }()

    var iTunes: iTunesApplication? {
        guard _iTunes?.isRunning == true else {
            return nil
        }
        return _iTunes
    }

    private(set) var latestPlayInfo: PlayInfo? {
        didSet {
            iTunesPlayer.shared.update()
            // os_log("%{public}s[%{public}ld], %{public}s: latestPlayInfo %s", ((#file as NSString).lastPathComponent), #line, #function, latestPlayInfo?.description ?? "nil")
        }
    }

    /// When a chosen rating is sent to Music: the first goes at once, the rest wait.
    /// The writer decides when; `write(_:)` below is what it performs.
    private lazy var ratingWriter = RatingWriter(interval: iTunesRadioStation.ratingSaveDelay) { [unowned self] request in
        self.write(request)
    }

    /// The longest `setRating(_:)` can hold a rating before saving it to Music.
    ///
    /// A rating usually goes out at once. Only one arriving while a previous write is still
    /// fresh waits, and never longer than this plus the hold timer's tolerance (0.2 s, from
    /// `RunLoopClock`), so that sum is the upper bound anything downstream has to allow for.
    /// `TrackAnnouncementController.pendingRatingLifetime` allows a full second over it.
    static let ratingSaveDelay: TimeInterval = 2.0

    /// How long after Music refuses a write the player is read again, so the stars fall back
    /// to what Music has. Long enough for Music to have settled after the refusal, short
    /// enough that the wrong stars are not on screen for long.
    static let refusedWriteRereadDelay: TimeInterval = 0.5
    /// The re-read scheduled after a refused write, so several refusals mean one read
    private var refusedWriteReread: DispatchWorkItem?
    /// True while a re-read after a refused write is waiting to run. Not private only so the
    /// tests can see it, like `classAndID(of:)`.
    var hasPendingRereadAfterRefusedWrite: Bool {
        return refusedWriteReread != nil
    }

    /// Coalesces a run of `libraryChanged` notifications into one re-read
    private var libraryChangedTimer: Timer?

    /// How long to wait after a library change before re-reading the player.
    ///
    /// Neither library notification identifies the changed song. Coalesce a burst before
    /// re-reading, allowing Music a short settling interval. Keep the later legacy signal
    /// as a second opportunity to reconcile if the earlier read was too soon.
    static let libraryChangedReadDelay: TimeInterval = 0.3

    /// Runs while an add to the library is waiting to land
    private var addToLibraryTimer: Timer?
    /// How often to look for a song added to the library. Each look is an Apple Event of
    /// about 35 ms, and the add usually lands on the first or second one.
    static let addToLibraryPollInterval: TimeInterval = 0.25
    /// How long to keep looking. The add goes through the cloud library, so allow for a slow
    /// network rather than giving up while it is still on its way.
    static let addToLibraryTimeout: TimeInterval = 10.0

    private init() {
        // Listen iTunes play state change notification
        // Note: The notification name on Catalina is same as Mojave
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(iTunesRadioStation.playInfoChanged(_:)), name: NSNotification.Name("com.apple.iTunes.playerInfo"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(iTunesRadioStation.sourceSaved(_:)), name: NSNotification.Name("com.apple.iTunes.sourceSaved"), object: nil)  // only set rating in iTunes edit song info panel can trigger that
        observeLibraryChanges(in: DistributedNotificationCenter.default())

        // Due to iTunes may already playing before app launch,update player when app start
        iTunesPlayer.shared.update(iTunes?.currentTrackCopy)
        observeMusicLifecycle()

        // Bind and broadcast keyboard
        // Notify control directly without trigger player update notification
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.ratingUp.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRatingUp, object: nil)
        })
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.ratingDown.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRatingDown, object: nil)
        })
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.rating5.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRating5, object: nil)
        })
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.rating4.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRating4, object: nil)
        })
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.rating3.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRating3, object: nil)
        })
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.rating2.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRating2, object: nil)
        })
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.rating1.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRating1, object: nil)
        })
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.rating0.rawValue, toAction: {
            iTunesPlayer.shared.update(broadcast: false)
            NotificationCenter.default.post(name: .iTunesRadioRequestTrackRating0, object: nil)
        })
    }

}

extension iTunesRadioStation {

    /// A local notification centre lets tests exercise the real subscriptions without
    /// sending synthetic Music notifications to other running apps.
    func observeLibraryChanges(in center: NotificationCenter) {
        center.addObserver(self, selector: #selector(libraryChanged(_:)), name: .ITLibraryDidChange, object: nil)
        center.addObserver(self, selector: #selector(libraryChanged(_:)), name: NSNotification.Name("com.apple.iTunes.libraryChanged"), object: nil)
    }

    @objc func sourceSaved(_ notification: Notification) {
        os_log("%{public}s[%{public}ld], %{public}s: sourceSaved", ((#file as NSString).lastPathComponent), #line, #function)
        playInfoChanged(notification)
    }

    /// In the 2026-09-21 deletion tests, Apple's documented `ITLibraryDidChange`
    /// (`com.apple.AMPLibraryAgent.libraryChanged`) preceded the legacy iTunes notification
    /// by about ten seconds. Observe both: neither identifies the song or guarantees one
    /// event per edit. The documented signal carries media domains; the legacy one is empty.
    ///
    /// Re-reading replaces `PlayingTrack`, so deleted library copies stop supplying stars
    /// and a song still playing from the catalog can show the add button. The legacy signal
    /// remains a fallback if Music's state has not settled when the earlier signal arrives.
    /// This is event-driven; it does not poll Music for library changes.
    ///
    /// Deliberately not routed through `playInfoChanged` the way `sourceSaved` is. That path
    /// decodes the payload into a `PlayInfo`, and an empty payload only survives it by
    /// decoding to a state of "unknown". The last real `playerInfo` still describes what is
    /// playing, and nothing here has any reason to disturb it.
    @objc func libraryChanged(_ notification: Notification) {
        os_log(.debug, "%{public}s[%{public}ld], %{public}s: %{public}s; scheduling a player refresh", ((#file as NSString).lastPathComponent), #line, #function, notification.name.rawValue)
        scheduleLibraryReread(after: iTunesRadioStation.libraryChangedReadDelay)
    }

    private func scheduleLibraryReread(after delay: TimeInterval) {
        libraryChangedTimer?.invalidate()
        // `.common` so a run loop tracking an open menu doesn't hold the read back
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.libraryChangedTimer = nil
            // Music does not yet have a held rating. Reading it now would undo the user's
            // choice on screen. Wait for the write window, then reconcile once.
            guard self.ratingWriter.heldRating == nil else {
                return self.scheduleLibraryReread(after: iTunesRadioStation.ratingSaveDelay)
            }
            self.readPlayerAgain(because: "Music's library changed")
        }
        RunLoop.main.add(timer, forMode: .common)
        libraryChangedTimer = timer
    }

    @objc func playInfoChanged(_ notification: Notification) {
        var dict: [String : Any] = [:]
        for (key, value) in notification.userInfo ?? [:] {
            guard let key = key as? String else { continue }
            switch value {
            case is Int:
                dict[key] = value as? Int ?? nil
            case is String:
                dict[key] = value as? String ?? nil
            case is Date:
                guard let date = value as? Date else { continue }
                let formatter = ISO8601DateFormatter()
                dict[key] = formatter.string(from: date)
            default:
                os_log("%{public}s[%{public}ld], %{public}s: can not decode PlayInfo at key \"%{public}s\" with value \"%s\"", ((#file as NSString).lastPathComponent), #line, #function, key, String(describing: value))
                continue
            }
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .custom { keys -> CodingKey in
                let key = keys.last!
                return AnyKey(stringValue: key.stringValue.snakeCaseKey) ?? AnyKey(stringValue: "")!
            }
            let playInfo = try decoder.decode(PlayInfo.self, from: jsonData)

            os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, playInfo.shortDescription)

            #if DEBUG
            let keys = Set(dict.keys.map { $0.snakeCaseKey })
            let labels = Mirror(reflecting: playInfo).children.compactMap { $0.label }
            let remains = keys.subtracting(labels)
            let remainsDict = dict.filter { remains.contains($0.key.snakeCaseKey) }
            if !remainsDict.isEmpty {
                os_log(.debug, "%{public}s[%{public}ld], %{public}s: remains info in dict %s not parse", ((#file as NSString).lastPathComponent), #line, #function, remainsDict.debugDescription)
            }
            #endif

            self.latestPlayInfo = playInfo

        } catch {
            // A payload this app can't decode is Music's business, not a bug to stop on:
            // keep the last known state and wait for the next notification
            os_log(.error, "%s: fail to parse playInfo with error %{public}s", #function, error.localizedDescription)
            return
        }
    }

}

extension iTunesRadioStation {

    /// setRating for current track
    ///
    /// - Parameter rating: integer in 0 ~ 100
    /// - Note: the rating goes to Music straight away. One arriving while that write is still
    ///   fresh is held and sent when the window closes, so a held-down rating shortcut doesn't
    ///   send Music a burst of Apple Events. A drag doesn't come through here repeatedly:
    ///   `RatingClickController` previews it and commits once, on release.
    /// - Parameter track: the track to rate. Nil means there is nowhere to put a rating -- a
    ///   song playing from the Apple Music catalog that isn't in the library -- and the rating
    ///   is dropped rather than sent somewhere Music refuses it.
    ///
    ///   There is deliberately no "whatever is playing" fallback. When nil meant both "no
    ///   target" and "use the default", the rating shortcuts still wrote to catalog tracks --
    ///   the bug this branch exists to fix -- and a held write could resolve the *next* song.
    ///   Callers pass `PlayingTrack.ratingTrack`, which is already the user's own copy when
    ///   the playing track cannot hold a rating.
    ///
    ///   Main thread only: `RatingWriter` checks, and so does everything else that reads the
    ///   `PlayingTrack` record.
    func setRating(_ rating: Int, on track: iTunesTrack?) {
        guard let targetTrack = track else {
            os_log("%{public}s[%{public}ld], %{public}s: nowhere to put a rating for this song, dropping it", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        // Note: latestPlayInfo could not set when App just launch without recieved playInfoChanged notification
        let name = latestPlayInfo?.name ?? targetTrack.name ?? "nil"

        // Which song the rating was chosen for comes from the same record the caller took the
        // target from, so the two cannot describe different songs. Music's notification would
        // be free but lags: the rating shortcuts refresh the record without waiting for it,
        // and a stale identity would make the next song look like this one. The writer only
        // asks when a rating is already held or this one is about to be. The read is an Apple
        // Event the first time on a record and remembered after that. The notification's
        // identity is the fallback for a record whose ID won't read; mixing the two shapes can
        // only make two ratings look like different songs, which costs an extra write and
        // never loses one.
        ratingWriter.rate(RatingWriter.Request(rating: rating, track: targetTrack, name: name, songIdentity: { [weak self] in
            iTunesPlayer.shared.playing?.persistentID ?? self?.latestPlayInfo?.songIdentity
        }))
    }

    /// Send a rating still waiting for the throttle window, now. `applicationWillTerminate`
    /// calls this so quitting inside the window doesn't lose the last rating.
    func flushHeldRatingWrite() {
        ratingWriter.flush()
    }

    /// Ask Music to store the request's rating on its track.
    ///
    /// Music can refuse: a song streamed from the Apple Music catalog isn't in the library,
    /// so there is nothing to store a rating on and the write comes back as OSStatus -54
    /// through `eventDidFail`, after this returns. See `iTunesTrack.isCatalogStream`.
    private func write(_ request: RatingWriter.Request) {
        // No fallback to whatever is playing: a held write fires up to `ratingSaveDelay`
        // later, and resolving the current track then would rate the next song -- the FIXME
        // this file used to carry.
        request.track.setRating?(request.rating)
        logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): set rating for \(request.name, privacy: .public): \(request.rating)")
    }

    /// Add the playing song to the library, so Music has somewhere to keep a rating.
    ///
    /// Only useful for a song streamed from the Apple Music catalog, which cannot be rated
    /// until it is in the library. See `iTunesTrack.isCatalogStream`.
    ///
    /// Music's add is `duplicate`, and it has to go to the library **source**: the library
    /// playlist is refused with "Can only duplicate subscription tracks to library source".
    /// Despite the scripting dictionary promising a specifier, the command answers with
    /// nothing usable, so the new song is found afterwards as the database ID that wasn't
    /// there before. Do not look it up by name: a library can hold several songs with the
    /// same title by different artists, and the wrong one would be rated.
    ///
    /// The playing track stays a URL track for the rest of the song -- it never turns into the
    /// library copy -- so the caller has to keep the track this returns and rate that instead.
    ///
    /// **The add is asynchronous.** `duplicate` returns before the song is in the library --
    /// measured at under a second, but not immediately -- so the new entry is looked for on a
    /// timer. Checking straight after the call finds nothing and is the reason this used to
    /// report that the song "did not appear in the library".
    ///
    /// - Parameter completion: the new library track, or nil if the add failed or timed out.
    ///   Called on the main thread, and never before `duplicate` has been sent. **Not called
    ///   at all** when an add is already in flight -- the press is ignored, and the completion
    ///   for the add that is running will answer for it. Calling it here would clear the
    ///   spinner while that first add is still going.
    func addCurrentTrackToLibrary(completion: @escaping (iTunesTrack?) -> Void) {
        guard addToLibraryTimer == nil else {
            // The button is still showing while the add is in flight; a second press must not
            // add the song twice
            os_log("%{public}s[%{public}ld], %{public}s: already adding a song to the library, ignoring", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }
        // A resolved copy, not the live `currentTrack` specifier: that one re-resolves on
        // every Apple Event, so a song change between the press and the send -- or during the
        // ten seconds of polling -- would add the wrong song to the user's library.
        guard let iTunes = iTunes, let track = iTunes.currentTrackCopy else {
            os_log("%{public}s[%{public}ld], %{public}s: no track to add to the library", ((#file as NSString).lastPathComponent), #line, #function)
            return completion(nil)
        }
        guard let library = librarySource(of: iTunes), let libraryPlaylist = libraryPlaylist(of: library) else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: no library source to add to", ((#file as NSString).lastPathComponent), #line, #function)
            return completion(nil)
        }

        let name = track.name ?? "nil"
        let existingIDs = databaseIDs(matching: track, in: libraryPlaylist)
        os_log("%{public}s[%{public}ld], %{public}s: adding %{public}s to the library…", ((#file as NSString).lastPathComponent), #line, #function, name)

        _ = (track as? iTunesGenericMethods)?.duplicateTo?(library as? SBObject)

        let giveUpAt = Date().addingTimeInterval(iTunesRadioStation.addToLibraryTimeout)
        addToLibraryTimer = Timer.scheduledTimer(withTimeInterval: iTunesRadioStation.addToLibraryPollInterval, repeats: true) { [weak self] timer in
            guard let self = self else { return timer.invalidate() }

            let result = LibraryAdd.result(
                before: existingIDs,
                after: self.databaseIDs(matching: track, in: libraryPlaylist)
            )

            switch result {
            case .pending:
                guard Date() >= giveUpAt else { return }
                self.finishAddToLibrary(timer)
                os_log(.error, "%{public}s[%{public}ld], %{public}s: %{public}s did not appear in the library within %{public}.0f s", ((#file as NSString).lastPathComponent), #line, #function, name, iTunesRadioStation.addToLibraryTimeout)
                completion(nil)

            case .ambiguous(let count):
                self.finishAddToLibrary(timer)
                os_log(.error, "%{public}s[%{public}ld], %{public}s: %{public}ld songs appeared at once, not rating any of them", ((#file as NSString).lastPathComponent), #line, #function, count)
                completion(nil)

            case .added(let databaseID):
                self.finishAddToLibrary(timer)
                os_log("%{public}s[%{public}ld], %{public}s: added %{public}s to the library as %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, name, databaseID)
                // Pick it out of the search results, not with `object(withID:)`, which takes a
                // track's `id` rather than its database ID and answers with a dead specifier
                completion(self.libraryMatches(for: track, in: libraryPlaylist)
                    .first(where: { $0.databaseID == databaseID }))
            }
        }
    }

    private func finishAddToLibrary(_ timer: Timer) {
        timer.invalidate()
        addToLibraryTimer = nil
    }

    /// The library's own copy of a song playing from the Apple Music catalog, if it has one.
    ///
    /// A song can be in the library and still play as a catalog track: opening the album in
    /// Apple Music plays the catalog copy, which is a separate object with its own ID and its
    /// own (unwritable) rating. Rating the library copy is what the user means, and it stops
    /// the button offering to add a song they already have.
    ///
    /// Matched on name, artist and album together. Where several copies match they are the
    /// same song, so the oldest is taken -- deterministic, and the one the user has had
    /// longest.
    ///
    /// An Apple Event. Callers go through `PlayingTrack`, which asks once per song and
    /// remembers the answer, so everything on screen agrees about which track it means.
    func libraryCopy(of track: iTunesTrack) -> iTunesTrack? {
        guard let iTunes = iTunes,
              let library = librarySource(of: iTunes),
              let libraryPlaylist = libraryPlaylist(of: library) else { return nil }

        // Keep the track the search returned. Don't look it up again by database ID:
        // `object(withID:)` matches a track's `id`, which is a different number, and answers
        // with a dead specifier that reads as empty and rates as nothing.
        return libraryMatches(for: track, in: libraryPlaylist)
            .min(by: { ($0.databaseID ?? .max) < ($1.databaseID ?? .max) })
    }

    /// The user's own library, as opposed to a shared library, an iPod or the store
    private func librarySource(of iTunes: iTunesApplication) -> iTunesSource? {
        return iTunes.sources?().first(where: { ($0 as? iTunesSource)?.kind == .library }) as? iTunesSource
    }

    private func libraryPlaylist(of source: iTunesSource) -> iTunesPlaylist? {
        return source.libraryPlaylists?().firstObject as? iTunesPlaylist
    }

    /// The library's songs that look like `track`: same name, artist and album.
    ///
    /// All three together, so the list stays short. Callers keep the tracks this returns
    /// rather than looking them up again by database ID, which does not work: see
    /// `libraryCopy(of:)`.
    private func libraryMatches(for track: iTunesTrack, in libraryPlaylist: iTunesPlaylist) -> [iTunesTrack] {
        // All three have to be readable. Coercing a failed read to "" would match library
        // songs that genuinely have blank metadata, which is a different song.
        guard let name = track.name, let artist = track.artist, let album = track.album else {
            os_log("%{public}s[%{public}ld], %{public}s: name, artist and album could not all be read, so no library copy is matched", ((#file as NSString).lastPathComponent), #line, #function)
            return []
        }
        let predicate = NSPredicate(format: "name == %@ AND artist == %@ AND album == %@", name, artist, album)
        return libraryPlaylist.tracks?().filtered(using: predicate) as? [iTunesTrack] ?? []
    }

    /// Database IDs of those songs, for spotting which one is new after an add
    private func databaseIDs(matching track: iTunesTrack, in libraryPlaylist: iTunesPlaylist) -> Set<Int> {
        return Set(libraryMatches(for: track, in: libraryPlaylist).compactMap { $0.databaseID })
    }

    func backward() {
        iTunes?.backTrack?()
    }

    func forward() {
        iTunes?.nextTrack?()
    }

    func playPause() {
        iTunes?.playpause?()
    }

}

// MARK: - Music lifecycle
extension iTunesRadioStation {

    /// Read the player again when Music launches or quits, or the Mac wakes.
    ///
    /// Music's own notifications cover playback, and a normal quit sends a Stopped one, but
    /// a crash or force quit sends nothing, and after sleep the track can have changed under
    /// a menu bar that never heard about it. Each of these costs at most one short-timeout
    /// read, and none of them sends Music anything when it isn't running.
    private func observeMusicLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(iTunesRadioStation.musicDidLaunch(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(iTunesRadioStation.musicDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(iTunesRadioStation.systemDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// True when a workspace notification is about Music
    static func isMusic(_ notification: Notification) -> Bool {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return application?.bundleIdentifier == OSVersionHelper.bundleIdentifier
    }

    @objc private func musicDidLaunch(_ notification: Notification) {
        guard iTunesRadioStation.isMusic(notification) else { return }
        // Music answers Apple Events only once it has finished launching. It will post its
        // own notification when playback starts; this read is for the menu bar's state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.readPlayerAgain(because: "Music launched")
        }
    }

    @objc private func musicDidTerminate(_ notification: Notification) {
        guard iTunesRadioStation.isMusic(notification) else { return }
        os_log("%{public}s[%{public}ld], %{public}s: Music quit, clearing the player", ((#file as NSString).lastPathComponent), #line, #function)
        // A rating still held has nowhere to go, and its timer would send an Apple Event to a
        // track whose app has quit
        ratingWriter.discard()
        // The observer runs iTunesPlayer.shared.update(), which finds Music not running
        latestPlayInfo = nil
    }

    @objc private func systemDidWake(_ notification: Notification) {
        readPlayerAgain(because: "the Mac woke")
    }

    /// Read the current track and run the usual player update, all under the short Apple
    /// Event timeout: the update's observers read Music too (the play state, the rating),
    /// and if Music is hung after wake those reads would otherwise wait the default two
    /// minutes on the main thread. When Music isn't running the update just clears the player.
    private func readPlayerAgain(because reason: String) {
        os_log("%{public}s[%{public}ld], %{public}s: reading the player again because %{public}s", ((#file as NSString).lastPathComponent), #line, #function, reason)
        let updated: Void? = MenuBarRatingControl.withShortTimeout { iTunes in
            iTunesPlayer.shared.update(iTunes.currentTrackCopy)
        }
        if updated == nil {
            iTunesPlayer.shared.update(nil)
        }
    }

}

// MARK: - SBApplicationDelegate
extension iTunesRadioStation: SBApplicationDelegate {

    /// Music refused or failed an Apple Event. Scripting Bridge reports it here, after the
    /// call that sent it has already returned, so the UI has shown the value as if it stuck.
    ///
    /// For a failed *set*, what is on screen is now wrong, so the player is read again a
    /// moment later and the stars and heart fall back to what Music has. The known case, a
    /// rating on an Apple Music catalog track (OSStatus -54), is no longer sent at all; this
    /// covers whatever else Music may refuse. It is not the "re-read straight after a write"
    /// that the project guide warns against: that one races a write that is about to succeed,
    /// and this one follows a write that has already failed.
    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        let (eventClass, eventID) = iTunesRadioStation.classAndID(of: event)
        os_log("%{public}s[%{public}ld], %{public}s: AppleEvent %{public}s/%{public}s failed with error %{public}s", ((#file as NSString).lastPathComponent), #line, #function, eventClass, eventID, error.localizedDescription)

        if eventClass == "core" && eventID == "setd" {
            // The delegate runs on whichever thread sent the event; the rest is main-thread work
            DispatchQueue.main.async { [weak self] in self?.scheduleRereadAfterRefusedWrite() }
        }
        return nil
    }

    /// Read the player again shortly, once, however many writes were refused. It goes through
    /// `readPlayerAgain`, so the read and the update's observers run under the short Apple
    /// Event timeout: a hung Music is a likely reason for the refusal, and the default
    /// timeout would hold the main thread for about two minutes.
    ///
    /// While a rating is still held the read waits for it: the read repaints the stars with
    /// Music's value, and a held rating is one Music does not have yet, so reading first
    /// would put the old stars back and nothing afterwards would correct them.
    private func scheduleRereadAfterRefusedWrite(after delay: TimeInterval = iTunesRadioStation.refusedWriteRereadDelay) {
        refusedWriteReread?.cancel()
        let reread = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.refusedWriteReread = nil
            guard self.ratingWriter.heldRating == nil else {
                return self.scheduleRereadAfterRefusedWrite(after: iTunesRadioStation.ratingSaveDelay)
            }
            self.readPlayerAgain(because: "Music refused a write")
        }
        refusedWriteReread = reread
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: reread)
    }

    /// The event class and ID (such as `core`/`setd` for a property write) as four-character
    /// codes. The descriptor type on the event itself is always `aevt`, which is why this log
    /// used to print `tvea` for every failure.
    static func classAndID(of event: UnsafePointer<AppleEvent>) -> (eventClass: String, eventID: String) {
        func attribute(_ key: AEKeyword) -> String {
            var code: DescType = 0
            var actualType: DescType = 0
            var actualSize = 0
            let status = AEGetAttributePtr(event, key, typeType, &actualType, &code, MemoryLayout<DescType>.size, &actualSize)
            guard status == noErr else { return "????" }
            return String(fourCharCode: code)
        }
        return (attribute(AEKeyword(keyEventClassAttr)), attribute(AEKeyword(keyEventIDAttr)))
    }

}

extension String {

    /// The four ASCII characters of a code such as `'setd'`
    init(fourCharCode code: FourCharCode) {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        self = String(bytes: bytes, encoding: .macOSRoman) ?? "????"
    }

    var snakeCaseKey: String {
        let joined = self.split(separator: " ").joined()
        return joined.prefix(1).lowercased() + joined.dropFirst()
    }

}

fileprivate struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
