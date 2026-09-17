//
//  AppDelegate.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-6-28.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa
import ServiceManagement
import os
import MASShortcut

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var menuBarRatingControl: MenuBarRatingControl?

    private var launchAtLoginObservation: NSKeyValueObservation?
    /// The Music Video strip. Kept here so it outlives the controller that shows it.
    private var trackAnnouncementPanel: TrackAnnouncementPanel?
    private var announceNewTracksObservation: NSKeyValueObservation?
    
    @IBAction func openAboutWindow(_ sender: NSMenuItem) {
        WindowManager.shared.open(.about)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // setup shortcut validator
        if let validator = MASShortcutValidator.shared() {
            validator.allowAnyShortcutWithOptionModifier = true
        } else {
            os_log("%{public}s[%{public}ld], %{public}s: WARNING - Failed to initialize MASShortcutValidator", 
                   ((#file as NSString).lastPathComponent), #line, #function)
        }
        
        setupUserDefaults()
        // UI tests run without Music: don't connect to it (Music notifications, the current
        // track and the rating shortcuts) or ask for permission to control it
        if !MenuBarRatingControl.isUITesting {
            _ = iTunesRadioStation.shared
            setupAppleEvent()
        }

        // After the Music connection, so the track already playing is recorded, not announced,
        // and before the menu bar, whose menu targets the controller
        setupTrackAnnouncement()

        // setup menu bar
        // Create synchronously: the control only refreshes on .iTunesPlayerDidUpdated, and the
        // async update in setupAppleEvent() must find it already observing. A delayed control
        // misses that update and shows the stopped icon until the next track change.
        menuBarRatingControl = MenuBarRatingControl()
        WindowManager.shared.menuBarRatingControl = menuBarRatingControl

        // Show first-launch window if needed
        if UserDefaults.standard.bool(forKey: ApplicationKey.isFirstLaunch.rawValue) {
            UserDefaults.standard.set(false, forKey: ApplicationKey.isFirstLaunch.rawValue)
            WindowManager.shared.open(.preferences)
        }
        
        #if DEBUG
        // WindowManager.shared.open(.preferences)
        #endif
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        os_log("%{public}s[%{public}ld], %{public}s: Application will terminate", ((#file as NSString).lastPathComponent), #line, #function)
    }

}

// MARK: - Track announcement

extension AppDelegate {

    /// Create the Music Video strip and its controller, seed it with the track already
    /// playing, and connect it to player updates, the setting, the shortcut and the menus.
    private func setupTrackAnnouncement() {
        let panel = TrackAnnouncementPanel()
        let controller = TrackAnnouncementController(
            readPlayer: { AppDelegate.readAnnouncementSnapshot() },
            loadArtwork: { identity in AppDelegate.loadAnnouncementArtwork(for: identity) },
            presenter: panel,
            isEnabled: UserDefaults.standard.announceNewTracks
        )
        trackAnnouncementPanel = panel
        TrackAnnouncementController.shared = controller

        // Music sends no notification at launch, so record the current track now (one short
        // Apple Event read) rather than announce it on the next rating change
        controller.playerDidUpdate(seedOnly: true)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.playerDidUpdateForAnnouncement(_:)), name: .iTunesPlayerDidUpdated, object: nil)

        announceNewTracksObservation = UserDefaults.standard.observe(\.announceNewTracks, options: [.new]) { [weak controller] defaults, _ in
            controller?.setEnabled(defaults.announceNewTracks)
        }
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.showCurrentTrack.rawValue, toAction: { [weak controller] in
            controller?.showCurrentTrack()
        })
    }

    @objc private func playerDidUpdateForAnnouncement(_ notification: Notification) {
        TrackAnnouncementController.shared?.playerDidUpdate()
    }

    /// What the player is doing, from Music's last notification. Before the first
    /// notification (the launch gap) it reads the current track once instead. Nil when Music
    /// isn't running, and always nil in UI-test mode, which never touches Music.
    static func readAnnouncementSnapshot() -> TrackAnnouncementController.PlayerSnapshot? {
        guard !MenuBarRatingControl.isUITesting, iTunesRadioStation.shared.iTunes != nil else { return nil }
        if let playInfo = iTunesRadioStation.shared.latestPlayInfo {
            return TrackAnnouncementController.PlayerSnapshot(playInfo: playInfo)
        }
        return MenuBarRatingControl.withShortTimeout { iTunes -> TrackAnnouncementController.PlayerSnapshot? in
            guard let track = iTunesPlayer.shared.currentTrack else { return nil }
            do {
                return try ExceptionCatcher.catchException {
                    TrackAnnouncementController.PlayerSnapshot(track: track, playerState: iTunes.playerState)
                } as? TrackAnnouncementController.PlayerSnapshot
            } catch {
                os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
                return nil
            }
        } ?? nil
    }

    /// The current track's artwork, if the current track is still the one being announced.
    /// The announcement's text comes from a queued notification while the artwork comes from
    /// the live track, so during rapid skips they can disagree; then a newer notification is
    /// on its way and this announcement is dropped.
    static func loadAnnouncementArtwork(for identity: String) -> TrackAnnouncementController.ArtworkLoad {
        guard !MenuBarRatingControl.isUITesting else { return .loaded(nil) }
        return MenuBarRatingControl.withShortTimeout { _ -> TrackAnnouncementController.ArtworkLoad in
            guard let track = iTunesPlayer.shared.currentTrack else { return .loaded(nil) }
            if TrackAnnouncementController.PlayerSnapshot.isPersistentID(identity),
               let liveID = track.persistentID, !liveID.isEmpty, liveID.uppercased() != identity {
                return .trackChanged
            }
            return .loaded(track.firstArtworkImage())
        } ?? .loaded(nil)
    }

}

extension AppDelegate {

    // Request AppleEvent permission
    func setupAppleEvent() {
        DispatchQueue.global().async {
            // Check if Music/iTunes is running
            let isRunning = NSWorkspace.shared.runningApplications.contains { 
                $0.bundleIdentifier == OSVersionHelper.bundleIdentifier 
            }
            
            if !isRunning {
                os_log("%{public}s[%{public}ld], %{public}s: iTunes/Music is not currently running", ((#file as NSString).lastPathComponent), #line, #function)
                return
            }
            
            let target = NSAppleEventDescriptor(bundleIdentifier: OSVersionHelper.bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            
            DispatchQueue.main.async {
                switch status {
                case noErr:
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: noErr", ((#file as NSString).lastPathComponent), #line, #function)
                    iTunesPlayer.shared.update()
                    
                case OSStatus(procNotFound):
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: iTunes/Music not running", ((#file as NSString).lastPathComponent), #line, #function)
                    
                case OSStatus(errAEEventNotPermitted):
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: not permitted", ((#file as NSString).lastPathComponent), #line, #function)
                    
                    // Explain once; after that, only log, so a denied permission doesn't nag at every login
                    let shownKey = "hasShownAutomationPermissionAlert"
                    guard !UserDefaults.standard.bool(forKey: shownKey) else { break }
                    UserDefaults.standard.set(true, forKey: shownKey)

                    let alert = NSAlert()
                    alert.messageText = "Permission Required"
                    alert.informativeText = "StarBar needs permission to control Music. Turn it on in System Settings → Privacy & Security → Automation."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open System Settings")
                    alert.addButton(withTitle: "Later")

                    // Menu bar apps have no Dock icon, so bring the alert to the front
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn,
                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                    
                default:
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: %s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: status))
                }
            }
        }   // end DispatchQueue.global().async
    }
    
    func setupUserDefaults() {
        // register shortcut
        do {
            let ratingDownShortcut = MASShortcut(keyCode: kVK_ANSI_Comma, modifierFlags: [.option, .control])
            let ratingUpShortcut = MASShortcut(keyCode: kVK_ANSI_Period, modifierFlags: [.option, .control])
            let showOrClosePopoverShortcut = MASShortcut(keyCode: kVK_ANSI_Slash, modifierFlags: [.option, .control])
            let rating5Shortcut = MASShortcut(keyCode: kVK_ANSI_5, modifierFlags: [.option, .control])
            let rating4Shortcut = MASShortcut(keyCode: kVK_ANSI_4, modifierFlags: [.option, .control])
            let rating3Shortcut = MASShortcut(keyCode: kVK_ANSI_3, modifierFlags: [.option, .control])
            let rating2Shortcut = MASShortcut(keyCode: kVK_ANSI_2, modifierFlags: [.option, .control])
            let rating1Shortcut = MASShortcut(keyCode: kVK_ANSI_1, modifierFlags: [.option, .control])
            let rating0Shortcut = MASShortcut(keyCode: kVK_ANSI_Grave, modifierFlags: [.option, .control])
            let showCurrentTrackShortcut = MASShortcut(keyCode: kVK_ANSI_N, modifierFlags: [.option, .control])

            let ratingDownShortcutData = try NSKeyedArchiver.archivedData(withRootObject: ratingDownShortcut as Any, requiringSecureCoding: false)
            let ratingUpShortcutData = try NSKeyedArchiver.archivedData(withRootObject: ratingUpShortcut as Any, requiringSecureCoding: false)
            let showOrClosePopoverShortcutData = try NSKeyedArchiver.archivedData(withRootObject: showOrClosePopoverShortcut as Any, requiringSecureCoding: false)
            let rating5ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating5Shortcut as Any, requiringSecureCoding: false)
            let rating4ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating4Shortcut as Any, requiringSecureCoding: false)
            let rating3ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating3Shortcut as Any, requiringSecureCoding: false)
            let rating2ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating2Shortcut as Any, requiringSecureCoding: false)
            let rating1ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating1Shortcut as Any, requiringSecureCoding: false)
            let rating0ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating0Shortcut as Any, requiringSecureCoding: false)
            let showCurrentTrackShortcutData = try NSKeyedArchiver.archivedData(withRootObject: showCurrentTrackShortcut as Any, requiringSecureCoding: false)

            UserDefaults.standard.register(defaults: [
                PreferencesViewController.ShortcutKey.ratingDown.rawValue : ratingDownShortcutData,
                PreferencesViewController.ShortcutKey.ratingUp.rawValue : ratingUpShortcutData,
                PreferencesViewController.ShortcutKey.showOrClosePopover.rawValue : showOrClosePopoverShortcutData,
                PreferencesViewController.ShortcutKey.rating5.rawValue: rating5ShortcutData,
                PreferencesViewController.ShortcutKey.rating4.rawValue: rating4ShortcutData,
                PreferencesViewController.ShortcutKey.rating3.rawValue: rating3ShortcutData,
                PreferencesViewController.ShortcutKey.rating2.rawValue: rating2ShortcutData,
                PreferencesViewController.ShortcutKey.rating1.rawValue: rating1ShortcutData,
                PreferencesViewController.ShortcutKey.rating0.rawValue: rating0ShortcutData,
                PreferencesViewController.ShortcutKey.showCurrentTrack.rawValue: showCurrentTrackShortcutData,
            ])
        } catch {
            os_log("%{public}s[%{public}ld], %{public}s: Default shortcut set fail", ((#file as NSString).lastPathComponent), #line, #function)
        }
        
        // register application default behavior
        UserDefaults.standard.register(defaults: [
            ApplicationKey.isFirstLaunch.rawValue : true,
            ApplicationKey.launchAtLogin.rawValue : false,
            ApplicationKey.allowHalfStar.rawValue : false,
            ApplicationKey.remindToRateUnrated.rawValue : true,
            ApplicationKey.announceNewTracks.rawValue : false
        ])
        
        // setup observer
        launchAtLoginObservation = UserDefaults.standard.observe(\.launchAtLogin, options: [.initial, .new]) { [weak self] defaults, change in
            os_log("%{public}s[%{public}ld], %{public}s: launchAtLoginObservation observe .launchAtLogin get newValue: %{public}s | oldValue: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, change.newValue?.description ?? "nil", change.oldValue?.description ?? "nil")
            self?.setupLaunchAtLogin()
        }
        
    }
    
    private func setupLaunchAtLogin() {
        let launcherAppId = "com.rossshannon.starbar.helper"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = runningApps.contains(where: { $0.bundleIdentifier == launcherAppId })
        
        let shouldLaunchAtLogin = UserDefaults.standard.launchAtLogin
        SMLoginItemSetEnabled(launcherAppId as CFString, shouldLaunchAtLogin)
        os_log("%{public}s[%{public}ld], %{public}s: set launchAtLogin to %{public}s", ((#file as NSString).lastPathComponent), #line, #function, shouldLaunchAtLogin.description)

        if isRunning {
            DistributedNotificationCenter.default().post(name: .killLauncher, object: Bundle.main.bundleIdentifier)
        }
        
    }
}
