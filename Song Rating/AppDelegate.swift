//
//  AppDelegate.swift
//  Song Rating
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
                    alert.informativeText = "Music Rating needs permission to control Music. Turn it on in System Settings → Privacy & Security → Automation."
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
            let songRating5Shortcut = MASShortcut(keyCode: kVK_ANSI_5, modifierFlags: [.option, .control])
            let songRating4Shortcut = MASShortcut(keyCode: kVK_ANSI_4, modifierFlags: [.option, .control])
            let songRating3Shortcut = MASShortcut(keyCode: kVK_ANSI_3, modifierFlags: [.option, .control])
            let songRating2Shortcut = MASShortcut(keyCode: kVK_ANSI_2, modifierFlags: [.option, .control])
            let songRating1Shortcut = MASShortcut(keyCode: kVK_ANSI_1, modifierFlags: [.option, .control])
            let songRating0Shortcut = MASShortcut(keyCode: kVK_ANSI_Grave, modifierFlags: [.option, .control])

            let ratingDownShortcutData = try NSKeyedArchiver.archivedData(withRootObject: ratingDownShortcut as Any, requiringSecureCoding: false)
            let ratingUpShortcutData = try NSKeyedArchiver.archivedData(withRootObject: ratingUpShortcut as Any, requiringSecureCoding: false)
            let showOrClosePopoverShortcutData = try NSKeyedArchiver.archivedData(withRootObject: showOrClosePopoverShortcut as Any, requiringSecureCoding: false)
            let songRating5ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: songRating5Shortcut as Any, requiringSecureCoding: false)
            let songRating4ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: songRating4Shortcut as Any, requiringSecureCoding: false)
            let songRating3ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: songRating3Shortcut as Any, requiringSecureCoding: false)
            let songRating2ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: songRating2Shortcut as Any, requiringSecureCoding: false)
            let songRating1ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: songRating1Shortcut as Any, requiringSecureCoding: false)
            let songRating0ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: songRating0Shortcut as Any, requiringSecureCoding: false)
            
            UserDefaults.standard.register(defaults: [
                PreferencesViewController.ShortcutKey.songRatingDown.rawValue : ratingDownShortcutData,
                PreferencesViewController.ShortcutKey.songRatingUp.rawValue : ratingUpShortcutData,
                PreferencesViewController.ShortcutKey.showOrClosePopover.rawValue : showOrClosePopoverShortcutData,
                PreferencesViewController.ShortcutKey.songRating5.rawValue: songRating5ShortcutData,
                PreferencesViewController.ShortcutKey.songRating4.rawValue: songRating4ShortcutData,
                PreferencesViewController.ShortcutKey.songRating3.rawValue: songRating3ShortcutData,
                PreferencesViewController.ShortcutKey.songRating2.rawValue: songRating2ShortcutData,
                PreferencesViewController.ShortcutKey.songRating1.rawValue: songRating1ShortcutData,
                PreferencesViewController.ShortcutKey.songRating0.rawValue: songRating0ShortcutData,
            ])
        } catch {
            os_log("%{public}s[%{public}ld], %{public}s: Default shortcut set fail", ((#file as NSString).lastPathComponent), #line, #function)
        }
        
        // register application default behavior
        UserDefaults.standard.register(defaults: [
            ApplicationKey.isFirstLaunch.rawValue : true,
            ApplicationKey.launchAtLogin.rawValue : false,
            ApplicationKey.allowHalfStar.rawValue : false
        ])
        
        // setup observer
        launchAtLoginObservation = UserDefaults.standard.observe(\.launchAtLogin, options: [.initial, .new]) { [weak self] defaults, change in
            os_log("%{public}s[%{public}ld], %{public}s: launchAtLoginObservation observe .launchAtLogin get newValue: %{public}s | oldValue: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, change.newValue?.description ?? "nil", change.oldValue?.description ?? "nil")
            self?.setupLaunchAtLogin()
        }
        
    }
    
    private func setupLaunchAtLogin() {
        let launcherAppId = "com.rossshannon.musicrating.helper"
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
