//
//  MenuBarOverlayWindow.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-24.
//

import Cocoa

/// A see-through window over the menu bar, for what StarBar draws outside its own item: the
/// heart's burst (`HeartBurstWindow`) and the five-star finale (`StarFinaleWindow`).
///
/// StarBar's menu bar item is a window of its own, and nothing drawn in it can leave it.
/// Widening the item to make room is ruled out too, since on macOS 27 any narrowing slides the
/// whole menu bar. So each effect gets one of these, laid over the item when it starts and
/// taken down when it ends: borderless, transparent, never key, ignoring the mouse so a quick
/// second click still reaches the item underneath, one level above the menu bar's items, and
/// on every Space. Like the strip's panel it never goes through `WindowManager`, which would
/// activate the app.
///
/// It has no clock of its own: `MenuBarRatingControl` steps what is drawn in it with the
/// change in the item that it belongs to, on one display link and one `SteppedTimeline`, so
/// the two can't drift apart and a stalled main thread pauses both alike.
class MenuBarOverlayWindow: NSPanel {

    /// One level above the menu bar's items, so the effect draws over the item and its
    /// neighbours. Below pop-up menus, so an open menu stays on top.
    static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = MenuBarOverlayWindow.windowLevel
        ignoresMouseEvents = true
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isExcludedFromWindowsMenu = true
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }

    /// Where the window is put is where it goes. The item is a few points below the screen's
    /// top edge, so the window can reach above it; AppKit would otherwise push it down,
    /// off-centre.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

}
