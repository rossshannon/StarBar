import Cocoa

/// Shrink the old rating before introducing the add button. The heart stays at the right
/// edge while the add button follows the left edge as the gap closes.
struct StarCollapse {
    static let duration: TimeInterval = 0.35
    static let shrinkFraction = 0.15 / duration
    static let badgeStart = 0.55

    static func shouldCollapse(wasStopped: Bool, isStopped: Bool,
                               previousMode: RatingControl.Mode, mode: RatingControl.Mode) -> Bool {
        return !wasStopped && !isStopped && previousMode == .rating && mode == .addToLibrary
    }

    static func scale(progress: Double) -> CGFloat {
        return 1 - StarRollout.ease(progress / shrinkFraction)
    }

    static func showsBadge(progress: Double) -> Bool {
        return badgeOpacity(progress: progress) > 0
    }

    static func badgeOpacity(progress: Double) -> CGFloat {
        return StarRollout.ease((progress - badgeStart) / (1 - badgeStart))
    }

    static func width(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        // Keep the template heart on whole points while its image changes width.
        return (from + (to - from) * StarRollout.ease(progress)).rounded()
    }

    static func image(stars: Stars, width: CGFloat, progress: Double,
                      isFavorited: Bool, isPending: Bool = false) -> NSImage {
        let size = stars.stars.first?.size ?? NSSize(width: 16, height: 16)
        let image = NSImage(size: NSSize(width: width, height: size.height + 4), flipped: false) { rect in
            NSColor.black.set()
            if showsBadge(progress: progress) {
                // Leave its heart slot empty; draw the heart at the live right edge below.
                let badge = AddToLibraryBadge(glyphSize: size, spacing: stars.spacing,
                                               isFavorited: true, isPending: isPending).image
                badge.draw(in: NSRect(x: 0, y: (rect.height - size.height) * 0.5,
                                      width: badge.size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: badgeOpacity(progress: progress))
            } else if let context = NSGraphicsContext.current?.cgContext {
                let scale = scale(progress: progress)
                if scale > 0 {
                    for (index, star) in stars.stars.enumerated() {
                        NSGraphicsContext.saveGraphicsState()
                        let fullWidth = stars.starsWidth + stars.spacing + size.width
                        let contraction = max(0, fullWidth - width)
                        let slotFraction = CGFloat(index) / CGFloat(max(1, stars.stars.count - 1))
                        context.translateBy(x: stars.spacing + CGFloat(index) * (size.width + stars.spacing)
                                            + size.width * 0.5 - contraction * slotFraction,
                                            y: rect.midY - 0.0955 * size.height * 0.5)
                        context.scaleBy(x: scale, y: scale)
                        star.image.draw(in: NSRect(x: -size.width * 0.5,
                                                   y: -size.height * 0.5 + 0.0955 * size.height * 0.5,
                                                   width: size.width, height: size.height))
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
            }
            if stars.drawsFavorite && !isFavorited {
                Stars.drawFavoriteHeartOutline(in: NSRect(x: width - size.width,
                                                          y: (rect.height - size.height) * 0.5,
                                                          width: size.width, height: size.height))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
