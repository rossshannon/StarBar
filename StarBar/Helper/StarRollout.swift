import Cocoa

/// Display-only motion from the stopped dot or add button to the rating strip. Positions are measured
/// from the right edge, which stays still while the status item grows to the left.
struct StarRollout {
    static let duration: TimeInterval = 1.0
    static let travelDuration = 0.78
    static let stagger = 0.055

    static func shouldRoll(wasStopped: Bool, isStopped: Bool,
                           previousMode: RatingControl.Mode, mode: RatingControl.Mode) -> Bool {
        return !isStopped && mode == .rating && (wasStopped || previousMode == .addToLibrary)
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
