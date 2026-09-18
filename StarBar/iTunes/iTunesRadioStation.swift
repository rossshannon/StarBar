//
//  iTunesRadioStation.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-6-28.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation
import ScriptingBridge
import os
import MASShortcut

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

    /// When a chosen rating is sent to Music: the first goes at once, the rest wait
    private var ratingWriteThrottle = RatingWriteThrottle(interval: iTunesRadioStation.ratingSaveDelay)
    /// The newest rating waiting for the throttle window to close, with the track it belongs to
    private var heldRatingWrite: (rating: Int, track: iTunesTrack?, name: String)?
    private var heldRatingWriteTimer: Timer?

    /// The longest `setRating(_:)` can hold a rating before saving it to Music.
    ///
    /// A rating usually goes out at once. Only one arriving while a previous write is still
    /// fresh waits, and never longer than this, so it stays the upper bound anything
    /// downstream has to allow for.
    static let ratingSaveDelay: TimeInterval = 2.0

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

        // Due to iTunes may already playing before app launch,update player when app start
        iTunesPlayer.shared.update(iTunes?.currentTrackCopy)

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

    @objc func sourceSaved(_ notification: Notification) {
        os_log("%{public}s[%{public}ld], %{public}s: sourceSaved", ((#file as NSString).lastPathComponent), #line, #function)
        playInfoChanged(notification)
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
                guard let date = value as? Date else { return }
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
            os_log(.error, "%s: fail to parse playInfo with error %{public}s", #function, error.localizedDescription)
            assertionFailure(error.localizedDescription)
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
    /// - Parameter track: the track to rate, or nil for whatever is playing. The menu bar
    ///   passes the library copy of a song just added with the Apple Music button, because the
    ///   playing track stays a catalog track that Music will not store a rating on.
    func setRating(_ rating: Int, on track: iTunesTrack? = nil) {
        guard track != nil || latestPlayInfo != nil || !(iTunes?.currentTrack?.name ?? "").isEmpty else {
            os_log("%{public}s[%{public}ld], %{public}s: try to set rating but no current track info", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        // Hold on to the track the user was looking at. A write that lands later must rate
        // that track, not whatever has started playing by then.
        let targetTrack = track ?? iTunes?.currentTrack?.copy()

        // Note: latestPlayInfo could not set when App just launch without recieved playInfoChanged notification
        let name = latestPlayInfo?.name ?? iTunes?.currentTrack?.name ?? "nil"

        switch ratingWriteThrottle.decide(at: Date()) {
        case .now:
            // Supersede anything still waiting: this rating is newer
            heldRatingWrite = nil
            heldRatingWriteTimer?.invalidate()
            heldRatingWriteTimer = nil
            os_log("%{public}s[%{public}ld], %{public}s: set rating for %{public}s %{public}ld…", ((#file as NSString).lastPathComponent), #line, #function, name, rating)
            write(rating: rating, to: targetTrack, name: name)

        case .hold(let until):
            // Keep only the newest rating. The timer is already counting to the same moment,
            // so holding a shortcut down must not push the write further away each press.
            heldRatingWrite = (rating, targetTrack, name)
            guard heldRatingWriteTimer == nil else { return }

            os_log("%{public}s[%{public}ld], %{public}s: holding rating for %{public}s %{public}ld until the window closes…", ((#file as NSString).lastPathComponent), #line, #function, name, rating)
            let timer = Timer(fire: until, interval: 0, repeats: false, block: { [weak self] _ in
                self?.sendHeldRatingWrite()
            })
            heldRatingWriteTimer = timer
            RunLoop.current.add(timer, forMode: .default)
        }
    }

    /// Send the rating that was waiting for the throttle window to close.
    private func sendHeldRatingWrite() {
        heldRatingWriteTimer = nil
        guard let held = heldRatingWrite else { return }
        heldRatingWrite = nil

        ratingWriteThrottle.didWrite(at: Date())
        write(rating: held.rating, to: held.track, name: held.name)
    }

    /// Ask Music to store `rating` on `track`, falling back to whatever is playing.
    ///
    /// Music can refuse: a song streamed from the Apple Music catalog isn't in the library,
    /// so there is nothing to store a rating on and the write comes back as OSStatus -54
    /// through `eventDidFail`, after this returns. See `iTunesTrack.isCatalogStream`.
    private func write(rating: Int, to targetTrack: iTunesTrack?, name: String) {
        let track = targetTrack ?? iTunes?.currentTrack
        track?.setRating?(rating)
        logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): set rating for \(name, privacy: .public): \(rating)")
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
    ///   Always called on the main thread, and never before `duplicate` has been sent.
    func addCurrentTrackToLibrary(completion: @escaping (iTunesTrack?) -> Void) {
        guard addToLibraryTimer == nil else {
            // The button is still showing while the add is in flight; a second press must not
            // add the song twice
            os_log("%{public}s[%{public}ld], %{public}s: already adding a song to the library, ignoring", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }
        guard let iTunes = iTunes, let track = iTunes.currentTrack else {
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
        guard let name = track.name else { return [] }
        let predicate = NSPredicate(format: "name == %@ AND artist == %@ AND album == %@",
                                    name, track.artist ?? "", track.album ?? "")
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

// MARK: - SBApplicationDelegate
extension iTunesRadioStation: SBApplicationDelegate {

    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        var appleEvent = event.pointee
        let chars = [UInt8](Data(bytes: &appleEvent.descriptorType, count: 4))
        let id = chars.map { String(format: "%c", $0) }.joined()    // appleEvent 4 char id (descType)
        os_log("%{public}s[%{public}ld], %{public}s: AppleEvent (%{public}s) call fail with error %{public}s", ((#file as NSString).lastPathComponent), #line, #function, id, error.localizedDescription)
        return nil
    }

}

extension String {

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

