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

    private var debounceSetRatingTimer: Timer?

    /// How long `setRating(_:)` waits before it saves the rating to Music
    static let ratingSaveDelay: TimeInterval = 2.0

    private init() {
        // Listen iTunes play state change notification
        // Note: The notification name on Catalina is same as Mojave
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(iTunesRadioStation.playInfoChanged(_:)), name: NSNotification.Name("com.apple.iTunes.playerInfo"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(iTunesRadioStation.sourceSaved(_:)), name: NSNotification.Name("com.apple.iTunes.sourceSaved"), object: nil)  // only set rating in iTunes edit song info panel can trigger that

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
    /// - Note: call track.setRating with debounce. Prevent apple event trigger jumping bug
    func setRating(_ rating: Int) {
        debounceSetRatingTimer?.invalidate()

        guard latestPlayInfo != nil || !(iTunes?.currentTrack?.name ?? "").isEmpty else {
            os_log("%{public}s[%{public}ld], %{public}s: try to set rating but no current track info", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        // save the record for later rating
        let targetTrack = iTunes?.currentTrack?.copy()

        // Note: latestPlayInfo could not set when App just launch without recieved playInfoChanged notification
        let name = latestPlayInfo?.name ?? iTunes?.currentTrack?.name ?? "nil"
        os_log("%{public}s[%{public}ld], %{public}s: set timer for 2.0s and set rating for %{public}s %{public}ld…", ((#file as NSString).lastPathComponent), #line, #function, name, rating)

        // FIXME: delay may cause set rating to *next* song just playing
        debounceSetRatingTimer = Timer(timeInterval: iTunesRadioStation.ratingSaveDelay, repeats: false, block: { [weak self] timer in
            guard let `self` = self else { return }
            // here we use the saved record
            // so the delay will not rate the next track if song just finish (a.k.a rate in last 2s)
            let track = targetTrack ?? self.iTunes?.currentTrack

            track?.setRating?(rating)
            logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): set rating for \(track?.name ?? "<nil>"): \(rating)")
        })
        debounceSetRatingTimer.flatMap {
            RunLoop.current.add($0, forMode: .default)
        }
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
        // The observer runs iTunesPlayer.shared.update(), which finds Music not running
        latestPlayInfo = nil
    }

    @objc private func systemDidWake(_ notification: Notification) {
        readPlayerAgain(because: "the Mac woke")
    }

    /// One short-timeout read of the current track, then the usual player update
    private func readPlayerAgain(because reason: String) {
        os_log("%{public}s[%{public}ld], %{public}s: reading the player again because %{public}s", ((#file as NSString).lastPathComponent), #line, #function, reason)
        let track = MenuBarRatingControl.withShortTimeout { $0.currentTrackCopy } ?? nil
        iTunesPlayer.shared.update(track)
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

