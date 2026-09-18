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

    /// When a chosen rating is sent to Music: the first goes at once, the rest wait.
    /// The writer decides when; `write(_:)` below is what it performs.
    private lazy var ratingWriter = RatingWriter(interval: iTunesRadioStation.ratingSaveDelay) { [unowned self] request in
        self.write(request)
    }

    /// The longest `setRating(_:)` can hold a rating before saving it to Music.
    ///
    /// A rating usually goes out at once. Only one arriving while a previous write is still
    /// fresh waits, and never longer than this, so it stays the upper bound anything
    /// downstream has to allow for.
    static let ratingSaveDelay: TimeInterval = 2.0

    /// How long after Music refuses a write the player is read again, so the stars fall back
    /// to what Music has. Long enough for Music to have settled after the refusal, short
    /// enough that the wrong stars are not on screen for long.
    static let refusedWriteRereadDelay: TimeInterval = 0.5
    /// The re-read scheduled after a refused write, so several refusals mean one read
    private var refusedWriteReread: DispatchWorkItem?

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

        // Note: latestPlayInfo could not set when App just launch without recieved playInfoChanged notification.
        // The track is already resolved, so its name costs no further round trip to Music.
        let name = latestPlayInfo?.name ?? targetTrack?.name ?? "nil"

        // The notification's ID says which song the rating was chosen for, at no Apple Event
        ratingWriter.rate(RatingWriter.Request(rating: rating, track: targetTrack, identity: latestPlayInfo?.persistentID, name: name))
    }

    /// Send a rating still waiting for the throttle window, now. `applicationWillTerminate`
    /// calls this so quitting inside the window doesn't lose the last rating.
    func flushHeldRatingWrite() {
        ratingWriter.flush()
    }

    /// Ask Music to store the rating on the request's track, falling back to whatever is
    /// playing.
    ///
    /// Music can refuse: a song streamed from the Apple Music catalog isn't in the library,
    /// so there is nothing to store a rating on and the write comes back as OSStatus -54
    /// through `eventDidFail`, after this returns. See `iTunesTrack.isCatalogStream`.
    private func write(_ request: RatingWriter.Request) {
        let track = request.track ?? iTunes?.currentTrack
        track?.setRating?(request.rating)
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
    /// - Returns: the new library track, or nil if the add failed
    func addCurrentTrackToLibrary() -> iTunesTrack? {
        guard let iTunes = iTunes, let track = iTunes.currentTrack else {
            os_log("%{public}s[%{public}ld], %{public}s: no track to add to the library", ((#file as NSString).lastPathComponent), #line, #function)
            return nil
        }
        guard let library = librarySource(of: iTunes), let libraryPlaylist = libraryPlaylist(of: library) else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: no library source to add to", ((#file as NSString).lastPathComponent), #line, #function)
            return nil
        }

        let name = track.name ?? "nil"
        let existingIDs = databaseIDs(matching: track, in: libraryPlaylist)
        os_log("%{public}s[%{public}ld], %{public}s: adding %{public}s to the library…", ((#file as NSString).lastPathComponent), #line, #function, name)

        _ = (track as? iTunesGenericMethods)?.duplicateTo?(library as? SBObject)

        let added = databaseIDs(matching: track, in: libraryPlaylist).subtracting(existingIDs)
        guard let databaseID = added.first else {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: %{public}s did not appear in the library after the add", ((#file as NSString).lastPathComponent), #line, #function, name)
            return nil
        }
        if added.count > 1 {
            // Two songs appearing at once shouldn't happen; rate neither rather than guess
            os_log(.error, "%{public}s[%{public}ld], %{public}s: %{public}ld songs appeared at once, not rating any of them", ((#file as NSString).lastPathComponent), #line, #function, added.count)
            return nil
        }

        os_log("%{public}s[%{public}ld], %{public}s: added %{public}s to the library as %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, name, databaseID)
        return libraryPlaylist.tracks?().object(withID: databaseID) as? iTunesTrack
    }

    /// The user's own library, as opposed to a shared library, an iPod or the store
    private func librarySource(of iTunes: iTunesApplication) -> iTunesSource? {
        return iTunes.sources?().first(where: { ($0 as? iTunesSource)?.kind == .library }) as? iTunesSource
    }

    private func libraryPlaylist(of source: iTunesSource) -> iTunesPlaylist? {
        return source.libraryPlaylists?().firstObject as? iTunesPlaylist
    }

    /// Database IDs of the library songs that look like `track`.
    ///
    /// Name, artist and album together, so the set stays small; it is only ever used to spot
    /// which ID is new, never to decide which song to rate on its own.
    private func databaseIDs(matching track: iTunesTrack, in libraryPlaylist: iTunesPlaylist) -> Set<Int> {
        guard let name = track.name else { return [] }
        let predicate = NSPredicate(format: "name == %@ AND artist == %@ AND album == %@",
                                    name, track.artist ?? "", track.album ?? "")
        guard let matches = libraryPlaylist.tracks?().filtered(using: predicate) as? [iTunesTrack] else { return [] }
        return Set(matches.compactMap { $0.databaseID })
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

    /// Music refused or failed an Apple Event. Scripting Bridge reports it here, after the
    /// call that sent it has already returned, so the UI has shown the value as if it stuck.
    ///
    /// For a failed *set*, the menu bar's stars are now wrong: it re-reads the player a
    /// moment later so they fall back to what Music has. The known case is a rating on an
    /// Apple Music catalog track (OSStatus -54); the menu bar avoids sending that one, so
    /// this covers whatever else Music may refuse.
    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        let (eventClass, eventID) = iTunesRadioStation.classAndID(of: event)
        os_log("%{public}s[%{public}ld], %{public}s: AppleEvent %{public}s/%{public}s failed with error %{public}s", ((#file as NSString).lastPathComponent), #line, #function, eventClass, eventID, error.localizedDescription)

        if eventClass == "core" && eventID == "setd" {
            DispatchQueue.main.async { [weak self] in self?.scheduleRereadAfterRefusedWrite() }
        }
        return nil
    }

    /// Read the player again shortly, once, however many writes were refused. The read and
    /// the update's observers run under the short Apple Event timeout: a hung Music is a
    /// likely reason for the refusal, and the default timeout would hold the main thread
    /// for about two minutes.
    private func scheduleRereadAfterRefusedWrite() {
        refusedWriteReread?.cancel()
        let reread = DispatchWorkItem { [weak self] in
            self?.refusedWriteReread = nil
            let updated: Void? = MenuBarRatingControl.withShortTimeout { iTunes in
                iTunesPlayer.shared.update(iTunes.currentTrackCopy)
            }
            if updated == nil {
                iTunesPlayer.shared.update(nil)
            }
        }
        refusedWriteReread = reread
        DispatchQueue.main.asyncAfter(deadline: .now() + iTunesRadioStation.refusedWriteRereadDelay, execute: reread)
    }

    /// The event class and ID (such as `core`/`setd` for a property write) as four-character
    /// codes. The descriptor type on the event itself is always `aevt`, which is why the log
    /// used to print `tvea`.
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

