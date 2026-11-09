//
//  HeartBurst.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-09.
//

import Cocoa

/// How the heart changes when the user sets or clears it in StarBar. Timing only, so the
/// rules can be tested without a window: `MenuBarRatingControl` steps the menu bar's heart,
/// `HeartBurstView` draws the strip's and the burst, and both step on a display link.
///
/// Ross chose it on 2026-11-09 from a page of true-size mock-ups (option B, "Burst", with D,
/// its echo on the strip), after asking for the juice of Twitter's heart: until then the heart
/// changed from outline to red in a single frame.
enum HeartChange: Equatable {

    /// Set: the outline shrinks away, a ring swells and hollows (`HeartBurst`), and the filled
    /// heart pops through it with a little overshoot while dots fly out
    case burst
    /// Cleared: the heart dips and comes back as an outline. Never a burst, as Twitter's isn't.
    case dip
    /// Set or cleared under Reduce Motion: a cross-fade, with no change of size and no dots
    case fade

    init(favorited: Bool, reduceMotion: Bool) {
        if reduceMotion {
            self = .fade
        } else {
            self = favorited ? .burst : .dip
        }
    }

    var duration: TimeInterval {
        switch self {
        case .burst: return HeartBurst.duration
        case .dip: return HeartChange.dipDuration
        case .fade: return HeartChange.fadeDuration
        }
    }

    static let dipDuration: TimeInterval = 0.24
    /// How small the heart gets at the bottom of the dip
    static let dipScale: CGFloat = 0.78
    static let fadeDuration: TimeInterval = 0.15
    /// How long the outline takes to shrink away at the start of a burst
    static let outlineShrinkDuration: TimeInterval = 0.1

    /// The heart being replaced, `elapsed` seconds in
    func outgoing(at elapsed: TimeInterval) -> HeartGlyph {
        switch self {
        case .burst:
            let shrink = 1 - easeOutCubic(clamp(elapsed / HeartChange.outlineShrinkDuration))
            return HeartGlyph(scale: CGFloat(shrink), opacity: 1)
        case .dip:
            return HeartGlyph(scale: HeartChange.dipped(at: elapsed), opacity: CGFloat(1 - clamp(elapsed / 0.12)))
        case .fade:
            return HeartGlyph(scale: 1, opacity: CGFloat(1 - clamp(elapsed / HeartChange.fadeDuration)))
        }
    }

    /// The heart taking its place
    func incoming(at elapsed: TimeInterval) -> HeartGlyph {
        switch self {
        case .burst:
            return HeartGlyph(scale: HeartBurst.popScale(at: elapsed), opacity: 1)
        case .dip:
            return HeartGlyph(scale: HeartChange.dipped(at: elapsed), opacity: CGFloat(clamp((elapsed - 0.06) / 0.12)))
        case .fade:
            return HeartGlyph(scale: 1, opacity: CGFloat(clamp(elapsed / HeartChange.fadeDuration)))
        }
    }

    /// Both hearts shrink together to the bottom of the dip and come back
    private static func dipped(at elapsed: TimeInterval) -> CGFloat {
        return CGFloat(keyframes(elapsed, [(0, 1), (0.1, Double(dipScale)), (dipDuration, 1)]))
    }

}

/// One of the two hearts drawn while the heart changes: its size, as a fraction of the
/// heart's own, and its opacity
struct HeartGlyph: Equatable {

    var scale: CGFloat
    var opacity: CGFloat

    /// The heart as it is when nothing is changing
    static let rest = HeartGlyph(scale: 1, opacity: 1)

    var isVisible: Bool {
        return scale > 0.001 && opacity > 0.001
    }

    /// `rect` grown or shrunk by `scale` about its centre
    func frame(for rect: NSRect) -> NSRect {
        let width = rect.width * scale
        let height = rect.height * scale
        return NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

}

/// The burst itself, after Twitter's heart: a circle swells from nothing around the heart and
/// turns from red to violet, a hole opens in it until the ring has gone, and seven pairs of dots
/// fly out from its edge and shrink away. Offsets are from the heart's centre, in points, with
/// y up as AppKit has it.
///
/// The menu bar's dots fan down and to the sides rather than all the way round, because the
/// screen's top edge is only 12 points above the heart on a 24 point menu bar; the strip's fan
/// up, because its panel ends at the strip's bottom edge.
struct HeartBurst: Equatable {

    static let duration: TimeInterval = 0.8
    /// When the filled heart starts to pop through the ring
    static let popStart: TimeInterval = 0.22
    /// The ring's widest radius, as a fraction of the heart's size
    static let ringScale: CGFloat = 0.82
    static let pairCount = 7
    /// How far round from its lead the trailing dot of a pair sits, in radians
    static let trailAngle: CGFloat = 0.26
    /// How far out the trailing dot is, as a fraction of its lead's distance
    static let trailDistance: CGFloat = 0.8

    /// The directions the dots fly in: `span` radians about `centre`, measured from the
    /// positive x axis with y up, one pair at each end and the rest evenly between
    struct Fan: Equatable {
        var centre: CGFloat
        var span: CGFloat

        /// Down and to the sides, for the menu bar. The last pair flies 10° above level, whose
        /// trailing dot rises 10.6 points at most, under the 12 points to the screen's edge.
        static let down = Fan(centre: -.pi / 2, span: 200 * .pi / 180)
        /// Up and to the sides, for the strip, whose panel ends at its bottom edge
        static let up = Fan(centre: .pi / 2, span: 200 * .pi / 180)
    }

    /// The heart's width
    let heartSize: CGFloat
    /// How far from the heart's centre the lead dots end up
    let reach: CGFloat
    /// The dots' size, against Twitter's proportions for a 16 point heart
    var dotScale: CGFloat = 1
    /// Nil sends the dots all the way round
    var fan: Fan?

    /// The menu bar's burst, for a heart `heartSize` wide (16 points)
    static func menuBar(heartSize: CGFloat) -> HeartBurst {
        return HeartBurst(heartSize: heartSize, reach: heartSize * 27 / 16, dotScale: 1, fan: .down)
    }

    /// The strip's burst, for its heart (12 points at scale 1): bigger for its size, since there
    /// is room above the strip
    static func strip(heartSize: CGFloat) -> HeartBurst {
        return HeartBurst(heartSize: heartSize, reach: heartSize * 44 / 12, dotScale: 1.9, fan: .up)
    }

    struct Ring: Equatable {
        var outerRadius: CGFloat
        var innerRadius: CGFloat
        /// From the heart's colour, 0, to the ring's last, 1
        var colourMix: CGFloat
    }

    struct Dot: Equatable {
        /// From the heart's centre
        var offset: CGVector
        var radius: CGFloat
        /// Which of the seven pairs, and whether this is its lead dot, for the colour
        var pair: Int
        var isLead: Bool
    }

    private var ringRadius: CGFloat {
        return HeartBurst.ringScale * heartSize
    }

    var leadDotRadius: CGFloat {
        return 2.3 * heartSize / 16 * dotScale
    }

    var trailDotRadius: CGFloat {
        return 1.5 * heartSize / 16 * dotScale
    }

    /// How far from the heart's centre anything is drawn, so a view can be sized to hold it all
    var extent: CGFloat {
        return max(ringRadius, reach + leadDotRadius)
    }

    /// The ring, `elapsed` seconds in: nil before it starts and once its hole has eaten it
    func ring(at elapsed: TimeInterval) -> Ring? {
        guard elapsed > 0, elapsed < 0.4 else { return nil }
        let outer = ringRadius * CGFloat(easeOutCubic(clamp(elapsed / 0.24)))
        let inner = ringRadius * CGFloat(easeOutCubic(clamp((elapsed - 0.13) / 0.24)))
        guard outer - inner > 0.15 else { return nil }
        return Ring(outerRadius: outer, innerRadius: min(inner, outer), colourMix: CGFloat(clamp(elapsed / 0.26)))
    }

    /// The dots, `elapsed` seconds in: none before they leave the ring or once they have shrunk
    /// away
    func dots(at elapsed: TimeInterval) -> [Dot] {
        let progress = (elapsed - 0.2) / 0.6
        guard progress > 0, progress < 1 else { return [] }
        let distance = ringRadius * 0.9 + (reach - ringRadius * 0.9) * CGFloat(easeOutQuart(progress))
        let shrink = CGFloat(progress < 0.45 ? 1 : 1 - easeInOut((progress - 0.45) / 0.55))
        var dots: [Dot] = []
        for pair in 0..<HeartBurst.pairCount {
            let direction = angle(ofPair: pair)
            dots.append(Dot(offset: CGVector(dx: distance * cos(direction), dy: distance * sin(direction)),
                            radius: leadDotRadius * shrink, pair: pair, isLead: true))
            let trailAngle = direction + HeartBurst.trailAngle
            let trailDistance = distance * HeartBurst.trailDistance
            dots.append(Dot(offset: CGVector(dx: trailDistance * cos(trailAngle), dy: trailDistance * sin(trailAngle)),
                            radius: trailDotRadius * shrink, pair: pair, isLead: false))
        }
        return dots
    }

    /// The direction pair `pair` flies in
    private func angle(ofPair pair: Int) -> CGFloat {
        let count = CGFloat(HeartBurst.pairCount)
        guard let fan = fan else {
            return .pi / 2 + CGFloat(pair) * 2 * .pi / count
        }
        return fan.centre - fan.span / 2 + CGFloat(pair) * fan.span / (count - 1)
    }

    /// The filled heart's size as it pops through the ring: nothing until `popStart`, then up
    /// past full size, back under it, and settled by 0.74 s
    static func popScale(at elapsed: TimeInterval) -> CGFloat {
        let since = elapsed - popStart
        guard since > 0 else { return 0 }
        return CGFloat(keyframes(since, [(0, 0), (0.16, 1.28), (0.3, 0.9), (0.42, 1.05), (0.52, 1)]))
    }

}

/// The burst's colours. The ring starts in the heart's own colour; the dots go in pairs.
struct HeartBurstPalette {

    let ringStart: NSColor
    let ringEnd: NSColor
    /// Seven pairs, lead and trailing dot
    let pairs: [(lead: NSColor, trail: NSColor)]

    func ringColour(mix: CGFloat) -> NSColor {
        return ringStart.blended(withFraction: mix, of: ringEnd) ?? ringStart
    }

    func colour(of dot: HeartBurst.Dot) -> NSColor {
        let pair = pairs[dot.pair % pairs.count]
        return dot.isLead ? pair.lead : pair.trail
    }

    /// Music's red heart, to violet, with bright dots that show on a light wallpaper as well
    /// as a dark one, since the menu bar has no background of its own on macOS 26 and later
    static let music = HeartBurstPalette(
        ringStart: Stars.favoriteHeartColor,
        ringEnd: rgb(0xB66DF2),
        pairs: [(rgb(0xFF4F7B), rgb(0xFFA63D)), (rgb(0x9B6BFF), rgb(0x3FB3FF)), (rgb(0x21C987), rgb(0xF2C21B)),
                (rgb(0xFF5A4E), rgb(0xC06BFF)), (rgb(0x3FA6FF), rgb(0x4FD6A8)), (rgb(0xFF8A1F), rgb(0xFF5FA2)),
                (rgb(0xA07BFF), rgb(0x3CC6EE))]
    )

    /// Spotify's green heart, in greens, teals and a little yellow
    static let spotify = HeartBurstPalette(
        ringStart: Stars.spotifyHeartColor,
        ringEnd: rgb(0x0FB39C),
        pairs: [(rgb(0x1ED760), rgb(0xA8E62A)), (rgb(0x0FB39C), rgb(0x5FE3A0)), (rgb(0x8ED84A), rgb(0xF2C21B)),
                (rgb(0x18C4B0), rgb(0x1ED760)), (rgb(0xA8E62A), rgb(0x3FA6FF)), (rgb(0x5FE3A0), rgb(0x159E4C)),
                (rgb(0xF2C21B), rgb(0x18C4B0))]
    )

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

private func easeOutCubic(_ t: Double) -> Double {
    return 1 - pow(1 - t, 3)
}

private func easeOutQuart(_ t: Double) -> Double {
    return 1 - pow(1 - t, 4)
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
