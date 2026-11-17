//
//  ShortcutsPreferencesViewController.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-16.
//

import Cocoa
import MASShortcut

/// The Shortcuts pane of Preferences: a recorder for each keyboard shortcut, the four
/// actions first and then the ratings, most stars first
final class ShortcutsPreferencesViewController: NSViewController {

    static var defaultTextFieldFontSize: CGFloat {
        return NSTextField(labelWithString: "sample").font!.pointSize
    }

    lazy var showCurrentTrackTextField: NSTextField = {
        return NSTextField(labelWithString: "Show current track: ")
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
        return ShortcutsPreferencesViewController.starsLabel(count: 5, fontSize: ShortcutsPreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating4TextField: NSStackView = {
        return ShortcutsPreferencesViewController.starsLabel(count: 4, fontSize: ShortcutsPreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating3TextField: NSStackView = {
        return ShortcutsPreferencesViewController.starsLabel(count: 3, fontSize: ShortcutsPreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating2TextField: NSStackView = {
        return ShortcutsPreferencesViewController.starsLabel(count: 2, fontSize: ShortcutsPreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating1TextField: NSStackView = {
        return ShortcutsPreferencesViewController.starsLabel(count: 1, fontSize: ShortcutsPreferencesViewController.defaultTextFieldFontSize)
    }()
    lazy var rating0TextField: NSTextField = {
        return NSTextField(labelWithString: "Remove stars: ")
    }()

    let showCurrentTrackShortcutView = ShortcutsPreferencesViewController.recorder(for: .showCurrentTrack)
    let ratingDownShortcutView = ShortcutsPreferencesViewController.recorder(for: .ratingDown)
    let ratingUpShortcutView = ShortcutsPreferencesViewController.recorder(for: .ratingUp)
    let showOrClosePopoverShortcutView = ShortcutsPreferencesViewController.recorder(for: .showOrClosePopover)
    let rating5ShortcutView = ShortcutsPreferencesViewController.recorder(for: .rating5)
    let rating4ShortcutView = ShortcutsPreferencesViewController.recorder(for: .rating4)
    let rating3ShortcutView = ShortcutsPreferencesViewController.recorder(for: .rating3)
    let rating2ShortcutView = ShortcutsPreferencesViewController.recorder(for: .rating2)
    let rating1ShortcutView = ShortcutsPreferencesViewController.recorder(for: .rating1)
    let rating0ShortcutView = ShortcutsPreferencesViewController.recorder(for: .rating0)

    lazy var gridView: NSGridView = {
        return PreferencesViewController.makeGrid([
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
        ])
    }()

    override func loadView() {
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        PreferencesViewController.install(gridView, in: view)
    }

}

extension ShortcutsPreferencesViewController {

    /// A recorder that keeps its shortcut in UserDefaults under `key`, where the bindings
    /// in `AppDelegate`, `WindowManager` and `iTunesRadioStation` read it
    static func recorder(for key: PreferencesViewController.ShortcutKey) -> MASShortcutView {
        let shortcutView = MASShortcutView()
        shortcutView.associatedUserDefaultsKey = key.rawValue
        return shortcutView
    }

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
