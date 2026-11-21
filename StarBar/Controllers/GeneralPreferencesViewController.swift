//
//  GeneralPreferencesViewController.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-16.
//

import Cocoa
import os

/// The General pane of Preferences: launching at login, half stars, the rating reminder and
/// Spotify on other devices, then, under a line, the Music Video strip with its style and
/// colour
final class GeneralPreferencesViewController: NSViewController {

    lazy var announcementStyleTextField: NSTextField = {
        return NSTextField(labelWithString: "Strip style: ")
    }()
    lazy var albumTintTextField: NSTextField = {
        return NSTextField(labelWithString: "Album art tinting: ")
    }()

    let launchAtLoginCheckboxButton: NSButton = {
        let checkbox = LaunchAtLogin.checkbox(for: BuildInfo.current.variant)
        let button = NSButton(checkboxWithTitle: checkbox.title, target: nil, action: nil)
        button.isEnabled = checkbox.isEnabled
        button.toolTip = checkbox.toolTip
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
    /// Off, Spotify playing on another device shows on neither the strip nor the menu bar. It
    /// says what it does on its own, and the tooltip says what "other devices" are. Greyed
    /// out where this Mac can't tell (before macOS 14.2), since it would change nothing.
    let spotifyOtherDevicesCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Show Spotify songs playing on other devices", target: nil, action: nil)
        if ProcessAudioOutput.isAvailable {
            button.toolTip = "Spotify Connect plays on speakers, TVs and phones. With this off, StarBar shows only what Spotify plays on this Mac."
        } else {
            button.isEnabled = false
            button.toolTip = "StarBar can tell where Spotify plays from macOS 14.2. Until then, it shows Spotify songs wherever they play."
        }
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
    let albumTintPopUpButton: NSPopUpButton = {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in TrackAnnouncementAlbumTint.allCases {
            button.addItem(withTitle: mode.title)
            button.lastItem?.representedObject = mode.rawValue
        }
        return button
    }()

    lazy var gridView: NSGridView = {
        let empty = NSGridCell.emptyContentView
        let gridView = PreferencesViewController.makeGrid([
            // The checkboxes say what they do, so their rows need no label
            [empty, launchAtLoginCheckboxButton],
            [empty, halfStarCheckboxButton],
            [empty, reminderCheckboxButton],
            [empty, spotifyOtherDevicesCheckboxButton],
            // The strip's settings are a block of their own
            [NSBox.separatorLine],
            [empty, announceRowView],
            [announcementStyleTextField, announcementStylePopUpButton],
            [albumTintTextField, albumTintPopUpButton],
        ], baselineLabels: [announcementStyleTextField, albumTintTextField])
        gridView.row(at: 0).rowAlignment = .lastBaseline
        return gridView
    }()

    var halfStarObservation: NSKeyValueObservation?
    var reminderObservation: NSKeyValueObservation?
    var spotifyOtherDevicesObservation: NSKeyValueObservation?
    var announceObservation: NSKeyValueObservation?
    var announcementStyleObservation: NSKeyValueObservation?
    var albumTintObservation: NSKeyValueObservation?

    override func loadView() {
        self.view = NSView()
    }

    deinit {
        halfStarObservation?.invalidate()
        reminderObservation?.invalidate()
        spotifyOtherDevicesObservation?.invalidate()
        announceObservation?.invalidate()
        announcementStyleObservation?.invalidate()
        albumTintObservation?.invalidate()
    }

}

extension GeneralPreferencesViewController {

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
    }

    @objc private func halfStarCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.allowHalfStar = sender.state == .on
    }

    @objc private func reminderCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.remindToRateUnrated = sender.state == .on
    }

    @objc private func spotifyOtherDevicesCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.spotifyShowsOtherDevices = sender.state == .on
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

    @objc private func albumTintChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        UserDefaults.standard.announcementAlbumTint = rawValue
    }

}

extension GeneralPreferencesViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        PreferencesViewController.install(gridView, in: view)

        launchAtLoginCheckboxButton.target = self
        launchAtLoginCheckboxButton.action = #selector(GeneralPreferencesViewController.launchAtLoginCheckboxButtonChanged(_:))
        refreshLaunchAtLogin()
        NotificationCenter.default.addObserver(self, selector: #selector(GeneralPreferencesViewController.applicationDidBecomeActive(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)

        halfStarCheckboxButton.target = self
        halfStarCheckboxButton.action = #selector(GeneralPreferencesViewController.halfStarCheckboxButtonChanged(_:))
        halfStarObservation = UserDefaults.standard.observe(\.allowHalfStar, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.halfStarCheckboxButton.state = defaults.allowHalfStar ? .on : .off
        }

        reminderCheckboxButton.target = self
        reminderCheckboxButton.action = #selector(GeneralPreferencesViewController.reminderCheckboxButtonChanged(_:))
        reminderObservation = UserDefaults.standard.observe(\.remindToRateUnrated, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.reminderCheckboxButton.state = defaults.remindToRateUnrated ? .on : .off
        }

        spotifyOtherDevicesCheckboxButton.target = self
        spotifyOtherDevicesCheckboxButton.action = #selector(GeneralPreferencesViewController.spotifyOtherDevicesCheckboxButtonChanged(_:))
        spotifyOtherDevicesObservation = UserDefaults.standard.observe(\.spotifyShowsOtherDevices, options: [.initial, .new]) { [weak self] defaults, _ in
            // Before macOS 14.2 StarBar shows them whatever the setting says, and so does the box
            self?.spotifyOtherDevicesCheckboxButton.state = defaults.spotifyShowsOtherDevices || !ProcessAudioOutput.isAvailable ? .on : .off
        }

        announceCheckboxButton.target = self
        announceCheckboxButton.action = #selector(GeneralPreferencesViewController.announceCheckboxButtonChanged(_:))
        announcePreviewButton.target = self
        announcePreviewButton.action = #selector(GeneralPreferencesViewController.announcePreviewButtonPressed(_:))
        announceObservation = UserDefaults.standard.observe(\.announceNewTracks, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.announceCheckboxButton.state = defaults.announceNewTracks ? .on : .off
        }

        announcementStylePopUpButton.target = self
        announcementStylePopUpButton.action = #selector(GeneralPreferencesViewController.announcementStyleChanged(_:))
        announcementStyleObservation = UserDefaults.standard.observe(\.announcementStyle, options: [.initial, .new]) { [weak self] defaults, _ in
            let style = TrackAnnouncementStyle(storedValue: defaults.announcementStyle)
            self?.announcementStylePopUpButton.selectItem(withTitle: style.title)
        }

        albumTintPopUpButton.target = self
        albumTintPopUpButton.action = #selector(GeneralPreferencesViewController.albumTintChanged(_:))
        albumTintObservation = UserDefaults.standard.observe(\.announcementAlbumTint, options: [.initial, .new]) { [weak self] defaults, _ in
            let mode = TrackAnnouncementAlbumTint(storedValue: defaults.announcementAlbumTint)
            self?.albumTintPopUpButton.selectItem(withTitle: mode.title)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshLaunchAtLogin()
    }

}
