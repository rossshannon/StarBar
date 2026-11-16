//
//  BuildInfo.swift
//  StarBar
//
//  Which build of StarBar is running, and what it was built from.
//

import Foundation

/// Which build of StarBar is running: StarBar itself or StarBar Dev, and, for a build that
/// isn't a release, the branch and commit it was made from, so that the About window and the
/// log can say which build is on the Mac.
///
/// StarBar Dev (`./build.sh --dev`) is the same code under another bundle identifier, name and
/// icon, so that a pull request's build can be installed beside the everyday StarBar rather
/// than over it. The bundle identifier is what says which one this is: it also gives each its
/// own sandbox container, and so its own settings and its own Spotify and Last.fm sign-ins.
///
/// The source comes from `Info.plist`, which `build.sh` fills from git through build settings:
/// `StarBarSourceBranch`, `StarBarSourceCommit`, `StarBarSourceModified` (`YES` when tracked
/// files had changes not yet committed) and `StarBarBuildDate` (ISO 8601). All four are empty
/// for a release, which is a build of a commit at a `v*` tag with nothing uncommitted, and for
/// a build from Xcode, which `build.sh` doesn't make.
struct BuildInfo: Equatable {

    enum Variant: String {
        /// StarBar, as released
        case standard
        /// StarBar Dev, built with `./build.sh --dev`
        case dev
    }

    static let standardBundleIdentifier = "com.rossshannon.starbar"
    static let devBundleIdentifier = "com.rossshannon.starbar.dev"

    /// The `Info.plist` keys `build.sh` fills
    static let branchKey = "StarBarSourceBranch"
    static let commitKey = "StarBarSourceCommit"
    static let modifiedKey = "StarBarSourceModified"
    static let buildDateKey = "StarBarBuildDate"

    let variant: Variant
    /// The app's name as the system shows it: "StarBar" or "StarBar Dev"
    let name: String
    let version: String
    let build: String
    /// The branch the build was made from; nil for a release, a build from Xcode, or a
    /// detached checkout
    let branch: String?
    /// The commit, abbreviated; nil for a release or a build from Xcode
    let commit: String?
    /// True when tracked files had changes not yet committed
    let hasUncommittedChanges: Bool
    let buildDate: Date?

    /// The running app's
    static let current = BuildInfo(bundleIdentifier: Bundle.main.bundleIdentifier, info: Bundle.main.infoDictionary ?? [:])

    init(bundleIdentifier: String?, info: [String: Any]) {
        let variant: Variant = bundleIdentifier == BuildInfo.devBundleIdentifier ? .dev : .standard
        func value(_ key: String) -> String? {
            guard let string = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
            return string
        }
        self.variant = variant
        name = value("CFBundleName") ?? (variant == .dev ? "StarBar Dev" : "StarBar")
        version = value("CFBundleShortVersionString") ?? "NA"
        build = value("CFBundleVersion") ?? "NA"
        branch = value(BuildInfo.branchKey)
        commit = value(BuildInfo.commitKey)
        hasUncommittedChanges = value(BuildInfo.modifiedKey).map { ["yes", "true", "1"].contains($0.lowercased()) } ?? false
        buildDate = value(BuildInfo.buildDateKey).flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    var isDev: Bool {
        return variant == .dev
    }

    /// The bundle identifier of the other variant: StarBar Dev's for StarBar, and StarBar's for
    /// StarBar Dev. Only one of the two runs at a time (`VariantHandover`).
    var otherVariantBundleIdentifier: String {
        return isDev ? BuildInfo.standardBundleIdentifier : BuildInfo.devBundleIdentifier
    }

    /// True when the build says where it came from, which a release doesn't
    var hasSource: Bool {
        return commit != nil
    }

    /// What the About window shows under the version, one line each, such as
    /// ["main", "8c978ba + changes, 16 Nov at 21:40"]; empty for a release or a build from Xcode.
    func sourceLines(timeZone: TimeZone = .current, locale: Locale = .current) -> [String] {
        guard let commit = commit else { return [] }
        var detail = commit
        if hasUncommittedChanges {
            detail += " + changes"
        }
        if let buildDate = buildDate {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate("dMMMjjmm")
            detail += ", built " + formatter.string(from: buildDate)
        }
        return [branch, detail].compactMap { $0 }
    }

    /// One line for the log at launch, such as "StarBar Dev 1.10.0 (472) from main at 8c978ba
    /// with uncommitted changes, built 2026-11-16T21:40:00Z", or "StarBar 1.10.0 (470)" for a
    /// release
    var logDescription: String {
        var line = "\(name) \(version) (\(build))"
        guard let commit = commit else { return line }
        line += " from " + (branch.map { "\($0) at " } ?? "") + commit
        if hasUncommittedChanges {
            line += " with uncommitted changes"
        }
        if let buildDate = buildDate {
            line += ", built " + ISO8601DateFormatter().string(from: buildDate)
        }
        return line
    }

}
