//
//  TrackAnnouncementSleeve.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-02.
//

import Foundation
import CoreGraphics
import QuartzCore

/// The break-out sleeve: a cover bigger than Growl's, turned to face the text and rising out
/// of the top of the strip into the panel's empty headroom, which tips towards the pointer when
/// it comes near. Geometry and timing only, so the rules can be tested without a window;
/// `TrackAnnouncementSleeveView` draws it and `TrackAnnouncementPanel` steps it.
///
/// Ross chose it on 2026-11-02 from a page of true-size mock-ups of ten treatments ("Break-out
/// with pointer tilt"), over a flat sleeve, a glow, a tossed sleeve, a record peeking out and
/// others.
enum TrackAnnouncementSleeve {

    /// The sleeve's side at scale 1; the strip's flat artwork is 80
    static let size: CGFloat = 112
    /// Gap under the sleeve, the same 12 the flat artwork keeps. With the strip 104 tall, the
    /// sleeve stands 20 points above its top edge.
    static let bottomInset: CGFloat = 12
    /// Where the text starts, measured from the sleeve's left edge: the leaning sleeve's right
    /// edge lands about 107 points in, and the strip's usual 16 point gap follows
    static let textOffset: CGFloat = 124
    static let cornerRadius: CGFloat = 7
    /// The turn about the upright axis that faces the sleeve towards the text, in degrees
    static let lean: CGFloat = 18
    /// How far the eye is from the sleeve, in points at scale 1; Core Animation's m34 is -1
    /// over this. Nearer exaggerates the perspective.
    static let eyeDistance: CGFloat = 420
    /// Room the sleeve's view keeps on every side for the turn, the tilt, the rise and the
    /// shadow. The sleeve and this fill the panel's 48 point headroom exactly:
    /// 12 + 112 + 28 = 104 + 48.
    static let margin: CGFloat = 28

    static let shadowOpacity: Float = 0.55
    static let shadowRadius: CGFloat = 5
    /// Down and a little to the left, away from the text the sleeve faces
    static let shadowOffset = CGSize(width: -3, height: -6)
    /// The hairline that keeps a pale sleeve's edge against a pale backdrop
    static let rimAlpha: CGFloat = 0.22
    static let rimWidth: CGFloat = 0.5

    /// The sleeve's square in the strip before it turns, in the strip's coordinates.
    /// `leadingX` is where the flat artwork would start: the Dock and glass insets plus 12.
    static func slot(leadingX: CGFloat, scale: CGFloat = 1) -> CGRect {
        return CGRect(x: leadingX, y: bottomInset * scale, width: size * scale, height: size * scale)
    }

    // MARK: - Pointer tilt

    /// The most the pointer turns the sleeve, each way about each axis, in degrees. About the
    /// upright axis that is 8 to 28 with the lean, so it never turns away from the text.
    static let maxTilt: CGFloat = 10
    /// The pointer's distance from the sleeve's centre that gives the whole tilt, in points at
    /// scale 1
    static let tiltSpan: CGFloat = 140
    /// Beyond this the pointer is ignored: the see-through hole's radius
    static let tiltReach: CGFloat = 270
    /// How quickly the sleeve follows the pointer: the time constant of an exponential approach,
    /// so the motion is the same at any display rate
    static let tiltResponse: TimeInterval = 0.08
    /// The glare's peak opacity, white
    static let glareAlpha: CGFloat = 0.38
    /// The pointer's offset that puts the glare's centre at the sleeve's edge
    static let glareSpan: CGFloat = 90

    struct Tilt: Equatable {
        /// Turn about the horizontal axis, in degrees: positive brings the top edge towards
        /// the viewer, negative tips it away so the sleeve faces up
        var x: CGFloat = 0
        /// Turn about the upright axis on top of the lean, in degrees: positive turns it further
        /// towards the text
        var y: CGFloat = 0
        /// How strongly the glare shows, 0 to 1
        var glare: CGFloat = 0
        /// The glare's centre on the sleeve, 0 to 1 across and up from the bottom left
        var glareCentre = CGPoint(x: 0.5, y: 1)

        static let rest = Tilt()
    }

    /// The tilt for a pointer `offset` from the sleeve's centre, in points at scale 1 with y
    /// up, as AppKit's screen coordinates have it. The sleeve turns to face the pointer: all
    /// the way once the pointer is `tiltSpan` off in either direction, fading out between a
    /// third of the way to `tiltReach` and `tiltReach` itself, so it settles before the pointer
    /// leaves.
    static func tilt(pointerOffset offset: CGVector) -> Tilt {
        let distance = hypot(offset.dx, offset.dy)
        let near = min(1, max(0, (1 - distance / tiltReach) * 3))
        guard near > 0 else { return .rest }
        func unit(_ value: CGFloat) -> CGFloat {
            return min(1, max(-1, value))
        }
        return Tilt(
            x: -unit(offset.dy / tiltSpan) * maxTilt * near,
            y: unit(offset.dx / tiltSpan) * maxTilt * near,
            glare: near,
            glareCentre: CGPoint(
                x: 0.5 + unit(offset.dx / glareSpan) * 0.5,
                y: 0.5 + unit(offset.dy / glareSpan) * 0.5
            )
        )
    }

    /// One step of the sleeve following `target` over `elapsed` seconds. Exponential, so two
    /// half steps land where one whole step does and a late display tick catches up rather
    /// than lagging. Snaps the last hundredth of a degree, so it comes to rest and the panel
    /// can stop setting the transform.
    static func approach(_ current: Tilt, toward target: Tilt, elapsed: TimeInterval) -> Tilt {
        let k = CGFloat(1 - exp(-max(0, elapsed) / tiltResponse))
        func step(_ from: CGFloat, _ to: CGFloat, within snap: CGFloat) -> CGFloat {
            let next = from + (to - from) * k
            return abs(to - next) < snap ? to : next
        }
        return Tilt(
            x: step(current.x, target.x, within: 0.01),
            y: step(current.y, target.y, within: 0.01),
            glare: step(current.glare, target.glare, within: 0.002),
            glareCentre: CGPoint(
                x: step(current.glareCentre.x, target.glareCentre.x, within: 0.001),
                y: step(current.glareCentre.y, target.glareCentre.y, within: 0.001)
            )
        )
    }

    // MARK: - Turning

    /// The sleeve's transform about its centre: the rise's scale, the lean and the pointer's
    /// turn about the upright axis, the pointer's tip about the horizontal one, then the
    /// perspective, whose eye moves back as the strip grows so the look is the same at any scale
    static func transform(_ tilt: Tilt, scale: CGFloat = 1, riseScale: CGFloat = 1) -> CATransform3D {
        let radians = CGFloat.pi / 180
        var result = CATransform3DMakeScale(riseScale, riseScale, 1)
        result = CATransform3DConcat(result, CATransform3DMakeRotation((lean + tilt.y) * radians, 0, 1, 0))
        result = CATransform3DConcat(result, CATransform3DMakeRotation(tilt.x * radians, 1, 0, 0))
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (eyeDistance * max(scale, 0.01))
        return CATransform3DConcat(result, perspective)
    }

    /// Where `point`, relative to the sleeve's centre and in its plane, lands on screen after
    /// `transform`, as Core Animation projects it
    static func project(_ point: CGPoint, through transform: CATransform3D) -> CGPoint {
        let x = point.x * transform.m11 + point.y * transform.m21 + transform.m41
        let y = point.x * transform.m12 + point.y * transform.m22 + transform.m42
        let w = point.x * transform.m14 + point.y * transform.m24 + transform.m44
        return CGPoint(x: x / w, y: y / w)
    }

    /// The smallest rectangle around a sleeve of `size` once turned and projected, relative to
    /// its centre
    static func projectedBounds(of size: CGSize, tilt: Tilt, scale: CGFloat = 1, riseScale: CGFloat = 1) -> CGRect {
        let transform = self.transform(tilt, scale: scale, riseScale: riseScale)
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let corners = [
            CGPoint(x: -halfWidth, y: -halfHeight),
            CGPoint(x: halfWidth, y: -halfHeight),
            CGPoint(x: halfWidth, y: halfHeight),
            CGPoint(x: -halfWidth, y: halfHeight),
        ].map { project($0, through: transform) }
        let xs = corners.map { $0.x }
        let ys = corners.map { $0.y }
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    // MARK: - Rise

    /// After the strip starts to slide in, the sleeve waits this long, then comes up out of the
    /// strip over `riseDuration`
    static let riseDelay: TimeInterval = 0.2
    static let riseDuration: TimeInterval = 0.45
    /// How far below its place the sleeve starts, at scale 1, and how small
    static let riseDistance: CGFloat = 26
    static let riseStartScale: CGFloat = 0.9
    /// How far the rise overshoots before it settles: the back-ease's constant
    static let riseOvershoot: Double = 1.4

    /// How far through its rise the sleeve is `elapsed` seconds after the strip starts to slide
    /// in: 0 sunk into the strip until `riseDelay`, then up, a little past its place, and back
    /// to exactly 1 at the end
    static func rise(elapsed: TimeInterval) -> CGFloat {
        let t = min(1, max(0, (elapsed - riseDelay) / riseDuration))
        let u = t - 1
        let overshoot = riseOvershoot
        return CGFloat(1 + (overshoot + 1) * u * u * u + overshoot * u * u)
    }

    /// The scale for a rise of `progress`: `riseStartScale` sunk, 1 in place
    static func riseScale(_ progress: CGFloat) -> CGFloat {
        return riseStartScale + (1 - riseStartScale) * progress
    }

    /// How far below its place the sleeve is for a rise of `progress`, at `scale`
    static func riseDrop(_ progress: CGFloat, scale: CGFloat = 1) -> CGFloat {
        return (1 - progress) * riseDistance * scale
    }
}

/// Switches for the break-out sleeve, read from defaults each time the strip appears, so either
/// part can be turned off without a rebuild: `announcementBreakout` (bool; true by default,
/// false puts the flat 80 point artwork back in the strip) and `announcementSleeveTilt` (bool;
/// true by default, false keeps the sleeve still when the pointer comes near).
struct TrackAnnouncementSleeveKnobs: Equatable {
    var breakout = true
    var tilt = true

    /// Where the panel gets its knobs. The tests are hosted in the app, so they replace this
    /// with fixed values rather than read whatever is set on the machine.
    static var read: () -> TrackAnnouncementSleeveKnobs = { current }

    static var current: TrackAnnouncementSleeveKnobs {
        let defaults = UserDefaults.standard
        var knobs = TrackAnnouncementSleeveKnobs()
        if defaults.object(forKey: "announcementBreakout") != nil {
            knobs.breakout = defaults.bool(forKey: "announcementBreakout")
        }
        if defaults.object(forKey: "announcementSleeveTilt") != nil {
            knobs.tilt = defaults.bool(forKey: "announcementSleeveTilt")
        }
        return knobs
    }
}
