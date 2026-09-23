import Cocoa

/// Right-align the visible content inside the menu bar allocation.
/// The stars use the full strip. The add button takes only its own width, but a collapse keeps
/// the full strip until the stars are gone (see `StarCollapse`), so while contents animate the
/// allocation can be wider than what is drawn. Resizing the native item on macOS 27 moves its
/// displayed contents independently of the local view frames, so width changes happen only
/// where nothing visible depends on them.
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

    /// The content right-aligned in the full strip
    func image(containing content: NSImage) -> NSImage {
        return image(containing: content, allocation: statusItemWidth)
    }

    /// The content right-aligned in a status item of the given length
    func image(containing content: NSImage, allocation: CGFloat) -> NSImage {
        let width = max(content.size.width, allocation - 2 * Self.edgeInset)
        guard content.size.width != width else { return content }
        let image = NSImage(size: NSSize(width: width, height: content.size.height), flipped: false) { rect in
            content.draw(in: NSRect(x: rect.maxX - content.size.width, y: 0,
                                   width: content.size.width, height: content.size.height))
            return true
        }
        image.isTemplate = content.isTemplate
        return image
    }
}
