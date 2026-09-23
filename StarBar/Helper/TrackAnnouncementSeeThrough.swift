//
//  TrackAnnouncementSeeThrough.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-23.
//

import AppKit

/// Seeing through the strip. Its blur or glass hides whatever sits at the bottom of the screen,
/// which is often the text box the user is typing in. The panel already lets clicks through;
/// these are the rules for letting the eye through too: a soft hole in the background that
/// follows the pointer, and a larger window in the middle of the strip while the user types.
/// The text, artwork and stars stay drawn in both cases.
enum TrackAnnouncementSeeThrough {

    /// The hole's radius, and the soft edge inside it, in points at scale 1. Ross tried 60
    /// and 24 on the live strip and asked for three times the size, then half as big again:
    /// the hole is much wider than the strip is tall, so it opens a wide slot through it
    /// rather than a spot.
    static let peepholeRadius: CGFloat = 270
    static let peepholeFeather: CGFloat = 108
    /// The typing window, in the middle of the strip and bigger than the pointer's hole. It
    /// replaced fading the whole background, which left the white text over whatever was
    /// behind and hard to read.
    static let typingRadius: CGFloat = 360
    static let typingFeather: CGFloat = 144
    /// How far above the strip's top edge the window's centre sits. Centred in the strip, the
    /// circle was narrowest at the top, so the glass jutted in over it; from above, the part
    /// inside the strip is widest at the top and narrows downwards, a concave scoop that frames
    /// what is just above the strip, where the text box being typed in usually is.
    static let typingCentreHeight: CGFloat = 90
    /// Room kept around the artwork and text, and the soft edge after it, at scale 1
    static let keepMargin: CGFloat = 24
    static let keepFeather: CGFloat = 48
    /// A key pressed within this long ago means the user is typing
    static let typingPause: TimeInterval = 1.5
    /// The window opens quickly when typing starts, and closes gently
    static let openDuration: TimeInterval = 0.15
    static let closeDuration: TimeInterval = 0.4

    /// The hole for a pointer at `pointer`, in the strip's own coordinates, or nil when the
    /// pointer is too far from the strip for any of the hole to reach it.
    ///
    /// - Parameters:
    ///   - pointer: the pointer, in screen coordinates
    ///   - stripFrame: the strip, in screen coordinates
    static func peephole(pointer: CGPoint, stripFrame: CGRect, radius: CGFloat, feather: CGFloat) -> TrackAnnouncementPeephole? {
        guard radius > 0 else { return nil }
        let centre = CGPoint(x: pointer.x - stripFrame.minX, y: pointer.y - stripFrame.minY)
        let bounds = CGRect(origin: .zero, size: stripFrame.size)
        // The pointer's distance from the nearest point of the strip; 0 inside it
        let dx = max(bounds.minX - centre.x, 0, centre.x - bounds.maxX)
        let dy = max(bounds.minY - centre.y, 0, centre.y - bounds.maxY)
        guard dx * dx + dy * dy < radius * radius else { return nil }
        return TrackAnnouncementPeephole(centre: centre, radius: radius, feather: min(max(0, feather), radius))
    }

    /// The square the hole's image fills, snapped to the pixel grid so that the rectangles
    /// around it meet it exactly. Rectangles meeting mid-pixel would each half-cover the
    /// shared pixels and leave a faint see-through seam.
    static func holeRect(for peephole: TrackAnnouncementPeephole, scale: CGFloat) -> CGRect {
        let scale = max(1, scale)
        let side = (peephole.radius * 2 * scale).rounded(.up) / scale
        let x = ((peephole.centre.x - side / 2) * scale).rounded() / scale
        let y = ((peephole.centre.y - side / 2) * scale).rounded() / scale
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The four solid rectangles that fill `bounds` around `hole`: below, above, left and
    /// right, in that order. The left and right ones span only the hole's height, so none of
    /// them overlap. A rectangle with nothing to cover comes back empty.
    static func maskTiles(around hole: CGRect, in bounds: CGRect) -> [CGRect] {
        let bottom = min(max(hole.minY, bounds.minY), bounds.maxY)
        let top = max(min(hole.maxY, bounds.maxY), bounds.minY)
        let left = min(max(hole.minX, bounds.minX), bounds.maxX)
        let right = max(min(hole.maxX, bounds.maxX), bounds.minX)
        return [
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bottom - bounds.minY),
            CGRect(x: bounds.minX, y: top, width: bounds.width, height: bounds.maxY - top),
            CGRect(x: bounds.minX, y: bottom, width: left - bounds.minX, height: top - bottom),
            CGRect(x: right, y: bottom, width: bounds.maxX - right, height: top - bottom),
        ]
    }

    /// One step of the typing window towards `target` (1 open, 0 closed) after `elapsed`
    /// seconds: open over `openDuration`, closed over `closeDuration`
    static func typingProgress(_ progress: CGFloat, toward target: CGFloat, elapsed: TimeInterval) -> CGFloat {
        guard elapsed > 0 else { return progress }
        if target > progress {
            return min(target, progress + CGFloat(elapsed / openDuration))
        }
        return max(target, progress - CGFloat(elapsed / closeDuration))
    }

    /// The typing window for a strip of `bounds`: a hole centred across the strip, its centre
    /// `centreHeight` above the strip's top edge, with the background kept from the strip's
    /// leading edge to `margin` past `occupied`, the part the artwork and text cover. Nil when
    /// closed.
    static func typingWindow(in bounds: CGRect, occupied: CGRect, radius: CGFloat, feather: CGFloat, centreHeight: CGFloat, margin: CGFloat, keepFeather: CGFloat, progress: CGFloat) -> TrackAnnouncementTypingWindow? {
        guard radius > 0, progress > 0 else { return nil }
        let hole = TrackAnnouncementPeephole(centre: CGPoint(x: bounds.midX, y: bounds.maxY + centreHeight), radius: radius, feather: min(max(0, feather), radius))
        let keepUntilX = occupied.isNull || occupied.isEmpty ? bounds.minX : min(bounds.maxX, occupied.maxX + margin)
        return TrackAnnouncementTypingWindow(hole: hole, keepUntilX: keepUntilX, keepFeather: max(0, keepFeather), progress: min(1, progress))
    }

}

/// The hole through the strip's background, in the strip's coordinates. Fully clear out to
/// `radius - feather`, fading to solid at `radius`.
struct TrackAnnouncementPeephole: Equatable {
    var centre: CGPoint
    var radius: CGFloat
    var feather: CGFloat
}

/// The window through the strip's background while the user types: a large soft hole, with
/// the background kept under the artwork and text whatever the hole covers
struct TrackAnnouncementTypingWindow: Equatable {
    var hole: TrackAnnouncementPeephole
    /// The background stays solid from the strip's leading edge to here
    var keepUntilX: CGFloat
    /// And fades out over this much after it
    var keepFeather: CGFloat
    /// How far open, 0 to 1
    var progress: CGFloat
}

/// What the keyboard is doing: how long ago a key last went down, whether Command or Control is
/// held now, and how long ago any modifier key last went down or up
struct KeyboardActivity: Equatable {
    var secondsSinceKeyDown: TimeInterval
    var commandKeysHeld: Bool
    var secondsSinceModifierChange: TimeInterval = .infinity

    /// The system's answer. None of the reads needs a permission: the ages are the same idle
    /// times a screen saver reads, and say nothing about which key it was.
    static func system() -> KeyboardActivity {
        return KeyboardActivity(
            secondsSinceKeyDown: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            commandKeysHeld: isShortcut(NSEvent.modifierFlags),
            secondsSinceModifierChange: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .flagsChanged)
        )
    }

    /// Whether keys pressed with these modifiers are shortcuts. Command or Control make one;
    /// Option on its own does not, because it types characters: accents, and # on a British
    /// keyboard, @ and brackets on many European ones. StarBar's own shortcuts hold Control.
    static func isShortcut(_ flags: NSEvent.ModifierFlags) -> Bool {
        return !flags.intersection([.command, .control]).isEmpty
    }
}

/// Whether the user is typing, from successive readings of the keyboard.
///
/// A key pressed while Command or Control is held is a shortcut, not typing, and doesn't
/// count. StarBar's own rating shortcuts are such keys, and rating from the keyboard must not
/// clear the background of the strip that is showing the new rating.
///
/// The modifiers can only be read as they are now, not as they were when the key went down,
/// so a shortcut let go of before the reading would look like typing. That is the usual case
/// for the key that brought the strip up: Command-Right Arrow in Music, say, is released while
/// StarBar reads the new song over Apple Events. So a key followed by any modifier change
/// doesn't count either. The cost is a capital letter whose Shift was let go of before the
/// reading; the next plain key counts.
struct TrackAnnouncementTyping {

    /// When the last key that counts as typing went down
    private(set) var lastTypedAt: Date?
    /// When the last key of any kind went down, to tell a new press from the same one read again
    private var lastKeyDownAt: Date?

    /// Two readings of one key press can place it a hair apart, because the key's age and the
    /// clock are read at slightly different moments
    static let sameKeyTolerance: TimeInterval = 0.005

    mutating func observe(_ keyboard: KeyboardActivity, at now: Date) {
        let age = keyboard.secondsSinceKeyDown
        // No key this session, or a reading that makes no sense: nothing to go on
        guard age.isFinite, age >= 0 else { return }
        let keyDownAt = now.addingTimeInterval(-age)
        defer { lastKeyDownAt = keyDownAt }
        if let last = lastKeyDownAt, keyDownAt.timeIntervalSince(last) <= TrackAnnouncementTyping.sameKeyTolerance {
            return
        }
        guard !keyboard.commandKeysHeld else { return }
        // A modifier went down or up after the key: most likely a shortcut, let go of since
        guard !(keyboard.secondsSinceModifierChange < age) else { return }
        lastTypedAt = keyDownAt
    }

    func isTyping(at now: Date, pause: TimeInterval) -> Bool {
        guard let typed = lastTypedAt else { return false }
        return now.timeIntervalSince(typed) < pause
    }

}

/// Knobs for trying the see-through behaviour without a rebuild, read from defaults each time
/// the strip appears. `announcementPeephole` (bool; true by default: the hole that follows the
/// pointer), `announcementPeepholeRadius` and `announcementPeepholeFeather` (points at scale 1;
/// 270 and 108 by default), `announcementTypingWindow` (bool; true by default: the window in
/// the middle of the strip while the user types), `announcementTypingRadius`,
/// `announcementTypingFeather` and `announcementTypingCentreHeight` (points at scale 1; 360,
/// 144 and 90 by default; the last is how far above the strip's top edge the window's centre
/// sits, and may be negative) and `announcementTypingPause` (seconds; 1.5 by default: how long
/// after the last key the window stays open).
struct TrackAnnouncementSeeThroughKnobs: Equatable {
    var peephole = true
    var radius = TrackAnnouncementSeeThrough.peepholeRadius
    var feather = TrackAnnouncementSeeThrough.peepholeFeather
    var typingWindow = true
    var typingRadius = TrackAnnouncementSeeThrough.typingRadius
    var typingFeather = TrackAnnouncementSeeThrough.typingFeather
    var typingCentreHeight = TrackAnnouncementSeeThrough.typingCentreHeight
    var typingPause = TrackAnnouncementSeeThrough.typingPause

    /// Where the panel gets its knobs. The tests are hosted in the app, so they replace this
    /// with fixed values rather than read whatever is set on the machine.
    static var read: () -> TrackAnnouncementSeeThroughKnobs = { current }

    static var current: TrackAnnouncementSeeThroughKnobs {
        let defaults = UserDefaults.standard
        var knobs = TrackAnnouncementSeeThroughKnobs()
        func length(_ key: String) -> CGFloat? {
            return defaults.object(forKey: key) == nil ? nil : max(0, CGFloat(defaults.double(forKey: key)))
        }
        if defaults.object(forKey: "announcementPeephole") != nil {
            knobs.peephole = defaults.bool(forKey: "announcementPeephole")
        }
        knobs.radius = length("announcementPeepholeRadius") ?? knobs.radius
        knobs.feather = length("announcementPeepholeFeather") ?? knobs.feather
        if defaults.object(forKey: "announcementTypingWindow") != nil {
            knobs.typingWindow = defaults.bool(forKey: "announcementTypingWindow")
        }
        knobs.typingRadius = length("announcementTypingRadius") ?? knobs.typingRadius
        knobs.typingFeather = length("announcementTypingFeather") ?? knobs.typingFeather
        if defaults.object(forKey: "announcementTypingCentreHeight") != nil {
            knobs.typingCentreHeight = CGFloat(defaults.double(forKey: "announcementTypingCentreHeight"))
        }
        if defaults.object(forKey: "announcementTypingPause") != nil {
            knobs.typingPause = max(0, defaults.double(forKey: "announcementTypingPause"))
        }
        return knobs
    }
}
