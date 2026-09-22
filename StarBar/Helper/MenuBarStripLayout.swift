import Cocoa

/// Keep the menu bar allocation fixed while the visible content expands or contracts.
/// Resizing the native item on macOS 27 moves its displayed contents independently
/// of the local view frames, so an anchored child view alone cannot keep the heart still.
struct MenuBarStripLayout {
    static let edgeInset: CGFloat = 4
    let imageWidth: CGFloat

    init(starSize: NSSize, spacing: CGFloat) {
        imageWidth = RatingControl.imageWidth(mode: .rating, starSize: starSize, spacing: spacing)
    }

    var statusItemWidth: CGFloat { imageWidth + 2 * Self.edgeInset }

    static func contentOriginX(in bounds: NSRect, contentWidth: CGFloat) -> CGFloat {
        return bounds.maxX - edgeInset - contentWidth
    }

    func image(containing content: NSImage) -> NSImage {
        guard content.size.width != imageWidth else { return content }
        let image = NSImage(size: NSSize(width: imageWidth, height: content.size.height), flipped: false) { rect in
            content.draw(in: NSRect(x: rect.maxX - content.size.width, y: 0,
                                   width: content.size.width, height: content.size.height))
            return true
        }
        image.isTemplate = content.isTemplate
        return image
    }
}
