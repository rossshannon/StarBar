import Cocoa

/// Changes only the glyphs that differ between two songs, without moving their slots.
struct StarRatingTransition {
    static let duration: TimeInterval = 0.2

    static func shouldAnimate(wasStopped: Bool, isStopped: Bool,
                              previousMode: RatingControl.Mode, mode: RatingControl.Mode,
                              from: Stars, to: Stars) -> Bool {
        return !wasStopped && !isStopped && previousMode == .rating && mode == .rating
            && from.stars.map { $0.style } != to.stars.map { $0.style }
    }

    static func image(from: Stars, to: Stars, progress: Double) -> NSImage {
        let p = StarRollout.ease(progress)
        let height = to.stars.map { $0.size.height }.max() ?? 0
        let heartWidth = to.showsFavorite ? to.spacing + (to.stars.first?.size.width ?? 0) : 0
        let size = NSSize(width: to.starsWidth + heartWidth, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.set()
        for (index, target) in to.stars.enumerated() {
            let source = index < from.stars.count ? from.stars[index] : target
            let rect = NSRect(x: to.spacing + CGFloat(index) * (target.size.width + to.spacing),
                              y: (size.height - target.size.height) * 0.5,
                              width: target.size.width, height: target.size.height)
            if p == 0 {
                source.image.draw(in: rect)
            } else if p == 1 || source.style == target.style {
                target.image.draw(in: rect)
            } else if source.style == .dot || target.style == .dot {
                let shrinking = target.style == .dot
                let amount = shrinking ? p : 1 - p
                let star = shrinking ? source : target
                // Start blending before the star has less area than the dot, avoiding a size pulse.
                let scale = 1 - 0.6 * amount
                let dotOpacity = StarRollout.ease((Double(amount) - 0.65) / 0.35)
                let centre = CGPoint(x: rect.midX, y: rect.midY - 0.0955 * rect.height * 0.5)
                let scaled = NSRect(x: centre.x + (rect.minX - centre.x) * scale,
                                    y: centre.y + (rect.minY - centre.y) * scale,
                                    width: rect.width * scale, height: rect.height * scale)
                blend(star.image, in: scaled, with: Star(size: target.size, style: .dot).image,
                      in: rect, fraction: dotOpacity)
            } else {
                // Add weighted alpha in an isolated layer: the shared half stays opaque.
                blend(source.image, in: rect, with: target.image, in: rect, fraction: p)
            }
        }
        if to.showsFavorite && to.drawsFavorite && !to.isFavorited, let first = to.stars.first {
            Stars.drawFavoriteHeartOutline(in: NSRect(x: to.starsWidth + to.spacing,
                                                      y: (size.height - first.size.height) * 0.5,
                                                      width: first.size.width, height: first.size.height))
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func blend(_ first: NSImage, in firstRect: NSRect,
                              with second: NSImage, in secondRect: NSRect, fraction: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        first.draw(in: firstRect, from: .zero, operation: .sourceOver, fraction: 1 - fraction)
        second.draw(in: secondRect, from: .zero, operation: .plusLighter, fraction: fraction)
        context.endTransparencyLayer()
    }
}
