//
//  WindowManager.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-7-2.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa
import os
import MASShortcut

final class WindowManager: NSObject {

    private(set) var aboutWindowController: NSWindowController?
    private(set) var preferencesWindowController: NSWindowController?

    private var hasWindowDisplay: Bool {
        return ![aboutWindowController, preferencesWindowController].compactMap { $0 }.isEmpty
    }

    private let popoverProxy = PopoverProxy()

    weak var menuBarRatingControl: MenuBarRatingControl?
    private(set) var invisibleWindows: [Int: NSWindow] = [:]
    private(set) var attachedPopover: NSPopover?
    private(set) var detachedPopover: NSPopover?
    /// Where the attached popover's invisible window was last asked to go. Compared with this
    /// rather than the window's frame, because the system nudges a window off the menu bar and
    /// the frame never matches the origin asked for.
    private var popoverAnchorOrigin: NSPoint?

    // MARK: - Singleton
    public static let shared = WindowManager()

    private override init() {
        super.init()

        NSWindow.allowsAutomaticWindowTabbing = false

        popoverProxy.delegate = self

        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.showOrClosePopover.rawValue, toAction: { [weak self] in
            guard self?.attachedPopover == nil else {
                self?.closeAttachedPopover()
                return
            }

            self?.triggerPopover()
        })
    }

}

extension WindowManager {

    func open(_ windowType: WindowType) {
        let windowController: NSWindowController? = {
            switch windowType {
            case .about:
                if aboutWindowController == nil {
                    aboutWindowController = NSWindowController(window: NSWindow(contentViewController: windowType.viewController))
                }
                return aboutWindowController

            case .preferences:
                if preferencesWindowController == nil {
                    preferencesWindowController = NSWindowController(window: NSWindow(contentViewController: windowType.viewController))
                }
                return preferencesWindowController
            }
        }()

        windowController?.window?.delegate = self
        windowController?.showWindow(self)

        // brint to front
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)

        updateActivationPolicy()
    }

    func triggerPopover() {
        // The player popover reads from Music, which UI-testing mode must never touch
        guard !MenuBarRatingControl.isUITesting,
              let button = menuBarRatingControl?.statusItem.button else {
            return
        }

        // close undetached popover if displaying
        guard attachedPopover == nil else {
            closeAttachedPopover()
            return
        }

        // Ref: https://stackoverflow.com/questions/48594212/how-to-open-a-nspopover-at-a-distance-from-the-system-bar/48604455#48604455
        let popoverRelativeWindow = NSWindow(contentRect: NSMakeRect(0, 0, 20, 5), styleMask: .borderless, backing: .buffered, defer: false)
        popoverRelativeWindow.delegate = self
        popoverRelativeWindow.backgroundColor = .red
        popoverRelativeWindow.alphaValue = 0

        guard let anchor = menuBarRatingControl?.popoverAnchorInScreen else {
            assertionFailure()
            return
        }

        // position and show the window
        let origin = WindowManager.popoverRelativeWindowOrigin(for: anchor)
        popoverRelativeWindow.setFrameOrigin(origin)
        popoverAnchorOrigin = origin
        popoverRelativeWindow.makeKeyAndOrderFront(self)
        popoverRelativeWindow.level = .floating                       // make popover always on top
        popoverRelativeWindow.isReleasedWhenClosed = false            // seealso: WindowManager.popoverDidClose(_:)

        let popover = NSPopover()
        popover.contentViewController = PopoverViewController()
        popover.behavior = .transient
        popover.delegate = popoverProxy

        invisibleWindows[popover.hashValue] = popoverRelativeWindow

        // position and show the NSPopover
        popover.show(relativeTo: popoverRelativeWindow.contentView!.frame, of: popoverRelativeWindow.contentView!, preferredEdge: NSRectEdge.minY)
//        NSApplication.shared.activate(ignoringOtherApps: true)
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
//            popover.contentViewController?.view.window?.makeKey()   // fix popover not get focus issue
//        }

        attachedPopover = popover

        // The status item's own window moves when other menu bar items come and go, and is
        // resized when the strip starts or stops
        stopFollowingStatusItemWindow()
        if let buttonWindow = button.window {
            for name in WindowManager.statusItemWindowChanges {
                NotificationCenter.default.addObserver(self, selector: #selector(WindowManager.statusItemWindowDidChange(_:)), name: name, object: buttonWindow)
            }
        }
    }

    /// Close the popover attached to the menu bar, if there is one. The reference is dropped
    /// first: the popover counts as shown until its close animation ends, and a menu bar
    /// update in that time would otherwise move it, towards the stopped icon when Music quits.
    func closeAttachedPopover() {
        let popover = attachedPopover
        attachedPopover = nil
        popover?.close()
    }

    /// Bottom-left of the invisible window the popover points at, centred on the anchor
    /// (10 is half the window's width)
    static func popoverRelativeWindowOrigin(for anchor: NSRect) -> NSPoint {
        return NSPoint(x: anchor.midX - 10, y: anchor.minY)
    }

    /// Keep the attached popover pointing just left of the heart as the menu bar changes
    /// under it. A detached popover is a window of its own and stays where it was put.
    func updatePopoverAnchor() {
        guard let popover = attachedPopover, popover.isShown,
              let window = invisibleWindows[popover.hashValue],
              let contentView = window.contentView,
              let anchor = menuBarRatingControl?.popoverAnchorInScreen else {
            return
        }
        let origin = WindowManager.popoverRelativeWindowOrigin(for: anchor)
        guard origin != popoverAnchorOrigin else { return }
        popoverAnchorOrigin = origin
        window.setFrameOrigin(origin)
        // Setting it while the popover is shown is what makes the popover reposition
        popover.positioningRect = contentView.bounds
        os_log("%{public}s[%{public}ld], %{public}s: moved popover anchor to x %.1f", ((#file as NSString).lastPathComponent), #line, #function, Double(anchor.midX))
    }

    private static let statusItemWindowChanges = [NSWindow.didMoveNotification, NSWindow.didResizeNotification]

    @objc private func statusItemWindowDidChange(_ notification: Notification) {
        updatePopoverAnchor()
    }

    private func stopFollowingStatusItemWindow() {
        for name in WindowManager.statusItemWindowChanges {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
    }

}

extension WindowManager {

    private func updateActivationPolicy() {
        NSApplication.shared.setActivationPolicy(hasWindowDisplay ? .regular : .accessory)
    }

}

extension WindowManager {

    enum WindowType {
        case about
        case preferences

        var viewController: NSViewController {
            switch self {
            case .about:        return AboutViewController()
            case .preferences:  return PreferencesViewController()
            }
        }
    }

}

extension WindowManager {

    @objc func preferencesMenuItemPressed(_ sender: NSMenuItem) {
        open(.preferences)
    }

    @objc func aboutMenuItemPressed(_ sender: NSMenuItem) {
        open(.about)
    }

}

// MARK: - NSWindowDelegate
extension WindowManager: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        switch notification {
        case _ where window === self.aboutWindowController?.window:
            aboutWindowController = nil
            os_log("%{public}s[%{public}ld], %{public}s: About window closed", ((#file as NSString).lastPathComponent), #line, #function)
        case _ where window === self.preferencesWindowController?.window:
            preferencesWindowController = nil
            os_log("%{public}s[%{public}ld], %{public}s: Preferences window closed", ((#file as NSString).lastPathComponent), #line, #function)
        default:
            os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, notification.description)
        }

        updateActivationPolicy()
    }
}

// MARK: - PopoverProxyDelegate
extension WindowManager: PopoverProxyDelegate {

    func popoverDidClose(_ notification: Notification) {
        // check which popover closed and release it

        os_log("%{public}s[%{public}ld], %{public}s: notification: %s", ((#file as NSString).lastPathComponent), #line, #function, notification.description)

        if let popover = attachedPopover, !popover.isShown {
            attachedPopover = nil
        }
        if attachedPopover == nil {
            stopFollowingStatusItemWindow()
        }

        if let popover = detachedPopover, !popover.isShown {
            detachedPopover = nil
        }

        // fix popover relative window crash app when set release when close issue
        if let popover = notification.object as? NSPopover {
            let window = self.invisibleWindows[popover.hashValue]       // retain
            self.invisibleWindows[popover.hashValue] = nil
            window?.close()
            // auto release here
        }
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return true
    }

    func popoverDidDetach(_ popover: NSPopover) {
        attachedPopover = nil
        stopFollowingStatusItemWindow()
        detachedPopover?.close()

        popover.behavior = .applicationDefined
        detachedPopover = popover

        os_log("%{public}s[%{public}ld], %{public}s: popoverDidDetach", ((#file as NSString).lastPathComponent), #line, #function)
    }

}
