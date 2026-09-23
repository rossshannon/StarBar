import Cocoa

/// Take the stars away, narrow the menu bar item while it is empty, then bring the add
/// button and heart in, already where they stay.
///
/// On macOS 27 the menu bar draws any width change of a status item at the item's old left
/// edge and then slides it into place, with the items to its left, over about a third of a
/// second. Nothing in the app changes that: moving the window has no effect, and narrowing a
/// little on every frame jiggled the heart and clipped the badge. So the width changes once,
/// while nothing is visible, and the new contents appear only after the slide has finished.
struct StarCollapse {
    /// The stars shrink away and the heart fades with them
    static let fadeOutDuration: TimeInterval = 0.2
    /// Measured slide of the narrower item and its neighbours: about 0.33 s
    static let settleDuration: TimeInterval = 0.35
    /// The add button and heart fade in
    static let fadeInDuration: TimeInterval = 0.2
    static let duration = fadeOutDuration + settleDuration + fadeInDuration
    /// Progress at which the item narrows: the stars and heart are gone
    static let shrinkFraction = fadeOutDuration / duration
    /// Progress at which the add button and heart start to fade in
    static let badgeStart = (fadeOutDuration + settleDuration) / duration

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

    /// The heart goes out with the stars and comes back with the add button, so it is never
    /// seen while the menu bar slides the narrower item into place.
    static func heartOpacity(progress: Double) -> CGFloat {
        return progress < badgeStart ? scale(progress: progress) : badgeOpacity(progress: progress)
    }

    /// Whether the item has narrowed yet
    static func hasShrunk(progress: Double) -> Bool {
        return progress >= shrinkFraction
    }

    /// Progress to draw, timing the wait from when the item actually narrowed.
    ///
    /// Synchronous Music reads can hold the main thread for over half a second. Measured on
    /// one clock, a late frame could narrow the item and start the fade-in at once, showing
    /// the badge while the menu bar is still sliding it. So the stars' progress stops at the
    /// narrowing point until the item has narrowed, and the rest is timed from that moment.
    /// - Parameters:
    ///   - elapsed: time since the collapse drew its first frame
    ///   - sinceNarrowing: time since the item narrowed, or nil if it has not yet
    static func progress(elapsed: TimeInterval, sinceNarrowing: TimeInterval?) -> Double {
        guard let sinceNarrowing = sinceNarrowing else {
            return min(max(0, elapsed / duration), shrinkFraction)
        }
        return min(1, shrinkFraction + max(0, sinceNarrowing) / duration)
    }

    /// Content width: the full strip until the stars are gone, then the add button's width
    static func width(from: CGFloat, to: CGFloat, progress: Double) -> CGFloat {
        return hasShrunk(progress: progress) ? to : from
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
            if stars.drawsFavorite && !isFavorited, let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setAlpha(heartOpacity(progress: progress))
                Stars.drawFavoriteHeartOutline(in: NSRect(x: width - size.width,
                                                          y: (rect.height - size.height) * 0.5,
                                                          width: size.width, height: size.height))
                context.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
