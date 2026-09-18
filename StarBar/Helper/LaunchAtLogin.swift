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

    /// The key the old implementation stored the choice under, and the helper it registered
    static let legacyDefaultsKey = "launchAtLogin"
    static let legacyHelperIdentifier = "com.rossshannon.starbar.helper"

    /// One-time move from the helper-app login item.
    ///
    /// Until the deployment target rose to 13, "Launch at login" registered a helper bundle
    /// inside the app with `SMLoginItemSetEnabled` and stored the choice in UserDefaults. The
    /// helper is no longer in the bundle, so that registration launches nothing. If the stored
    /// choice was on, this registers the app itself once, drops the old registration, and
    /// forgets the key, so the system is the only record from then on.
    ///
    /// Not run under tests: the test host is a build in DerivedData, and registering it would
    /// put that path in the user's login items.
    static func migrateLegacyHelperItem() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: legacyDefaultsKey) != nil, !isRunningTests else { return }
        let wanted = defaults.bool(forKey: legacyDefaultsKey)
        defaults.removeObject(forKey: legacyDefaultsKey)

        // launchd may still hold the helper's registration; it points at nothing now
        try? SMAppService.loginItem(identifier: legacyHelperIdentifier).unregister()

        guard wanted, SMAppService.mainApp.status == .notRegistered else {
            os_log("%{public}s[%{public}ld], %{public}s: legacy launch at login was %{public}s, status %{public}ld, nothing to migrate", ((#file as NSString).lastPathComponent), #line, #function, wanted ? "on" : "off", SMAppService.mainApp.status.rawValue)
            return
        }
        do {
            try SMAppService.mainApp.register()
            os_log("%{public}s[%{public}ld], %{public}s: migrated launch at login from the helper to the app, status now %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, SMAppService.mainApp.status.rawValue)
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: could not migrate launch at login: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
        }
    }

    private static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

}
