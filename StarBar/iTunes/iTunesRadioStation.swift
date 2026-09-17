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
    func setRating(_ rating: Int) {
        guard latestPlayInfo != nil || !(iTunes?.currentTrack?.name ?? "").isEmpty else {
            os_log("%{public}s[%{public}ld], %{public}s: try to set rating but no current track info", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        // Hold on to the track the user was looking at. A write that lands later must rate
        // that track, not whatever has started playing by then.
        let targetTrack = iTunes?.currentTrack?.copy()

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

