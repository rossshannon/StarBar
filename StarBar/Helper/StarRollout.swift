import Cocoa

/// Display-only motion from the stopped dot or add button to the rating strip. Positions are measured
/// from the right edge, which stays still while the status item grows to the left.
struct StarRollout {
    static let duration: TimeInterval = 1.0
    static let travelDuration = 0.78
    static let stagger = 0.055

    /// How long a widened item is left empty before the first star shows.
    ///
    /// macOS 27 first draws a status item that has widened a long way over the items to its
    /// right, and then slides it into place. Measured 2026-10-22, going from the 32 pt dot to
    /// the 148 pt strip, the first star showed over the neighbouring icon for 3 to 4 frames;
    /// measured 2026-11-12 on macOS 27.2, going from Spotify's 52 pt heart, for 7 and 8 frames
    /// at 60 Hz in two recordings (0.12 to 0.13 s, from the frame the item widened, the star
    /// starting two icons to the right). So the stars wait nine frames for that slide, as the
    /// add button waits for the slide of a narrowed item (`StarCollapse.settleDuration`). The
    /// wait is counted from the widening, and a new song's first frame usually comes later
    /// than this anyway, behind the Music reads the song sets off (0.4 to 0.6 s later in
    /// eight rollouts from the stopped dot that day), so it is only a wait when the frame
    /// would have come too soon: after Spotify's heart has faded, which widens the item on a
    /// frame of the transition itself.
    static let settleDuration: TimeInterval = 0.15

    /// How far a rollout's stars have rolled: nowhere until the widened item has been left
    /// `settleDuration` to be put in its place, and then over `duration`.
    struct Schedule {
        /// How long the transition had run, as drawn, when the stars started to roll
        private var rollStart: TimeInterval?

        /// - Parameters:
        ///   - elapsed: how long the transition has run, as drawn
        ///   - sinceWidening: time on the clock since the item widened, or nil if it has not yet
        mutating func progress(elapsed: TimeInterval, sinceWidening: TimeInterval?) -> Double {
            if rollStart == nil, let sinceWidening = sinceWidening, sinceWidening >= StarRollout.settleDuration {
                rollStart = elapsed
            }
            guard let rollStart = rollStart else { return 0 }
            return min(1, max(0, (elapsed - rollStart) / StarRollout.duration))
        }
    }

    static func shouldRoll(wasStopped: Bool, isStopped: Bool,
                           previousMode: RatingControl.Mode, mode: RatingControl.Mode) -> Bool {
        return !isStopped && mode == .rating && (wasStopped || previousMode == .addToLibrary || previousMode == .spotify)
    }

    struct Pose {
        let x: CGFloat
        let angle: CGFloat
        let opacity: CGFloat
    }

    static func ease(_ progress: Double) -> CGFloat {
        let p = CGFloat(min(1, max(0, progress)))
        return p * p * (3 - 2 * p)
    }

    static func width(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        return from + (to - from) * ease(progress / travelDuration)
    }

    static func pose(index: Int, starSize: NSSize, spacing: CGFloat,
                     imageWidth: CGFloat, progress: Double) -> Pose {
        let finalWidth = RatingControl.imageWidth(mode: .rating, starSize: starSize, spacing: spacing)
        let destination = spacing + CGFloat(index) * (starSize.width + spacing)
        let source = finalWidth - starSize.width
        let local = (progress - Double(index) * stagger) / travelDuration
        let remaining = (source - destination) * (1 - ease(local))
        return Pose(x: destination + remaining - (finalWidth - imageWidth),
                    angle: -remaining / (starSize.width * 0.5),
                    opacity: ease(local / 0.12))
    }

    static func heartOpacity(progress: Double) -> CGFloat {
        return ease((progress - 0.65) / 0.35)
    }

    /// How long a heart already showing (Spotify's) takes to fade out before the rollout
    static let outgoingHeartFadeDuration: TimeInterval = 0.2

    /// That heart's opacity, `progress` running 0 to 1 over `outgoingHeartFadeDuration`
    static func outgoingHeartOpacity(progress: Double) -> CGFloat {
        return 1 - ease(progress)
    }

    /// A template image lets AppKit retain the menu bar's normal light/dark appearance.
    /// The extra vertical room prevents the rotated star tips being clipped.
    static func image(stars: Stars, width: CGFloat, progress: Double) -> NSImage {
        let height = (stars.stars.first?.size.height ?? 16) + 4
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.black.set()
            for (index, star) in stars.stars.enumerated() {
                let pose = pose(index: index, starSize: star.size, spacing: stars.spacing,
                                imageWidth: width, progress: progress)
                NSGraphicsContext.saveGraphicsState()
                let transform = AffineTransform(
                    translationByX: pose.x + star.size.width * 0.5,
                    byY: rect.midY - 0.0955 * star.size.height * 0.5)
                var rotation = transform
                rotation.rotate(byRadians: pose.angle)
                (rotation as NSAffineTransform).concat()
                star.image.draw(in: NSRect(x: -star.size.width * 0.5,
                                           y: -star.size.height * 0.5 + 0.0955 * star.size.height * 0.5,
                                           width: star.size.width, height: star.size.height),
                                from: .zero, operation: .sourceOver, fraction: pose.opacity)
                NSGraphicsContext.restoreGraphicsState()
            }
            if stars.drawsFavorite && !stars.isFavorited, let star = stars.stars.first {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(heartOpacity(progress: progress))
                Stars.drawFavoriteHeartOutline(in: NSRect(x: width - star.size.width,
                                                          y: (height - star.size.height) * 0.5,
                                                          width: star.size.width, height: star.size.height))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
