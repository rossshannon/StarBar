//
//  StarFlourish.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-23.
//

import Cocoa

/// What the stars do when the user rates a song in StarBar. The timing and the drawing of one
/// frame, with nothing of the menu bar or the strip in it, so the rules can be tested without
/// a window: `MenuBarRatingControl` steps the menu bar's stars and the strip's panel steps its
/// own, both on a display link, as they do the heart's change (`HeartChange`).
///
/// Ross asked for it on 2026-11-23: a heart set in StarBar bursts, and the stars only appeared.
/// He was shown eight flourishes side by side at true size, in the menu bar and on the strip.
/// What they all share is here:
///
/// - A rating saved at the same number of stars or more is a flourish: the lit stars pop one
///   after another from the left, in the chosen `Look`. Stars the save lights grow out of their
///   dots as the run reaches them; stars already lit (on macOS 27 the press has lit them before
///   the release saves them) pop where they are.
/// - A rating lowered or removed is quiet, as a heart taken away never bursts: the stars fold
///   back into their dots from the right.
/// - Reduce Motion cross-fades the glyphs that change, and nothing moves.
/// - While the mouse button is held and the stars follow it, a glyph that changes grows or
///   shrinks quickly rather than switching, and nothing pops: nothing is saved yet.
///
/// He chose the one-colour run on 2026-11-24 (`Look.run`), with the five-star finale on top
/// (`StarFinale`): a song given five stars has each star throw a small coloured star of its
/// own as the run reaches it.
struct StarFlourish: Equatable {

    /// Which flourish a raised rating gets.
    ///
    /// The hidden default `starFlourish` picks one by name (`run`, `afterglow` or `pop`), read
    /// at each rating, so the three can be compared on the real menu bar without a rebuild.
    enum Look: String, CaseIterable, Equatable {
        /// The run, and the app icon's five colours flash on each star as it pops, then cool
        /// back to the menu bar's own colour
        case afterglow
        /// The stars pop one after another from the left, the last one hardest, in the menu
        /// bar's own colour
        case run
        /// Every lit star grows to 110% together and settles: the plain pop Ross named as
        /// the fallback
        case pop

        /// The look in use: `run`, which Ross chose, unless the hidden default names another
        static func current(_ defaults: UserDefaults = .standard) -> Look {
            return defaults.string(forKey: "starFlourish").flatMap { Look(rawValue: $0) } ?? .run
        }

        /// How long after one star the next one starts
        var stagger: TimeInterval {
            return self == .pop ? 0 : 0.05
        }

        /// How long one star's part lasts, from when the flourish reaches it
        var starDuration: TimeInterval {
            switch self {
            case .afterglow: return StarFlourish.tintCoolStart + StarFlourish.tintCoolDuration
            case .run: return 0.3
            case .pop: return 0.25
            }
        }

        /// Whether the stars flash in colour, which needs something drawn over the template
        /// image, as the red heart is
        var tints: Bool {
            return self == .afterglow
        }

        /// The size a star grows from when it was a dot until now
        var bloomScale: Double {
            return self == .pop ? 0.7 : 0.45
        }

        /// A star's size through its pop, against its own: seconds since the flourish reached
        /// it, and the size then. It overshoots, dips a little under and settles.
        func popKeys(from start: Double, isLast: Bool) -> [(Double, Double)] {
            switch self {
            case .afterglow: return [(0, start), (0.09, isLast ? 1.26 : 1.17), (0.2, 0.96), (0.3, 1)]
            case .run: return [(0, start), (0.09, isLast ? 1.3 : 1.2), (0.2, 0.95), (0.3, 1)]
            case .pop: return [(0, start), (0.09, 1.1), (0.25, 1)]
            }
        }
    }

    enum Kind: Equatable {
        /// Saved at the same rating or a higher one: the lit stars pop, in the `Look`
        case raise
        /// Saved lower, or removed: the stars fold back into their dots from the right
        case lower
        /// Saved under Reduce Motion: the glyphs that change cross-fade where they are
        case fade
        /// Not saved yet: the stars following the mouse while its button is held
        case preview
    }

    let kind: Kind
    let look: Look
    /// What each of the five slots showed when the flourish began
    let from: [Star.Style]
    /// What each shows when it ends
    let to: [Star.Style]
    /// Whether the five-star finale plays with it (`StarFinale`): the song was given five
    /// stars and didn't have them before. Whoever draws the flourish draws the finale, stepped
    /// on the same clock, and `duration` allows for it.
    let hasFinale: Bool

    /// The largest any look draws a star, against its own size
    static let largestScale: CGFloat = 1.3
    /// How long a star the run lights takes to come out of its dot
    static let bloomFadeDuration: TimeInterval = 0.07
    /// How long the colour takes to come up on a star, how long after the flourish reached the
    /// star it starts to cool, and how long the cooling takes
    static let tintRiseDuration: TimeInterval = 0.04
    static let tintCoolStart: TimeInterval = 0.2
    static let tintCoolDuration: TimeInterval = 0.48
    /// A rating lowered: how long after one star the next one to its left starts to fold, and
    /// how long each takes
    static let lowerStagger: TimeInterval = 0.03
    static let lowerDuration: TimeInterval = 0.14
    static let fadeDuration: TimeInterval = 0.15
    static let previewDuration: TimeInterval = 0.1

    private init(kind: Kind, look: Look, from: [Star.Style], to: [Star.Style], hasFinale: Bool = false) {
        self.kind = kind
        self.look = look
        self.from = from
        self.to = to
        self.hasFinale = hasFinale
    }

    /// The flourish for a rating the user has just saved.
    ///
    /// - Parameters:
    ///   - rating: the rating saved, 0 to 100
    ///   - before: the song's rating before the gesture began, which decides whether this is
    ///     a rating raised or lowered. The same rating chosen again counts as raised, so a
    ///     click on the stars a song already has still answers.
    ///   - shown: the rating the stars showed as the gesture ended: `before` for a shortcut or
    ///     a quick click, and whatever the stars had followed the mouse to for a press that
    ///     was held
    init(saving rating: Int, from before: Int, showing shown: Int, reduceMotion: Bool, look: Look = .run) {
        let to = Stars.styles(forRating: rating)
        let kind: Kind
        if reduceMotion {
            kind = .fade
        } else if rating < before || !to.contains(where: { $0 != .dot }) {
            kind = .lower
        } else {
            kind = .raise
        }
        // The finale is for a song that becomes five stars, not for five stars chosen again,
        // and never under Reduce Motion, where nothing moves
        let hadFiveStars = StarFlourish.isFiveStars(Stars.styles(forRating: before))
        self.init(kind: kind, look: look, from: Stars.styles(forRating: shown), to: to,
                  hasFinale: kind == .raise && StarFlourish.isFiveStars(to) && !hadFiveStars)
    }

    private static func isFiveStars(_ styles: [Star.Style]) -> Bool {
        return styles.allSatisfy { $0 == .full }
    }

    /// The stars following the mouse from `shown` to `rating` while its button is held, or nil
    /// when no glyph changes, or under Reduce Motion, where they switch as they always did
    static func preview(from shown: Int, to rating: Int, reduceMotion: Bool) -> StarFlourish? {
        guard !reduceMotion else { return nil }
        let flourish = StarFlourish(kind: .preview, look: .afterglow,
                                    from: Stars.styles(forRating: shown), to: Stars.styles(forRating: rating))
        return flourish.duration > 0 ? flourish : nil
    }

    /// How many stars are lit at the end, half stars included
    var lit: Int {
        return to.filter { $0 != .dot }.count
    }

    /// Whether slot `index` ends as something other than it began
    func changes(_ index: Int) -> Bool {
        return from.indices.contains(index) && to.indices.contains(index) && from[index] != to[index]
    }

    private var changeCount: Int {
        return to.indices.filter { changes($0) }.count
    }

    /// When the flourish reaches slot `index`, in seconds from its start
    func delay(of index: Int) -> TimeInterval {
        switch kind {
        case .raise:
            // A slot past the lit stars was lit by the drag and isn't now: it goes at once
            return index < lit ? TimeInterval(index) * look.stagger : 0
        case .lower:
            // From the right: one step for each slot after this one that changes too
            let later = to.indices.filter { $0 > index && changes($0) }.count
            return TimeInterval(later) * StarFlourish.lowerStagger
        case .fade, .preview:
            return 0
        }
    }

    /// How long the whole flourish takes, the finale included: 0 when there is nothing to
    /// draw, such as no stars chosen for a song that had none
    var duration: TimeInterval {
        return hasFinale ? max(starsDuration, StarFinale.duration(stagger: look.stagger)) : starsDuration
    }

    /// How long the stars themselves take. From then on they are drawn at rest, while the
    /// finale's small stars, if it has one, are still in the air.
    var starsDuration: TimeInterval {
        switch kind {
        case .raise:
            return lit == 0 ? 0 : TimeInterval(lit - 1) * look.stagger + look.starDuration
        case .lower:
            return changeCount == 0 ? 0 : TimeInterval(changeCount - 1) * StarFlourish.lowerStagger + StarFlourish.lowerDuration
        case .fade:
            return changeCount == 0 ? 0 : StarFlourish.fadeDuration
        case .preview:
            return changeCount == 0 ? 0 : StarFlourish.previewDuration
        }
    }

    /// How one slot is drawn at a moment
    struct Pose: Equatable {
        /// The star's size against its own, about its own centre. A dot is never resized.
        var scale: CGFloat
        /// How much of the colour shows over the star, 0 to 1
        var tint: CGFloat
        /// How far the slot has turned from what it showed into what it will show, 0 to 1
        var morph: CGFloat
        /// True when the two glyphs cross-fade where they are; false when the star shrinks
        /// into its dot or grows out of it, as `StarRatingTransition` draws a new song's
        var crossFades: Bool

        /// The slot as it is when nothing is changing
        static let rest = Pose(scale: 1, tint: 0, morph: 1, crossFades: false)
    }

    /// Slot `index`, `elapsed` seconds into the flourish
    func pose(of index: Int, at elapsed: TimeInterval) -> Pose {
        let since = elapsed - delay(of: index)
        switch kind {
        case .raise where index < lit:
            let blooms = changes(index)
            guard since >= 0 else {
                // Not reached yet: a star the run will light is still what it was
                return blooms ? Pose(scale: 1, tint: 0, morph: 0, crossFades: true) : .rest
            }
            // A half star filling out is already its full size; only a dot has to grow
            let start = blooms && from[index] == .dot ? look.bloomScale : 1
            let scale = keyframes(since, look.popKeys(from: start, isLast: index == lit - 1))
            var tint = 0.0
            if look.tints {
                // Up in a few frames, held while the star overshoots, then cooling as it settles
                tint = since < StarFlourish.tintRiseDuration
                    ? since / StarFlourish.tintRiseDuration
                    : 1 - easeInOut(clamp((since - StarFlourish.tintCoolStart) / StarFlourish.tintCoolDuration))
            }
            return Pose(scale: CGFloat(scale), tint: CGFloat(tint),
                        morph: blooms ? CGFloat(clamp(since / StarFlourish.bloomFadeDuration)) : 1,
                        crossFades: true)
        case .raise, .lower:
            guard changes(index) else { return .rest }
            return Pose(scale: 1, tint: 0, morph: CGFloat(clamp(since / StarFlourish.lowerDuration)), crossFades: false)
        case .fade:
            guard changes(index) else { return .rest }
            return Pose(scale: 1, tint: 0, morph: CGFloat(clamp(since / StarFlourish.fadeDuration)), crossFades: true)
        case .preview:
            guard changes(index) else { return .rest }
            return Pose(scale: 1, tint: 0, morph: CGFloat(clamp(since / StarFlourish.previewDuration)), crossFades: false)
        }
    }

}

// MARK: - Drawing

extension StarFlourish {

    /// The app icon's five bands, top to bottom, which a star flashes in `Look.afterglow`
    static let bandColours: [NSColor] = [rgb(0xFD415D), rgb(0xFE8D39), rgb(0xFEE83A), rgb(0x8BE44A), rgb(0x04CC63)]
    /// Where each band starts down the star, from its top point, 0, to its feet, 1: narrower
    /// in the middle, as the icon's are, since the star is widest there
    static let bandStops: [CGFloat] = [0, 0.29, 0.45, 0.58, 0.74]

    /// The room kept above and below the stars for one that pops past its slot. The image a
    /// flourish is drawn in is this much taller each way than the stars at rest, so centred
    /// where they are, the stars don't move.
    static func headroom(starSize: NSSize) -> CGFloat {
        return (0.18 * starSize.height).rounded(.up)
    }

    /// The size of a flourish's images: as wide as the rating strip, heart slot included, so
    /// they sit exactly where the stars at rest do, and `headroom` taller above and below
    static func imageSize(starSize: NSSize, spacing: CGFloat) -> NSSize {
        return NSSize(width: RatingControl.imageWidth(mode: .rating, starSize: starSize, spacing: spacing),
                      height: starSize.height + 2 * headroom(starSize: starSize))
    }

    /// Slot `index` in an image of `imageSize`, laid out as `Stars.image` lays the stars out
    static func slot(_ index: Int, starSize: NSSize, spacing: CGFloat) -> NSRect {
        return NSRect(x: spacing + CGFloat(index) * (starSize.width + spacing), y: headroom(starSize: starSize),
                      width: starSize.width, height: starSize.height)
    }

    /// The middle of the star drawn in `slot`, which `Star` draws a little below the slot's
    /// own, so that the star's top point and its feet are the same distance from the edges
    static func centre(ofStarIn slot: NSRect) -> CGPoint {
        return CGPoint(x: slot.midX, y: slot.midY - 0.0955 * slot.height * 0.5)
    }

    /// `slot` resized about the star's own centre, so a star that pops grows evenly from its
    /// middle
    static func frame(ofStarIn slot: NSRect, scale: CGFloat) -> NSRect {
        // Exactly the slot at rest, so a flourish's first and last frames are the stars at rest
        guard scale != 1 else { return slot }
        let centre = StarFlourish.centre(ofStarIn: slot)
        return NSRect(x: centre.x + (slot.minX - centre.x) * scale,
                      y: centre.y + (slot.minY - centre.y) * scale,
                      width: slot.width * scale, height: slot.height * scale)
    }

    /// One glyph of a slot: which, where and how opaque
    struct Glyph: Equatable {
        let style: Star.Style
        let frame: NSRect
        let opacity: CGFloat
    }

    /// What slot `index` holds `elapsed` seconds in: one glyph at rest, and two while it turns
    /// from one into the other. The two are added together where they overlap, so the half a
    /// half star shares with a full one stays solid while the other half comes or goes.
    func glyphs(of index: Int, at elapsed: TimeInterval, in slot: NSRect) -> [Glyph] {
        let pose = self.pose(of: index, at: elapsed)
        let source = from[index]
        let target = to[index]
        func glyph(_ style: Star.Style, scale: CGFloat = 1, opacity: CGFloat = 1) -> Glyph {
            return Glyph(style: style,
                         frame: style == .dot ? slot : StarFlourish.frame(ofStarIn: slot, scale: pose.scale * scale),
                         opacity: opacity)
        }
        if source == target || pose.morph >= 1 {
            return [glyph(target)]
        }
        if pose.morph <= 0 {
            return [glyph(source)]
        }
        if source == .dot || target == .dot {
            let turnsToDot = target == .dot
            let star = turnsToDot ? source : target
            if pose.crossFades {
                let dotOpacity = turnsToDot ? pose.morph : 1 - pose.morph
                return [glyph(star, opacity: 1 - dotOpacity), glyph(.dot, opacity: dotOpacity)]
            }
            // As `StarRatingTransition`: the star shrinks towards its dot, and the two blend
            // before the star has less area than the dot, which would pulse
            let eased = StarRollout.ease(Double(pose.morph))
            let amount = turnsToDot ? eased : 1 - eased
            let dotOpacity = StarRollout.ease(Double(amount - 0.65) / 0.35)
            return [glyph(star, scale: 1 - 0.6 * amount, opacity: 1 - dotOpacity), glyph(.dot, opacity: dotOpacity)]
        }
        let fraction = pose.crossFades ? pose.morph : StarRollout.ease(Double(pose.morph))
        return [glyph(source, opacity: 1 - fraction), glyph(target, opacity: fraction)]
    }

    /// The stars `elapsed` seconds in, as a template image of `imageSize`, for whatever colour
    /// the stars at rest are drawn in
    func image(at elapsed: TimeInterval, starSize: NSSize, spacing: CGFloat) -> NSImage {
        let image = NSImage(size: StarFlourish.imageSize(starSize: starSize, spacing: spacing))
        image.lockFocus()
        NSColor.black.set()
        for index in to.indices {
            let slot = StarFlourish.slot(index, starSize: starSize, spacing: spacing)
            StarFlourish.draw(glyphs(of: index, at: elapsed, in: slot), starSize: starSize)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// The colour to draw over `image(at:)` at the same moment, in an image the same size, or
    /// nil while no star is coloured: the stars the flash has reached, in the icon's five
    /// bands, as opaque as the flash is strong. Never a template: its colours are its own.
    func tintImage(at elapsed: TimeInterval, starSize: NSSize, spacing: CGFloat) -> NSImage? {
        guard kind == .raise, look.tints else { return nil }
        let tinted = to.indices.filter { to[$0] != .dot && pose(of: $0, at: elapsed).tint > 0.01 }
        guard !tinted.isEmpty else { return nil }
        let image = NSImage(size: StarFlourish.imageSize(starSize: starSize, spacing: spacing))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            for index in tinted {
                let slot = StarFlourish.slot(index, starSize: starSize, spacing: spacing)
                let stars = glyphs(of: index, at: elapsed, in: slot).filter { $0.style != .dot && $0.opacity > 0.001 }
                guard let first = stars.first else { continue }
                // Each star in a layer of its own: the bands are painted only where that star
                // is, and the layer goes down as opaque as the flash is strong
                context.saveGState()
                context.setAlpha(pose(of: index, at: elapsed).tint)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                NSColor.black.set()
                StarFlourish.composite(stars, starSize: starSize)
                StarFlourish.fillBands(overStarIn: first.frame)
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func draw(_ glyphs: [Glyph], starSize: NSSize) {
        let visible = glyphs.filter { $0.opacity > 0.001 }
        guard let first = visible.first else { return }
        guard visible.count > 1 || first.opacity < 0.999 else {
            Star(size: starSize, style: first.style).image.draw(in: first.frame)
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        composite(visible, starSize: starSize)
        context.endTransparencyLayer()
    }

    /// Draw glyphs that share a slot, adding their opacity where they overlap. Call inside a
    /// transparency layer, so what is added is only these glyphs.
    private static func composite(_ glyphs: [Glyph], starSize: NSSize) {
        for (position, glyph) in glyphs.enumerated() {
            Star(size: starSize, style: glyph.style).image.draw(
                in: glyph.frame, from: .zero, operation: position == 0 ? .sourceOver : .plusLighter,
                fraction: glyph.opacity)
        }
    }

    /// Paint the five bands over whatever has been drawn of the star in `frame`, keeping its
    /// shape and opacity. Each band is painted from its top edge down to the bottom, over the
    /// one before, so where two meet part way through a pixel they blend into each other
    /// rather than into the black underneath.
    private static func fillBands(overStarIn frame: NSRect) {
        let radius = 0.5 * min(frame.width, frame.height)
        let centreY = frame.midY - 0.0955 * radius
        let top = centreY + radius
        let feet = centreY - 0.809 * radius
        let area = frame.insetBy(dx: -2, dy: -2)
        for (band, colour) in bandColours.enumerated() {
            let bandTop = band == 0 ? area.maxY : top - bandStops[band] * (top - feet)
            colour.set()
            NSRect(x: area.minX, y: area.minY, width: area.width, height: bandTop - area.minY).fill(using: .sourceIn)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255,
                       alpha: 1)
    }

}

// MARK: - Easing

private func clamp(_ value: Double) -> Double {
    return min(1, max(0, value))
}

private func easeInOut(_ t: Double) -> Double {
    return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
}

/// The value at `t` on a curve through `keys`, easing in and out between each pair
private func keyframes(_ t: Double, _ keys: [(Double, Double)]) -> Double {
    guard let first = keys.first, let last = keys.last else { return 0 }
    guard t > first.0 else { return first.1 }
    for (from, to) in zip(keys, keys.dropFirst()) where t <= to.0 {
        return from.1 + (to.1 - from.1) * easeInOut((t - from.0) / (to.0 - from.0))
    }
    return last.1
}
