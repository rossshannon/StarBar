//
//  PreferencesViewController.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-7-2.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa
import MASShortcut
import os

final class PreferencesViewController: NSViewController {

    static var defaultTextFieldFontSize: CGFloat {
        return NSTextField(labelWithString: "sample").font!.pointSize
    }

    lazy var showCurrentTrackTextField: NSTextField = {
        return NSTextField(labelWithString: "Show current track: ")
    }()
    lazy var announcementStyleTextField: NSTextField = {
        return NSTextField(labelWithString: "Strip style: ")
    }()
    lazy var ratingDownTextField: NSTextField = {
        return NSTextField(labelWithString: "Rating down: ")
    }()
    lazy var ratingUpTextField: NSTextField = {
        return NSTextField(labelWithString: "Rating up: ")
    }()
    lazy var showOrClosePopoverTextField: NSTextField = {
        return NSTextField(labelWithString: "Show/Close popover: ")
    }()
    lazy var rating5TextField: NSStackView = {
        return PreferencesViewController.starsLabel(count: 5, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating4TextField: NSStackView = {
        return PreferencesViewController.starsLabel(count: 4, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating3TextField: NSStackView = {
        return PreferencesViewController.starsLabel(count: 3, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating2TextField: NSStackView = {
        return PreferencesViewController.starsLabel(count: 2, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating1TextField: NSStackView = {
        return PreferencesViewController.starsLabel(count: 1, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating0TextField: NSTextField = {
        return NSTextField(labelWithString: "Remove stars: ")
    }()

    let launchAtLoginCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
        return button
    }()
    let halfStarCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Allow half stars", target: nil, action: nil)
        return button
    }()
    let reminderCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Remind me to rate unrated songs", target: nil, action: nil)
        return button
    }()
    let announceCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Show a Music Video strip when a new song plays", target: nil, action: nil)
        return button
    }()
    let announcePreviewButton: NSButton = {
        let button = NSButton(title: "Preview", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        return button
    }()
    /// The announce checkbox and its Preview button, side by side in one grid cell
    lazy var announceRowView: NSStackView = {
        let stack = NSStackView(views: [announceCheckboxButton, announcePreviewButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }()
    let announcementStylePopUpButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        for style in TrackAnnouncementStyle.allCases {
            button.addItem(withTitle: style.title)
            button.lastItem?.representedObject = style.rawValue
        }
        return button
    }()
    let showCurrentTrackShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.showCurrentTrack.rawValue
        return shortcutView
    }()
    let ratingDownShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.ratingDown.rawValue
        return shortcutView
    }()
    let ratingUpShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.ratingUp.rawValue
        return shortcutView
    }()
    let showOrClosePopoverShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.showOrClosePopover.rawValue
        return shortcutView
    }()
    let rating5ShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.rating5.rawValue
        return shortcutView
    }()
    let rating4ShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.rating4.rawValue
        return shortcutView
    }()
    let rating3ShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.rating3.rawValue
        return shortcutView
    }()
    let rating2ShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.rating2.rawValue
        return shortcutView
    }()
    let rating1ShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.rating1.rawValue
        return shortcutView
    }()
    let rating0ShortcutView: MASShortcutView = {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = ShortcutKey.rating0.rawValue
        return shortcutView
    }()

    lazy var spotifyTextField: NSTextField = {
        return NSTextField(labelWithString: "Spotify: ")
    }()
    let spotifyConnectButton: NSButton = {
        return NSButton(title: "Connect", target: nil, action: nil)
    }()
    /// What connecting does, or how the sign-in stands
    let spotifyStatusTextField: NSTextField = {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 300
        return field
    }()

    lazy var lastfmTextField: NSTextField = {
        return NSTextField(labelWithString: "Last.fm: ")
    }()
    let lastfmConnectButton: NSButton = {
        return NSButton(title: "Connect", target: nil, action: nil)
    }()
    /// What connecting does, or how the sign-in and the scrobbling stand
    let lastfmStatusTextField: NSTextField = {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 300
        return field
    }()
    let lastfmSpotifyCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Scrobble songs played in Spotify", target: nil, action: nil)
        // Last.fm's own Spotify link scrobbles on its servers, so both would count each play twice
        button.toolTip = "Leave this off if Spotify is connected to Last.fm in your Last.fm settings, or every Spotify song is scrobbled twice."
        return button
    }()
    let lastfmLoveCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Love songs on Last.fm when I favourite them", target: nil, action: nil)
        return button
    }()

    let leadingPaddingView = NSView()
    let trailingPaddingView = NSView()

    lazy var gridView: NSGridView = {
        let empty = NSGridCell.emptyContentView

        let gridView = NSGridView(views: [
            // The checkboxes say what they do, so their rows need no label
            [empty, launchAtLoginCheckboxButton],
            [empty, halfStarCheckboxButton],
            [empty, reminderCheckboxButton],
            [empty, announceRowView],
            [announcementStyleTextField, announcementStylePopUpButton],
            [NSBox.separatorLine],
            [spotifyTextField, spotifyConnectButton],
            [empty, spotifyStatusTextField],
            [lastfmTextField, lastfmConnectButton],
            [empty, lastfmStatusTextField],
            [empty, lastfmSpotifyCheckboxButton],
            [empty, lastfmLoveCheckboxButton],
            [NSBox.separatorLine],
            [ratingDownTextField, ratingDownShortcutView],
            [ratingUpTextField, ratingUpShortcutView],
            [showOrClosePopoverTextField, showOrClosePopoverShortcutView],
            [showCurrentTrackTextField, showCurrentTrackShortcutView],
            [NSBox.separatorLine],
            // Most stars first, the way a rating reads from best to worst
            [rating5TextField, rating5ShortcutView],
            [rating4TextField, rating4ShortcutView],
            [rating3TextField, rating3ShortcutView],
            [rating2TextField, rating2ShortcutView],
            [rating1TextField, rating1ShortcutView],
            [rating0TextField, rating0ShortcutView],
            [leadingPaddingView, trailingPaddingView]
        ])

        gridView.row(at: 0).rowAlignment = .lastBaseline
        // A label beside a pop-up or a push button sits on the control's text, not its top
        for label in [announcementStyleTextField, spotifyTextField, lastfmTextField] {
            gridView.cell(for: label)?.row?.rowAlignment = .firstBaseline
        }

        gridView.column(at: 0).xPlacement = .trailing
        gridView.column(at: 1).xPlacement = .leading
        gridView.rowSpacing = 8

        let lines = gridView.subviews.filter { ($0 as? NSBox)?.boxType == .separator }
        for line in lines {
            guard let lineRow = gridView.cell(for: line)?.row else {
                continue
            }
            lineRow.mergeCells(in: NSMakeRange(0, 2))
            lineRow.topPadding = 8
            lineRow.bottomPadding = 8
        }

        return gridView
    }()

    var halfStarObservation: NSKeyValueObservation?
    var reminderObservation: NSKeyValueObservation?
    var announceObservation: NSKeyValueObservation?
    var announcementStyleObservation: NSKeyValueObservation?
    var lastfmSpotifyObservation: NSKeyValueObservation?
    var lastfmLoveObservation: NSKeyValueObservation?

    override func loadView() {
        self.view = NSView()
    }

    deinit {
        halfStarObservation?.invalidate()
        reminderObservation?.invalidate()
        announceObservation?.invalidate()
        announcementStyleObservation?.invalidate()
        lastfmSpotifyObservation?.invalidate()
        lastfmLoveObservation?.invalidate()
    }

}

extension PreferencesViewController {

    /// A row label of `count` stars followed by a colon, for the rating shortcuts.
    ///
    /// The stars are a template image in an image view tinted with the label colour, so
    /// they follow light and dark mode like the text beside them. An image baked with the
    /// label colour at creation time (the earlier text-attachment approach) kept the colour
    /// of whichever appearance the window opened in.
    static func starsLabel(count: Int, fontSize: CGFloat) -> NSStackView {
        let stars = Stars(
            stars: Array(repeating: Star(size: CGSize(width: fontSize, height: fontSize), style: .full), count: count),
            spacing: 3
        )
        let image = stars.image
        image.isTemplate = true

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = .labelColor
        imageView.setAccessibilityLabel(RatingControl.accessibilityDescription(rating: 20 * count, isFavorited: false))

        // The trailing space matches the text labels, so the gap to the recorder is the same
        let colon = NSTextField(labelWithString: ": ")
        let stack = NSStackView(views: [imageView, colon])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        return stack
    }
}

extension PreferencesViewController {

    @objc private func launchAtLoginCheckboxButtonChanged(_ sender: NSButton) {
        let wantsLaunchAtLogin = sender.state == .on
        do {
            try LaunchAtLogin.setEnabled(wantsLaunchAtLogin)
        } catch {
            os_log(.error, "%{public}s[%{public}ld], %{public}s: launch at login could not be changed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
        }
        if wantsLaunchAtLogin, LaunchAtLogin.needsApproval {
            // The user switched StarBar off in System Settings earlier; only they can switch it back on there
            LaunchAtLogin.openSystemSettings()
        }
        refreshLaunchAtLogin()
    }

    /// The checkbox shows what the system will do, not what was last asked for
    private func refreshLaunchAtLogin() {
        launchAtLoginCheckboxButton.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        // Back from System Settings, where the item may have been switched
        refreshLaunchAtLogin()
        refreshLastfm()
    }

    @objc private func halfStarCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.allowHalfStar = sender.state == .on
    }

    @objc private func reminderCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.remindToRateUnrated = sender.state == .on
    }

    @objc private func announceCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.announceNewTracks = sender.state == .on
    }

    @objc private func announcePreviewButtonPressed(_ sender: NSButton) {
        TrackAnnouncementController.shared?.preview()
    }

    @objc private func announcementStyleChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        UserDefaults.standard.announcementStyle = rawValue
    }

    @objc private func spotifyConnectButtonPressed(_ sender: NSButton) {
        let account = SpotifyAccount.shared
        if account.state == .connected {
            account.disconnect()
        } else {
            account.connect(presentingFrom: view.window)
        }
    }

    @objc private func spotifyAccountDidChange(_ notification: Notification) {
        refreshSpotify()
    }

    /// The button and the text under it follow the sign-in
    func refreshSpotify() {
        let account = SpotifyAccount.shared
        spotifyConnectButton.title = account.state == .connected ? "Disconnect" : "Connect"
        spotifyConnectButton.isEnabled = account.state != .connecting
        spotifyStatusTextField.stringValue = PreferencesViewController.spotifyStatus(state: account.state, problem: account.lastProblem)
    }

    /// What the text under the Connect button says
    static func spotifyStatus(state: SpotifyAccount.State, problem: String?) -> String {
        let status: String
        switch state {
        case .connected:
            status = "Connected. Click the green heart in the menu bar to like or unlike the Spotify song playing."
        case .connecting:
            status = "Waiting for Spotify's sign-in…"
        case .disconnected:
            status = "Connect your Spotify account to like songs with the menu bar's green heart."
        }
        guard let problem = problem else { return status }
        return problem + " " + status
    }

    @objc private func lastfmConnectButtonPressed(_ sender: NSButton) {
        let account = LastfmAccount.shared
        if account.state == .connected {
            account.disconnect()
        } else {
            account.connect(presentingFrom: view.window)
        }
    }

    @objc private func lastfmSpotifyCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.lastfmScrobbleSpotify = sender.state == .on
    }

    @objc private func lastfmLoveCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.lastfmLoveSync = sender.state == .on
    }

    @objc private func lastfmDidChange(_ notification: Notification) {
        refreshLastfm()
    }

    /// The button, the text under it and the two settings follow the sign-in, the pause and
    /// what is waiting to be sent
    func refreshLastfm() {
        let account = LastfmAccount.shared
        let defaults = UserDefaults.standard
        let isConnected = account.state == .connected
        lastfmConnectButton.title = isConnected ? "Disconnect" : "Connect"
        lastfmConnectButton.isEnabled = isConnected || (account.state != .connecting && account.canConnect)
        // The settings say what happens to a signed-in user's plays, so they wait for one
        lastfmSpotifyCheckboxButton.isEnabled = isConnected
        lastfmLoveCheckboxButton.isEnabled = isConnected
        lastfmStatusTextField.stringValue = PreferencesViewController.lastfmStatus(
            state: account.state,
            username: account.username,
            canConnect: account.canConnect,
            problem: account.lastProblem,
            isPaused: defaults.lastfmPaused,
            waiting: LastfmScrobbler.shared.waitingCount,
            isDryRun: defaults.lastfmDryRun
        )
    }

    /// What the text under Last.fm's Connect button says. A dry run says so whatever else
    /// is true, since nothing is sent then; a problem comes first, as Spotify's does, except
    /// while connecting, when it belongs to the attempt before.
    static func lastfmStatus(state: LastfmAccount.State, username: String?, canConnect: Bool, problem: String?, isPaused: Bool, waiting: Int, isDryRun: Bool) -> String {
        if isDryRun {
            return "Dry run: StarBar logs what it would send to Last.fm and sends nothing."
        }
        let status: String
        switch state {
        case .connected:
            let name = username ?? "your Last.fm user"
            var text = isPaused ? "Connected as \(name). Scrobbling is paused." : "Scrobbling as \(name)."
            if waiting == 1 {
                text += " 1 play waiting to be sent."
            } else if waiting > 1 {
                text += " \(waiting) plays waiting to be sent."
            }
            status = text + " To remove StarBar's access, go to Applications in your Last.fm settings."
        case .connecting:
            return "Waiting for you to allow access on last.fm…"
        case .disconnected:
            status = canConnect
                ? "Scrobble what you play in Music to your Last.fm profile."
                : "This copy of StarBar was built without a Last.fm key, so it can't connect."
        }
        guard let problem = problem else { return status }
        return problem + " " + status
    }

}

extension PreferencesViewController {

    func setupWindow() {
        view.window?.styleMask.remove(.resizable)
    }

}

extension PreferencesViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Preferences"

        gridView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridView)
        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: gridView.trailingAnchor, constant: 16),
            view.bottomAnchor.constraint(equalTo: gridView.bottomAnchor, constant: 8),
            leadingPaddingView.widthAnchor.constraint(equalTo: trailingPaddingView.widthAnchor, multiplier: 1.0),
            gridView.widthAnchor.constraint(greaterThanOrEqualToConstant: 420), // magic width
        ])

        launchAtLoginCheckboxButton.target = self
        launchAtLoginCheckboxButton.action = #selector(PreferencesViewController.launchAtLoginCheckboxButtonChanged(_:))
        refreshLaunchAtLogin()
        NotificationCenter.default.addObserver(self, selector: #selector(PreferencesViewController.applicationDidBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)

        halfStarCheckboxButton.target = self
        halfStarCheckboxButton.action = #selector(PreferencesViewController.halfStarCheckboxButtonChanged(_:))
        halfStarObservation = UserDefaults.standard.observe(\.allowHalfStar, options: [.initial, .new]) { [weak self] defaults, launchAtLogin in
            self?.halfStarCheckboxButton.state = defaults.allowHalfStar ? .on : .off
        }

        reminderCheckboxButton.target = self
        reminderCheckboxButton.action = #selector(PreferencesViewController.reminderCheckboxButtonChanged(_:))
        reminderObservation = UserDefaults.standard.observe(\.remindToRateUnrated, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.reminderCheckboxButton.state = defaults.remindToRateUnrated ? .on : .off
        }

        announceCheckboxButton.target = self
        announceCheckboxButton.action = #selector(PreferencesViewController.announceCheckboxButtonChanged(_:))
        announcePreviewButton.target = self
        announcePreviewButton.action = #selector(PreferencesViewController.announcePreviewButtonPressed(_:))
        announceObservation = UserDefaults.standard.observe(\.announceNewTracks, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.announceCheckboxButton.state = defaults.announceNewTracks ? .on : .off
        }

        announcementStylePopUpButton.target = self
        announcementStylePopUpButton.action = #selector(PreferencesViewController.announcementStyleChanged(_:))
        announcementStyleObservation = UserDefaults.standard.observe(\.announcementStyle, options: [.initial, .new]) { [weak self] defaults, _ in
            let style = TrackAnnouncementStyle(storedValue: defaults.announcementStyle)
            self?.announcementStylePopUpButton.selectItem(withTitle: style.title)
        }

        spotifyConnectButton.target = self
        spotifyConnectButton.action = #selector(PreferencesViewController.spotifyConnectButtonPressed(_:))
        NotificationCenter.default.addObserver(self, selector: #selector(PreferencesViewController.spotifyAccountDidChange(_:)), name: .spotifyAccountDidChange, object: nil)
        refreshSpotify()

        lastfmConnectButton.target = self
        lastfmConnectButton.action = #selector(PreferencesViewController.lastfmConnectButtonPressed(_:))
        lastfmSpotifyCheckboxButton.target = self
        lastfmSpotifyCheckboxButton.action = #selector(PreferencesViewController.lastfmSpotifyCheckboxButtonChanged(_:))
        lastfmSpotifyObservation = UserDefaults.standard.observe(\.lastfmScrobbleSpotify, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.lastfmSpotifyCheckboxButton.state = defaults.lastfmScrobbleSpotify ? .on : .off
        }
        lastfmLoveCheckboxButton.target = self
        lastfmLoveCheckboxButton.action = #selector(PreferencesViewController.lastfmLoveCheckboxButtonChanged(_:))
        lastfmLoveObservation = UserDefaults.standard.observe(\.lastfmLoveSync, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.lastfmLoveCheckboxButton.state = defaults.lastfmLoveSync ? .on : .off
        }
        NotificationCenter.default.addObserver(self, selector: #selector(PreferencesViewController.lastfmDidChange(_:)), name: .lastfmAccountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(PreferencesViewController.lastfmDidChange(_:)), name: .lastfmScrobblerDidChange, object: nil)
        refreshLastfm()
    }

    override func viewDidAppear() {
        setupWindow()
        refreshLaunchAtLogin()
        refreshLastfm()
    }

}

extension PreferencesViewController {

    enum ShortcutKey: String {
        case ratingDown
        case ratingUp
        case showOrClosePopover
        case rating5
        case rating4
        case rating3
        case rating2
        case rating1
        case rating0
        case showCurrentTrack
    }

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct PreferencesViewController_Preview: PreviewProvider {

    static var previews: some View {
        NSViewControllerPreview {
            return PreferencesViewController()
        }
    }

}

#endif
