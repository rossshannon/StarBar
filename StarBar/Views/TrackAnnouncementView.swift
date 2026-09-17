//
//  TrackAnnouncementView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Cocoa
import os.log

/// Experiment knobs for the glass, read from defaults so its look can be compared without a
/// rebuild. The defaults are the combination Ross picked from a grid of samples: the regular
/// style at full opacity, untinted, 8 point corners, no drawn sheen.
/// `announcementGlassRegular` (bool; true by default, false for the clear style),
/// `announcementGlassTintAlpha` (0 to 1; `TrackAnnouncementLayout.glassTint`'s alpha, 0, by
/// default), `announcementGlassCornerRadius` (points at scale 1;
/// `TrackAnnouncementLayout.glassCornerRadius` by default; bigger corners lens more),
/// `announcementGlassEdgeLine` (bool; true by default: the bright line along the top edge
/// and corners), `announcementGlassSheen` (bool; false by default: the drawn rim light and
/// shade that suggest a domed surface) and `announcementGlassAlpha` (0 to 1; 1 by default:
/// the glass view's own opacity, which fades frost and rim together, since the API has no
/// frost dial). They are read when the glass is built, so switch the strip style away and
/// back after changing one.
struct TrackAnnouncementGlassKnobs: Equatable {
    var regular = true
    var tintAlpha = TrackAnnouncementLayout.glassTint.alphaComponent
    var cornerRadius = TrackAnnouncementLayout.glassCornerRadius
    var edgeLine = true
    var sheen = false
    var alpha: CGFloat = 1

    /// Where the strip gets its knobs. The tests are hosted in the app, so they replace this
    /// with fixed values rather than read whatever is set on the machine.
    static var read: () -> TrackAnnouncementGlassKnobs = { current }

    static var current: TrackAnnouncementGlassKnobs {
        let defaults = UserDefaults.standard
        var knobs = TrackAnnouncementGlassKnobs()
        if defaults.object(forKey: "announcementGlassRegular") != nil {
            knobs.regular = defaults.bool(forKey: "announcementGlassRegular")
        }
        if defaults.object(forKey: "announcementGlassTintAlpha") != nil {
            knobs.tintAlpha = min(1, max(0, CGFloat(defaults.double(forKey: "announcementGlassTintAlpha"))))
        }
        if defaults.object(forKey: "announcementGlassCornerRadius") != nil {
            knobs.cornerRadius = max(0, CGFloat(defaults.double(forKey: "announcementGlassCornerRadius")))
        }
        if defaults.object(forKey: "announcementGlassSheen") != nil {
            knobs.sheen = defaults.bool(forKey: "announcementGlassSheen")
        }
        if defaults.object(forKey: "announcementGlassEdgeLine") != nil {
            knobs.edgeLine = defaults.bool(forKey: "announcementGlassEdgeLine")
        }
        if defaults.object(forKey: "announcementGlassAlpha") != nil {
            knobs.alpha = min(1, max(0, CGFloat(defaults.double(forKey: "announcementGlassAlpha"))))
        }
        return knobs
    }
}

/// The announcement strip: a dark band with the artwork on the left and the title, artist,
/// album and rating in white, drawn the way Growl's Music Video view drew them.
///
/// The band's background depends on the style: Growl's flat translucent black, a blur of
/// whatever is behind the strip under a lighter tint, or Liquid Glass. The backdrop is a
/// subview under the drawn content, because a view's own drawing always sits beneath its
/// subviews.
final class TrackAnnouncementView: NSView {

    var announcement: TrackAnnouncement {
        didSet {
            content.announcement = announcement
            setAccessibilityLabel(announcement.accessibilityLabel)
        }
    }

    /// 0.6 normally; 1 when Reduce Transparency is on, which also makes the other styles
    /// draw an opaque tint over their backdrop
    var backgroundAlpha: CGFloat = TrackAnnouncementLayout.backgroundAlpha {
        didSet { content.tintAlpha = tintAlpha }
    }

    /// How much bigger than Growl's 1280 by 800 design to draw, set from the screen
    var scale: CGFloat = 1 {
        didSet {
            content.scale = scale
            applyInsets()
            layoutBackdrop()
        }
    }

    /// Space at the left and right the content keeps clear: a Dock at the side that the
    /// strip's background runs behind
    var leadingInset: CGFloat = 0 {
        didSet {
            applyInsets()
            layoutBackdrop()
        }
    }
    var trailingInset: CGFloat = 0 {
        didSet {
            applyInsets()
            layoutBackdrop()
        }
    }

    /// The background: flat black, blur or glass
    var style: TrackAnnouncementStyle = .classic {
        didSet {
            guard style != oldValue else { return }
            rebuildBackdrop()
            applyInsets()
            content.tintAlpha = tintAlpha
            content.tintColor = tintColor
        }
    }

    /// The blur or glass view under the content, nil for the classic style
    private(set) var backdropView: NSView?
    private let content: TrackAnnouncementContentView

    init(announcement: TrackAnnouncement, frame: NSRect = .zero) {
        self.announcement = announcement
        content = TrackAnnouncementContentView(announcement: announcement, frame: NSRect(origin: .zero, size: frame.size))
        super.init(frame: frame)
        wantsLayer = true
        if #available(macOS 14.0, *) {
            // The glass hangs below the strip; the window clips it, this view must not
            clipsToBounds = false
        }
        content.autoresizingMask = [.width, .height]
        content.tintAlpha = tintAlpha
        content.tintColor = tintColor
        addSubview(content)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(announcement.accessibilityLabel)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutBackdrop()
    }

    /// The frame the backdrop takes for the current style: the whole strip for a blur, and
    /// for glass a rectangle inset from the sides and hanging below the strip, so that only
    /// its top corners are ever seen
    var backdropFrame: NSRect {
        switch style {
        case .classic, .blur:
            return bounds
        case .glass:
            return TrackAnnouncementLayout.glassFrame(in: bounds.size, scale: scale, leadingInset: leadingInset, trailingInset: trailingInset, cornerRadius: glassCornerRadius)
        }
    }

    /// The glass's corner radius at scale 1: the layout's, unless the experiment knob says otherwise
    private var glassCornerRadius: CGFloat {
        return TrackAnnouncementGlassKnobs.read().cornerRadius
    }

    /// Whether the content draws the sheen over the glass
    var hasSheen: Bool {
        return content.sheen != nil
    }

    private func applyInsets() {
        let insets = TrackAnnouncementLayout.contentInsets(for: style, scale: scale, leadingInset: leadingInset, trailingInset: trailingInset)
        content.leadingInset = insets.leading
        content.trailingInset = insets.trailing
        content.artworkCornerRadius = TrackAnnouncementLayout.artworkCornerRadius(for: style, scale: scale)
    }

    /// The rounding on the artwork's corners, for tests
    var artworkCornerRadius: CGFloat {
        return content.artworkCornerRadius
    }

    private func layoutBackdrop() {
        let knobs = TrackAnnouncementGlassKnobs.read()
        content.sheen = (style == .glass && (knobs.edgeLine || knobs.sheen))
            ? TrackAnnouncementContentView.Sheen(rect: backdropFrame, cornerRadius: glassCornerRadius * scale, edgeLine: knobs.edgeLine, shading: knobs.sheen)
            : nil
        guard let backdrop = backdropView else { return }
        backdrop.frame = backdropFrame
        TrackAnnouncementView.applyCornerRadius(to: backdrop, radius: glassCornerRadius * scale)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The black drawn over the backdrop: all of it for the classic style, a lighter wash
    /// over a blur or glass, and opaque for Reduce Transparency whatever the style
    var tintAlpha: CGFloat {
        if backgroundAlpha >= 1 { return 1 }
        switch style {
        case .classic: return backgroundAlpha
        case .blur: return TrackAnnouncementLayout.blurTintAlpha
        case .glass: return TrackAnnouncementLayout.glassTintAlpha
        }
    }

    /// The wash is always black; the glass carries its own dark tint instead of a wash
    var tintColor: NSColor {
        return .black
    }

    private func rebuildBackdrop() {
        backdropView?.removeFromSuperview()
        backdropView = nil
        guard let backdrop = TrackAnnouncementView.makeBackdrop(for: style) else { return }
        addSubview(backdrop, positioned: .below, relativeTo: content)
        backdropView = backdrop
        layoutBackdrop()
    }

    /// The glass's corner radius, already scaled with the strip; nothing for a blur
    static func applyCornerRadius(to backdrop: NSView, radius: CGFloat) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
            glass.cornerRadius = radius
        }
        #endif
    }

    /// A behind-window blur, or Liquid Glass where the system has it. `state` must be
    /// `.active`: the default follows the window's active state, and this panel is never
    /// active, so the blur would silently switch off.
    ///
    /// `NSGlassEffectView` exists only in the macOS 26 SDK (Xcode 26, Swift 6.2), so the
    /// runtime check sits inside a compiler check: an older Xcode builds the blur fallback.
    static func makeBackdrop(for style: TrackAnnouncementStyle) -> NSView? {
        switch style {
        case .classic:
            return nil
        case .glass:
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                let knobs = TrackAnnouncementGlassKnobs.read()
                // .regular is the style with the lensing Ross was after; .clear is a little
                // less frosted but bends less. The tint's alpha matters: an opaque tint
                // paints the strip solid, hiding the glass. The corner radius is set with
                // the frame, since it scales with the strip.
                glass.style = knobs.regular ? .regular : .clear
                if knobs.tintAlpha > 0 {
                    glass.tintColor = NSColor.black.withAlphaComponent(knobs.tintAlpha)
                }
                glass.alphaValue = knobs.alpha
                os_log("%{public}s[%{public}ld], %{public}s: NSGlassEffectView style=%{public}s tint=%.2f alpha=%.2f radius=%.0f sheen=%{public}s", ((#file as NSString).lastPathComponent), #line, #function, knobs.regular ? "regular" : "clear", Double(knobs.tintAlpha), Double(knobs.alpha), Double(knobs.cornerRadius), knobs.sheen ? "on" : "off")
                return glass
            }
            #endif
            os_log("%{public}s[%{public}ld], %{public}s: no Liquid Glass on this system; using the blur", ((#file as NSString).lastPathComponent), #line, #function)
            return makeBlur()
        case .blur:
            return makeBlur()
        }
    }

    private static func makeBlur() -> NSVisualEffectView {
        let blur = NSVisualEffectView()
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        return blur
    }

}

/// The strip's drawn content: the tint, the artwork or its placeholder, the text and the
/// rating row. Layout comes from `TrackAnnouncementLayout`.
final class TrackAnnouncementContentView: NSView {

    var announcement: TrackAnnouncement {
        didSet { needsDisplay = true }
    }

    var tintAlpha: CGFloat = TrackAnnouncementLayout.backgroundAlpha {
        didSet { needsDisplay = true }
    }

    var tintColor: NSColor = .black {
        didSet { needsDisplay = true }
    }

    /// The glass's shape in this view's coordinates, and which parts of the sheen to draw
    /// over it: the bright line along the top edge, and the soft shading that suggests a dome
    struct Sheen: Equatable {
        var rect: NSRect
        var cornerRadius: CGFloat
        var edgeLine = true
        var shading = false
    }

    /// Set for the glass style when any part of the sheen is on
    var sheen: Sheen? {
        didSet {
            guard sheen != oldValue else { return }
            needsDisplay = true
        }
    }

    var scale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    var leadingInset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var trailingInset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    /// Rounding on the artwork's corners; 0 draws it square
    var artworkCornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init(announcement: TrackAnnouncement, frame: NSRect = .zero) {
        self.announcement = announcement
        super.init(frame: frame)
        wantsLayer = true
        // Moving the strip must not redraw it: its contents change only with the announcement
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        if tintAlpha > 0 {
            tintColor.withAlphaComponent(tintAlpha).setFill()
            bounds.fill()
        }
        // Under Reduce Transparency's opaque wash the sheen has no glass to sit on
        if let sheen = sheen, tintAlpha < 1 {
            drawSheen(sheen)
        }

        let frames = TrackAnnouncementLayout.frames(
            in: bounds.size,
            scale: scale,
            leadingInset: leadingInset,
            trailingInset: trailingInset,
            hasArtist: !announcement.artist.isEmpty,
            hasAlbum: !announcement.album.isEmpty
        )
        drawArtwork(in: frames.artwork)
        draw(announcement.title, in: frames.title, font: NSFont.boldSystemFont(ofSize: TrackAnnouncementLayout.titleFontSize * scale))
        let detailFont = NSFont.messageFont(ofSize: TrackAnnouncementLayout.detailFontSize * scale)
        if let artistRect = frames.artist {
            draw(announcement.artist, in: artistRect, font: detailFont)
        }
        if let albumRect = frames.album {
            draw(announcement.album, in: albumRect, font: detailFont)
        }
        drawRating(in: frames.rating)
    }

    /// A rim light fading down from the top edge and a shade rising from the bottom, clipped
    /// to the glass's rounded shape, so the flat glass reads as a dome
    private func drawSheen(_ sheen: Sheen) {
        let shape = NSBezierPath(roundedRect: sheen.rect, xRadius: sheen.cornerRadius, yRadius: sheen.cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if sheen.shading {
            let highlightHeight = bounds.height * TrackAnnouncementLayout.glassSheenHighlightFraction
            let highlight = NSRect(x: sheen.rect.minX, y: bounds.maxY - highlightHeight, width: sheen.rect.width, height: highlightHeight)
            // Angle -90 draws the starting colour at the top
            NSGradient(starting: NSColor.white.withAlphaComponent(TrackAnnouncementLayout.glassSheenHighlightAlpha), ending: .clear)?
                .draw(in: highlight, angle: -90)
            let shadeHeight = bounds.height * TrackAnnouncementLayout.glassSheenShadeFraction
            let shade = NSRect(x: sheen.rect.minX, y: bounds.minY, width: sheen.rect.width, height: shadeHeight)
            NSGradient(starting: NSColor.black.withAlphaComponent(TrackAnnouncementLayout.glassSheenShadeAlpha), ending: .clear)?
                .draw(in: shade, angle: 90)
        }
        if sheen.edgeLine {
            // The specular line along the top edge, following the rounded corners: the
            // shape stroked twice as wide and clipped, so only the inner half shows
            let edgeWidth = TrackAnnouncementLayout.glassSheenEdgeWidth * scale
            NSColor.white.withAlphaComponent(TrackAnnouncementLayout.glassSheenEdgeAlpha).setStroke()
            shape.lineWidth = edgeWidth * 2
            shape.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawArtwork(in slot: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if let artwork = announcement.artwork, artwork.size.width > 0, artwork.size.height > 0 {
            let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: artwork.size, in: slot)
            if artworkCornerRadius > 0 {
                NSBezierPath(roundedRect: rect, xRadius: artworkCornerRadius, yRadius: artworkCornerRadius).addClip()
            }
            NSGraphicsContext.current?.imageInterpolation = .high
            artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            // No artwork: a quiet square with a music note, so the slot never looks broken
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: slot, xRadius: artworkCornerRadius, yRadius: artworkCornerRadius).fill()
            if let note = TrackAnnouncementContentView.placeholderImage {
                // Drawn at 36 points in an 80 point slot at scale 1, and in proportion above
                let noteSize = CGSize(width: note.size.width * scale, height: note.size.height * scale)
                let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: noteSize, in: slot)
                note.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.9)
            }
        }
    }

    private static let placeholderImage: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        symbol.isTemplate = true
        return symbol.withTintColor(.white)
    }()

    /// The five stars and the heart, white like the text, with the same shadow. The menu
    /// bar's template image is tinted white; a favourite's heart is drawn in colour on top,
    /// as the menu bar does.
    private func drawRating(in rect: NSRect) {
        let starSize = NSSize(width: TrackAnnouncementLayout.ratingStarSize * scale, height: TrackAnnouncementLayout.ratingStarSize * scale)
        let spacing = TrackAnnouncementLayout.ratingSpacing * scale
        let stars = Stars.rating(announcement.rating, starSize: starSize, spacing: spacing, isFavorited: announcement.isFavorited)
        let template = stars.image
        template.isTemplate = true
        let image = template.withTintColor(.white)
        let origin = NSPoint(x: rect.minX, y: rect.midY - image.size.height / 2)

        NSGraphicsContext.saveGraphicsState()
        textShadow.set()
        image.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        if announcement.isFavorited {
            let heart = Stars.filledFavoriteHeartImage(size: starSize)
            heart.draw(at: NSPoint(x: rect.minX + stars.starsWidth + spacing, y: origin.y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Growl's soft downward shadow, scaled with the strip
    private var textShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowOffset = CGSize(
            width: TrackAnnouncementLayout.shadowOffset.width * scale,
            height: TrackAnnouncementLayout.shadowOffset.height * scale
        )
        shadow.shadowBlurRadius = TrackAnnouncementLayout.shadowBlurRadius * scale
        shadow.shadowColor = NSColor.black
        return shadow
    }

    private func draw(_ text: String, in rect: NSRect, font: NSFont) {
        guard !text.isEmpty else { return }
        let shadow = textShadow
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

}
