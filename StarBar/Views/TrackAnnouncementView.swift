//
//  TrackAnnouncementView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Cocoa

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
            return TrackAnnouncementLayout.glassFrame(in: bounds.size, scale: scale, leadingInset: leadingInset, trailingInset: trailingInset)
        }
    }

    private func applyInsets() {
        let insets = TrackAnnouncementLayout.contentInsets(for: style, scale: scale, leadingInset: leadingInset, trailingInset: trailingInset)
        content.leadingInset = insets.leading
        content.trailingInset = insets.trailing
    }

    private func layoutBackdrop() {
        guard let backdrop = backdropView else { return }
        backdrop.frame = backdropFrame
        TrackAnnouncementView.applyCornerRadius(to: backdrop, scale: scale)
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

    /// The glass's corner radius, scaled with the strip; nothing for a blur
    static func applyCornerRadius(to backdrop: NSView, scale: CGFloat) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = backdrop as? NSGlassEffectView {
            glass.cornerRadius = TrackAnnouncementLayout.glassCornerRadius * scale
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
                // .clear keeps the backdrop visible through the glass; .regular frosts it
                // to a near-flat grey over a bright window. The tint's alpha matters: an
                // opaque tint on clear glass paints the strip solid, hiding the glass. The
                // corner radius is set with the frame, since it scales with the strip.
                glass.style = .clear
                glass.tintColor = TrackAnnouncementLayout.glassTint
                return glass
            }
            #endif
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

    var scale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    var leadingInset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var trailingInset: CGFloat = 0 {
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

    private func drawArtwork(in slot: NSRect) {
        if let artwork = announcement.artwork, artwork.size.width > 0, artwork.size.height > 0 {
            let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: artwork.size, in: slot)
            NSGraphicsContext.current?.imageInterpolation = .high
            artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            // No artwork: a quiet square with a music note, so the slot never looks broken
            NSColor.white.withAlphaComponent(0.12).setFill()
            slot.fill()
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
