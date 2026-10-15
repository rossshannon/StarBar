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

    /// Ask the system to open StarBar at login, or to stop. Throws when the system refuses,
    /// or when this copy of the app is not an installed one.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard isInstalledLocation(Bundle.main.bundleURL) else {
                os_log(.error, "%{public}s[%{public}ld], %{public}s: not registering %{public}s at login, it is not in an Applications folder", ((#file as NSString).lastPathComponent), #line, #function, Bundle.main.bundlePath)
                throw NotInstalledError()
            }
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
    /// Only run by an installed copy: the test host and other builds live in DerivedData or
    /// the build cache, and registering one would put that path in the user's login items.
    static func migrateLegacyHelperItem() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: legacyDefaultsKey) != nil, !isRunningTests,
              isInstalledLocation(Bundle.main.bundleURL) else { return }
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

    /// True for an app in `/Applications` or `~/Applications`.
    ///
    /// `SMAppService.mainApp` registers whichever bundle calls it, and the system keeps that
    /// path even after a newer copy is installed. A build from Xcode or `build.sh` that
    /// registers itself goes on opening at login once it is out of date: an old test host
    /// in the build cache did, while a newer release sat in /Applications. So only an
    /// installed copy may register.
    ///
    /// The app is sandboxed, so `homeDirectoryForCurrentUser` is the container; the user's
    /// real home comes from the password database.
    static func isInstalledLocation(_ bundleURL: URL, home: URL = realHomeDirectory) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        let roots = ["/Applications/", home.standardizedFileURL.appendingPathComponent("Applications").path + "/"]
        return roots.contains { path.hasPrefix($0) }
    }

    static var realHomeDirectory: URL {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }

    struct NotInstalledError: LocalizedError {
        var errorDescription: String? {
            return "Only a copy of StarBar in an Applications folder can open at login."
        }
    }

    private static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

}
