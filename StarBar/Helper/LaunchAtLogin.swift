//
//  LaunchAtLogin.swift
//  StarBar
//
//  Whether StarBar opens at login, through the system's login items.
//

import Foundation
import ServiceManagement
import os

/// Registers this app bundle as a login item with `SMAppService.mainApp` (macOS 13 and
/// later). There is no helper app, no `LoginItems` folder inside the bundle and no
/// launcher to tell to quit, which is what the old `SMLoginItemSetEnabled` route needed.
///
/// The system is the source of truth: the user can turn the item off in System Settings
/// at any time, so nothing is stored in UserDefaults and `isEnabled` asks the system.
enum LaunchAtLogin {

    /// True when the system will open StarBar at login
    static var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }

    /// True when the user has to allow the item in System Settings before it takes effect.
    /// This happens after they turned it off there themselves.
    static var needsApproval: Bool {
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// Ask the system to open StarBar at login, or to stop. Throws when the system refuses.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        os_log("%{public}s[%{public}ld], %{public}s: launch at login %{public}s, status now %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, enabled ? "on" : "off", SMAppService.mainApp.status.rawValue)
    }

    /// Show the Login Items pane, for when the item needs the user's approval
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

}
