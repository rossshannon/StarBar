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

    lazy var startupTextField: NSTextField = {
        return NSTextField(labelWithString: "Startup: ")
    }()
    lazy var halfStarTextField: NSTextField = {
        return NSTextField(labelWithString: "Half star: ")
    }()
    lazy var reminderTextField: NSTextField = {
        return NSTextField(labelWithString: "Reminder: ")
    }()
    lazy var announceTextField: NSTextField = {
        return NSTextField(labelWithString: "Announce: ")
    }()
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
    lazy var rating5TextField: NSView = {
        return PreferencesViewController.starsLabel(count: 5, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating4TextField: NSView = {
        return PreferencesViewController.starsLabel(count: 4, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating3TextField: NSView = {
        return PreferencesViewController.starsLabel(count: 3, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating2TextField: NSView = {
        return PreferencesViewController.starsLabel(count: 2, fontSize: PreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating1TextField: NSView = {
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
        let button = NSButton(checkboxWithTitle: "Enable", target: nil, action: nil)
        return button
    }()
    let reminderCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Remind me to rate unrated songs", target: nil, action: nil)
        return button
    }()
    let announceCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Show a Music Video strip when a new song starts", target: nil, action: nil)
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

    let leadingPaddingView = NSView()
    let trailingPaddingView = NSView()

    lazy var gridView: NSGridView = {
        let empty = NSGridCell.emptyContentView

        let gridView = NSGridView(views: [
            [startupTextField, launchAtLoginCheckboxButton],
            [halfStarTextField, halfStarCheckboxButton],
            [reminderTextField, reminderCheckboxButton],
            [announceTextField, announceRowView],
            [announcementStyleTextField, announcementStylePopUpButton],
            [NSBox.separatorLine],
            [ratingDownTextField, ratingDownShortcutView],
            [ratingUpTextField, ratingUpShortcutView],
            [showOrClosePopoverTextField, showOrClosePopoverShortcutView],
            [showCurrentTrackTextField, showCurrentTrackShortcutView],
            [NSBox.separatorLine],
            [rating0TextField, rating0ShortcutView],
            [rating1TextField, rating1ShortcutView],
            [rating2TextField, rating2ShortcutView],
            [rating3TextField, rating3ShortcutView],
            [rating4TextField, rating4ShortcutView],
            [rating5TextField, rating5ShortcutView],
            [leadingPaddingView, trailingPaddingView]
        ])

        gridView.row(at: 0).rowAlignment = .lastBaseline

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

    override func loadView() {
        self.view = NSView()
    }

    deinit {
        halfStarObservation?.invalidate()
        reminderObservation?.invalidate()
        announceObservation?.invalidate()
        announcementStyleObservation?.invalidate()
    }

}

extension PreferencesViewController {

    /// A row label of `count` stars followed by a colon, for the rating shortcuts.
    ///
    /// The stars are a template image in an image view tinted with the label colour, so
    /// they follow light and dark mode like the text beside them. An image baked with the
    /// label colour at creation time (the earlier text-attachment approach) kept the colour
    /// of whichever appearance the window opened in.
    static func starsLabel(count: Int, fontSize: CGFloat) -> NSView {
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

        let colon = NSTextField(labelWithString: ":")
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
    }

    override func viewDidAppear() {
        setupWindow()
        refreshLaunchAtLogin()
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
