//
//  PreferencesViewController.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-7-2.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa

/// The Preferences window's content: a toolbar of panes, laid out the way macOS's own
/// Settings windows are. Each pane is a view controller of its own; this one switches between
/// them, fits the window to the pane on show, and opens on the pane chosen last.
final class PreferencesViewController: NSTabViewController {

    /// The panes, in toolbar order
    enum Pane: String, CaseIterable {
        case general
        case accounts
        case shortcuts

        /// The toolbar label, which is also the window's title while the pane is on show
        var title: String {
            switch self {
            case .general:   return "General"
            case .accounts:  return "Accounts"
            case .shortcuts: return "Shortcuts"
            }
        }

        /// The toolbar icon, an SF Symbol
        var symbolName: String {
            switch self {
            case .general:   return "gearshape"
            case .accounts:  return "person.crop.circle"
            case .shortcuts: return "keyboard"
            }
        }

        func makeViewController() -> NSViewController {
            switch self {
            case .general:   return GeneralPreferencesViewController()
            case .accounts:  return AccountsPreferencesViewController()
            case .shortcuts: return ShortcutsPreferencesViewController()
            }
        }
    }

    /// The window's position is kept by AppKit under this name
    static let frameAutosaveName = "Preferences"

    private let defaults: UserDefaults
    /// Set once the window has been fitted and placed for its first showing; until then
    /// there is no window on screen to resize
    private var hasPlacedWindow = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Read before the first pane is added: adding it selects it, which remembers it
        let remembered = defaults.string(forKey: ApplicationKey.preferencesPane.rawValue).flatMap(Pane.init(rawValue:)) ?? .general

        for pane in Pane.allCases {
            let viewController = pane.makeViewController()
            viewController.title = pane.title
            let item = NSTabViewItem(viewController: viewController)
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
        selectedTabViewItemIndex = Pane.allCases.firstIndex(of: remembered) ?? 0
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        guard let window = view.window else { return }
        window.styleMask.remove(.resizable)
        window.toolbarStyle = .preference

        guard !hasPlacedWindow else { return }
        hasPlacedWindow = true
        // Fitted before it is placed, so the centre or a saved position is the right size's
        fitWindowToSelectedPane(animated: false)
        if window.setFrameUsingName(PreferencesViewController.frameAutosaveName) {
            // The saved frame has the height of the pane on show when it was saved
            fitWindowToSelectedPane(animated: false)
        } else {
            window.center()
        }
        window.setFrameAutosaveName(PreferencesViewController.frameAutosaveName)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let pane = PreferencesViewController.pane(of: tabViewItem) {
            defaults.set(pane.rawValue, forKey: ApplicationKey.preferencesPane.rawValue)
        }
        // Before the window is up, viewWillAppear fits it to the pane it opens on
        guard hasPlacedWindow else { return }
        fitWindowToSelectedPane(animated: true)
    }

}

extension PreferencesViewController {

    /// The pane on show
    var selectedPane: Pane? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return PreferencesViewController.pane(of: tabViewItems[selectedTabViewItemIndex])
    }

    static func pane(of item: NSTabViewItem?) -> Pane? {
        return (item?.identifier as? String).flatMap(Pane.init(rawValue:))
    }

    /// The content size the window takes for a pane: the pane's own height, and the widest
    /// pane's width for every pane, so switching panes changes only the height
    func contentSize(for item: NSTabViewItem) -> NSSize {
        let widest = tabViewItems.compactMap { $0.viewController?.view.fittingSize.width }.max() ?? 0
        return NSSize(width: widest, height: item.viewController?.view.fittingSize.height ?? 0)
    }

    /// Resize the window to the pane on show, keeping its top edge where it is. Animated
    /// only when the window is on screen and Reduce Motion is off.
    func fitWindowToSelectedPane(animated: Bool) {
        guard let window = view.window, let contentView = window.contentView,
              tabViewItems.indices.contains(selectedTabViewItemIndex) else {
            return
        }
        let frame = PreferencesViewController.windowFrame(
            window.frame,
            contentSize: contentView.frame.size,
            fitting: contentSize(for: tabViewItems[selectedTabViewItemIndex]),
            within: window.screen?.visibleFrame
        )
        guard frame != window.frame else { return }
        let animate = animated && window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animate)
    }

    /// The frame of a window whose content is `contentSize` once its content is `target`
    /// instead. The title bar and toolbar keep their height, which is why this goes by the
    /// difference in content size rather than a frame worked out from a content rect, and
    /// the top edge stays put, as in macOS's own Settings windows. A window that would then
    /// reach below the bottom of the screen moves up, but never past the top.
    static func windowFrame(_ frame: NSRect, contentSize: NSSize, fitting target: NSSize, within visibleFrame: NSRect?) -> NSRect {
        var fitted = frame
        fitted.size.width += target.width - contentSize.width
        fitted.size.height += target.height - contentSize.height
        fitted.origin.y = frame.maxY - fitted.height
        if let visible = visibleFrame, fitted.minY < visible.minY {
            fitted.origin.y = min(visible.minY, visible.maxY - fitted.height)
        }
        return fitted
    }

}

extension PreferencesViewController {

    /// A pane's grid: labels right-aligned in the first column, controls left-aligned in the
    /// second, and a separator line across both columns for each `NSBox.separatorLine` row.
    /// `baselineLabels` sit on the text of the pop-up or push button beside them rather
    /// than at its top.
    static func makeGrid(_ rows: [[NSView]], baselineLabels: [NSView] = []) -> NSGridView {
        let gridView = NSGridView(views: rows)
        for label in baselineLabels {
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
    }

    /// The margin round each pane's grid
    static let paneMargin: CGFloat = 20

    /// Put a pane's grid in the pane's view: pinned to the top and centred across, with
    /// `paneMargin` round it, so the pane's fitting size is the grid's plus the margins.
    /// Only the top is required: while the window animates from one pane's height to
    /// another's, the pane can be briefly smaller than its grid, and the other margins
    /// give way rather than log constraints that can't be satisfied.
    static func install(_ gridView: NSGridView, in view: NSView) {
        gridView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridView)
        let yielding = [
            gridView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            gridView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: paneMargin),
            view.bottomAnchor.constraint(greaterThanOrEqualTo: gridView.bottomAnchor, constant: paneMargin),
        ]
        for constraint in yielding {
            constraint.priority = NSLayoutConstraint.Priority(999)
        }
        NSLayoutConstraint.activate(yielding + [
            gridView.topAnchor.constraint(equalTo: view.topAnchor, constant: paneMargin),
        ])
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
