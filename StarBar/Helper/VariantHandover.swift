//
//  VariantHandover.swift
//  StarBar
//
//  Only one of StarBar and StarBar Dev runs at a time: the one opened last.
//

import Cocoa
import os

/// Keeps StarBar and StarBar Dev from running together: whichever was opened last runs, and
/// the other quits.
///
/// Both would follow Music and Spotify, so two copies would show two strips, both answer the
/// rating shortcuts, and both scrobble each play once each is signed in to Last.fm. So each
/// copy watches the running apps (key-value observing `NSWorkspace.runningApplications`, which
/// lists agent apps such as StarBar, where the workspace's launch notification may not) and
/// quits through `NSApp.terminate`, which flushes a held rating, when the other variant opens
/// after it. The newcomer does nothing: it is the older copy's job to step aside.
///
/// A sandboxed app can't quit another, so a copy made before this existed (StarBar 1.10.0 and
/// earlier) never steps aside. When the other variant is still running `olderCopyWait` after
/// this one opened, this one says so once, and offers to quit itself.
///
/// Only copies in an Applications folder count (`LaunchAtLogin.isInstalledLocation`): the test
/// host is StarBar too, run from DerivedData, and a test run must not make an installed
/// StarBar Dev quit.
final class VariantHandover {

    static let shared = VariantHandover()

    /// How long the other variant has to quit after this one opens, before this one warns
    static let olderCopyWait: TimeInterval = 5

    /// What a copy of StarBar does about another running app
    enum Action: Equatable {
        /// Nothing: it isn't the other variant, or isn't an installed copy
        case ignore
        /// Quit: the other variant opened after this one
        case stepAside
        /// The other variant opened first and should quit for this one
        case waitForOther
    }

    /// The rule, on its own so tests can drive it.
    ///
    /// - Parameters:
    ///   - otherBundleIdentifier: the running app's bundle identifier
    ///   - otherBundleURL: where it runs from
    ///   - otherLaunched: when it opened; nil when the system doesn't say, which counts as now
    ///   - ownBundleIdentifier: this copy's
    ///   - ownLaunched: when this copy opened
    ///   - now: the time to count a missing launch date as
    static func action(otherBundleIdentifier: String?, otherBundleURL: URL?, otherLaunched: Date?,
                       ownBundleIdentifier: String, ownLaunched: Date, now: Date = Date(),
                       home: URL = LaunchAtLogin.realHomeDirectory) -> Action {
        let family = [BuildInfo.standardBundleIdentifier, BuildInfo.devBundleIdentifier]
        guard let other = otherBundleIdentifier, other != ownBundleIdentifier,
              family.contains(other), family.contains(ownBundleIdentifier),
              let url = otherBundleURL, LaunchAtLogin.isInstalledLocation(url, home: home) else { return .ignore }
        let opened = otherLaunched ?? now
        if opened > ownLaunched {
            return .stepAside
        }
        // Opened at the same instant: StarBar runs and StarBar Dev quits
        if opened == ownLaunched {
            return ownBundleIdentifier == BuildInfo.devBundleIdentifier ? .stepAside : .waitForOther
        }
        return .waitForOther
    }

    private var observation: NSKeyValueObservation?

    /// True once `start` has begun watching the running apps
    var isWatching: Bool {
        return observation != nil
    }
    private var ownLaunched = Date()
    private var isSteppingAside = false
    private var hasWarned = false

    private static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Start watching. Does nothing under tests or UI tests, whose app is never an installed one
    /// but whose bundle identifier is StarBar's.
    func start() {
        guard observation == nil, !VariantHandover.isRunningTests, !MenuBarRatingControl.isUITesting,
              let ownIdentifier = Bundle.main.bundleIdentifier else { return }
        ownLaunched = NSRunningApplication.current.launchDate ?? Date()

        // Each launch or quit of any app; a few dozen apps to look through, nothing more
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.check(ownIdentifier: ownIdentifier)
            }
        }
        check(ownIdentifier: ownIdentifier)

        DispatchQueue.main.asyncAfter(deadline: .now() + VariantHandover.olderCopyWait) { [weak self] in
            self?.warnIfOtherIsStillRunning(ownIdentifier: ownIdentifier)
        }
    }

    /// The other variant's installed copies that are running, each with what to do about it
    private func others(ownIdentifier: String) -> [(app: NSRunningApplication, action: Action)] {
        let now = Date()
        var others: [(app: NSRunningApplication, action: Action)] = []
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            let action = VariantHandover.action(otherBundleIdentifier: app.bundleIdentifier, otherBundleURL: app.bundleURL,
                                                otherLaunched: app.launchDate, ownBundleIdentifier: ownIdentifier,
                                                ownLaunched: ownLaunched, now: now)
            if action != .ignore {
                others.append((app: app, action: action))
            }
        }
        return others
    }

    private func check(ownIdentifier: String) {
        guard !isSteppingAside,
              let newer = others(ownIdentifier: ownIdentifier).first(where: { $0.action == .stepAside })?.app else { return }
        isSteppingAside = true
        os_log("%{public}s[%{public}ld], %{public}s: %{public}s opened after this copy, from %{public}s, so %{public}s is quitting: only one of them runs at a time", ((#file as NSString).lastPathComponent), #line, #function, newer.localizedName ?? newer.bundleIdentifier ?? "?", newer.bundleURL?.path ?? "?", BuildInfo.current.name)
        NSApp.terminate(nil)
    }

    private func warnIfOtherIsStillRunning(ownIdentifier: String) {
        guard !isSteppingAside, !hasWarned,
              let older = others(ownIdentifier: ownIdentifier).first(where: { $0.action == .waitForOther })?.app else { return }
        hasWarned = true
        let otherName = older.localizedName ?? (BuildInfo.current.isDev ? "StarBar" : "StarBar Dev")
        let ownName = BuildInfo.current.name
        os_log(.error, "%{public}s[%{public}ld], %{public}s: %{public}s is still running %.0f s after this copy opened; it is too old to step aside", ((#file as NSString).lastPathComponent), #line, #function, otherName, VariantHandover.olderCopyWait)

        let alert = NSAlert()
        alert.messageText = "\(otherName) is running too"
        alert.informativeText = "This copy of \(otherName) is from before the two took turns, so it doesn't quit when \(ownName) opens. With both running, both show the strip, both answer the rating shortcuts, and both scrobble if they're signed in to Last.fm.\n\nQuit \(otherName) from its menu to try \(ownName) on its own."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Quit \(ownName)")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            isSteppingAside = true
            NSApp.terminate(nil)
        }
    }

}
