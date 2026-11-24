//
//  StarFinale.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-24.
//

import Cocoa

/// The extra a song gets when it is given five stars in StarBar: as the stars' flourish
/// (`StarFlourish`) reaches each star, that star throws a small star of its own, in one of the
/// app icon's five colours, with a dot trailing it. They fan out, turn as they fly, and shrink
/// away.
///
/// Ross chose it on 2026-11-24, on top of the one-colour run, from the page of flourishes he
/// was shown the day before (option H there, whose timings these are). Timing and geometry
/// only, so the rules can be tested without a window: the menu bar draws it in a window of its
/// own over the stars (`StarFinaleWindow`), since nothing drawn in the status item can leave
/// it, and the strip in a view beside itself, as each draws the heart's burst. Offsets are
/// from the first star's centre, in points, with y up as AppKit has it.
///
/// The menu bar's small stars fan down, because the screen's top edge is about 12 points above
/// the stars; the strip's fan up, because its panel ends at the strip's bottom edge.
struct StarFinale: Equatable {

    /// Which way the small stars fly
    enum Fan: Equatable {
        /// Down and to the sides, for the menu bar
        case down
        /// Up and to the sides, for the strip
        case up
    }

    static let starCount = 5
    /// How long after the flourish reaches a star its small star leaves
    static let launchDelay: TimeInterval = 0.06
    /// How long each small star flies
    static let flightDuration: TimeInterval = 0.62
    /// How much further each star's small star leans from straight out than its neighbour's,
    /// in radians: the middle star's flies straight out, and the first and last lean 48 degrees
    static let spread: CGFloat = 0.42
    /// How far round from its small star a trailing dot flies, in radians, and how far out, as
    /// a fraction of the small star's distance
    static let trailAngle: CGFloat = 0.32
    static let trailDistance: CGFloat = 0.7
    /// How far a small star turns over its flight, in radians
    static let turn: CGFloat = 2.6

    /// The width of one of the stars being rated
    let starSize: CGFloat
    /// From one star's centre to the next
    let pitch: CGFloat
    /// How far from its star's centre a small star ends up
    let reach: CGFloat
    /// A small star's outer radius at its biggest
    let miniRadius: CGFloat
    /// A trailing dot's radius at its biggest
    let dotRadius: CGFloat
    let fan: Fan
    /// How long after one star the flourish reaches the next (`StarFlourish.Look.stagger`)
    let stagger: TimeInterval

    /// The menu bar's, for stars `starSize` wide (16 points) and `spacing` apart
    static func menuBar(starSize: CGFloat, spacing: CGFloat, stagger: TimeInterval) -> StarFinale {
        return StarFinale(starSize: starSize, pitch: starSize + spacing, reach: starSize * 23 / 16,
                          miniRadius: starSize * 3.4 / 16, dotRadius: starSize * 1.3 / 16,
                          fan: .down, stagger: stagger)
    }

    /// The strip's, for its stars (12 points at scale 1): bigger for their size, since there
    /// is room above them
    static func strip(starSize: CGFloat, spacing: CGFloat, stagger: TimeInterval) -> StarFinale {
        return StarFinale(starSize: starSize, pitch: starSize + spacing, reach: starSize * 2.6,
                          miniRadius: starSize * 0.36, dotRadius: starSize * 1.69 / 12,
                          fan: .up, stagger: stagger)
    }

    /// How long the finale takes, from the start of a flourish whose stars start `stagger`
    /// apart: the last star's small star is the last to go
    static func duration(stagger: TimeInterval) -> TimeInterval {
        return TimeInterval(starCount - 1) * stagger + launchDelay + flightDuration
    }

    var duration: TimeInterval {
        return StarFinale.duration(stagger: stagger)
    }

    /// One thing in the air: a small star, or the dot that trails it
    struct Piece: Equatable {
        /// Which star threw it, 0 to 4, for its colour
        var star: Int
        /// True for the small star, false for its dot
        var isStar: Bool
        /// Its centre, from the first star's centre
        var offset: CGVector
        /// The small star's outer radius, or the dot's radius
        var radius: CGFloat
        /// How far the small star has turned, in radians, anticlockwise
        var rotation: CGFloat
    }

    /// How far a small star leaves from its star's centre
    private var launchDistance: CGFloat {
        return starSize * 5 / 16
    }

    /// How far a small star has fallen by the end of its flight, whichever way it flew
    var drop: CGFloat {
        return starSize / 4
    }

    /// How far star `star`'s small star leans from straight out, in radians, positive to the
    /// left: the first star's flies left, the last one's right
    func lean(of star: Int) -> CGFloat {
        return CGFloat(2 - star) * StarFinale.spread
    }

    /// What is in the air `elapsed` seconds into the flourish: nothing before the first small
    /// star leaves, and nothing once the last has shrunk away
    func pieces(at elapsed: TimeInterval) -> [Piece] {
        var pieces: [Piece] = []
        for star in 0..<StarFinale.starCount {
            let since = elapsed - TimeInterval(star) * stagger - StarFinale.launchDelay
            let progress = since / StarFinale.flightDuration
            guard progress > 0, progress < 1 else { continue }
            let distance = launchDistance + (reach - launchDistance) * CGFloat(easeOutQuart(progress))
            // Out at half size and full within a few frames; shrinking away over the second half
            let grow = CGFloat(0.5 + 0.5 * easeOutCubic(clamp(progress / 0.15)))
            let shrink = CGFloat(progress < 0.45 ? 1 : 1 - easeInOut((progress - 0.45) / 0.55))
            let fall = drop * CGFloat(progress * progress)
            let centre = CGFloat(star) * pitch
            let lean = self.lean(of: star)
            let direction: CGFloat = star % 2 == 0 ? 1 : -1
            pieces.append(Piece(star: star, isStar: true,
                                offset: offset(from: centre, distance: distance, lean: lean, fall: fall),
                                radius: miniRadius * grow * shrink,
                                rotation: direction * StarFinale.turn * CGFloat(progress)))
            let trailLean = lean + (fan == .down ? StarFinale.trailAngle : -StarFinale.trailAngle)
            pieces.append(Piece(star: star, isStar: false,
                                offset: offset(from: centre, distance: distance * StarFinale.trailDistance,
                                               lean: trailLean, fall: fall),
                                radius: dotRadius * shrink, rotation: 0))
        }
        return pieces
    }

    private func offset(from centre: CGFloat, distance: CGFloat, lean: CGFloat, fall: CGFloat) -> CGVector {
        let out = distance * cos(lean)
        return CGVector(dx: centre - distance * sin(lean), dy: (fan == .up ? out : -out) - fall)
    }

    /// The rectangle about the first star's centre that holds everything the finale draws, so
    /// a view can be sized to hold it all. Against the fan it reaches only a small star's
    /// radius: the menu bar's pieces never rise above the stars, towards the screen's edge.
    var bounds: NSRect {
        let side = reach * sin(2 * StarFinale.spread) + miniRadius
        let far = reach + miniRadius + (fan == .down ? drop : 0)
        let near = miniRadius
        return NSRect(x: -side, y: fan == .down ? -far : -near,
                      width: CGFloat(StarFinale.starCount - 1) * pitch + 2 * side, height: far + near)
    }

    /// The app icon's five bands, top to bottom: one to each star's small star, first to
    /// last, and each dot in the colour two along, so no pair is one colour
    static let colours: [NSColor] = StarFlourish.bandColours

    static func colour(of piece: Piece) -> NSColor {
        return colours[(piece.isStar ? piece.star : piece.star + 2) % colours.count]
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
