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
/// and corners in light mode), `announcementGlassSheen` (bool; false by default: the drawn rim light and
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
/// whatever is behind the strip under a lighter tint, or Liquid Glass. The background (the
/// backdrop and the wash over it) sits in `TrackAnnouncementSurfaceView` under the drawn
/// content, so that it can be seen through without taking the text with it.
final class TrackAnnouncementView: NSView {

    var announcement: TrackAnnouncement {
        didSet {
            content.announcement = announcement
            setAccessibilityLabel(announcement.accessibilityLabel)
            // A longer title covers more of the strip, and keeps more of its background
            applyTypingWindow()
        }
    }

    /// 0.6 normally; 1 when Reduce Transparency is on, which also makes the other styles
    /// draw an opaque tint over their backdrop
    var backgroundAlpha: CGFloat = TrackAnnouncementLayout.backgroundAlpha {
        didSet { surface.wash.tintAlpha = tintAlpha }
    }

    /// How much bigger than Growl's 1280 by 800 design to draw, set from the screen
    var scale: CGFloat = 1 {
        didSet {
            content.scale = scale
            surface.wash.scale = scale
            applyInsets()
            layoutBackdrop()
            applyTypingWindow()
        }
    }

    /// The hole through the background that follows the pointer, in this view's coordinates;
    /// nil for none. The text, artwork and stars stay drawn over it.
    var peephole: TrackAnnouncementPeephole? {
        get { return surface.peephole }
        set { surface.peephole = newValue }
    }

    /// Open the window through the middle of the background that shows while the user types,
    /// `progress` of the way (0 closed, 1 open; the panel steps it). The radius, feather and
    /// the centre's height above the strip's top edge are already scaled. The artwork and text
    /// keep their background whatever the window covers: fading the whole background instead
    /// left the white text over whatever was behind.
    func setTypingWindow(radius: CGFloat, feather: CGFloat, centreHeight: CGFloat = 0, progress: CGFloat) {
        typingWindowSize = (radius, feather, centreHeight)
        typingWindowProgress = progress
        applyTypingWindow()
    }

    /// The typing window as laid out, in this view's coordinates; nil while it is closed
    var typingWindow: TrackAnnouncementTypingWindow? {
        return surface.typingWindow
    }

    private var typingWindowSize: (radius: CGFloat, feather: CGFloat, centreHeight: CGFloat) = (0, 0, 0)
    private var typingWindowProgress: CGFloat = 0

    private func applyTypingWindow() {
        // Closed: nothing to lay out, and no text to measure
        guard typingWindowSize.radius > 0, typingWindowProgress > 0 else {
            surface.typingWindow = nil
            return
        }
        surface.typingWindow = TrackAnnouncementSeeThrough.typingWindow(
            in: bounds,
            occupied: content.occupiedRect,
            radius: typingWindowSize.radius,
            feather: typingWindowSize.feather,
            centreHeight: typingWindowSize.centreHeight,
            margin: TrackAnnouncementSeeThrough.keepMargin * scale,
            keepFeather: TrackAnnouncementSeeThrough.keepFeather * scale,
            progress: typingWindowProgress
        )
    }

    /// Space at the left and right the content keeps clear: a Dock at the side that the
    /// strip's background runs behind
    var leadingInset: CGFloat = 0 {
        didSet {
            applyInsets()
            layoutBackdrop()
            applyTypingWindow()
        }
    }
    var trailingInset: CGFloat = 0 {
        didSet {
            applyInsets()
            layoutBackdrop()
            applyTypingWindow()
        }
    }

    /// The background: flat black, blur or glass
    var style: TrackAnnouncementStyle = .classic {
        didSet {
            guard style != oldValue else { return }
            rebuildBackdrop()
            applyInsets()
            // The glass's side insets move the content, and so the part that keeps its background
            applyTypingWindow()
            surface.wash.tintAlpha = tintAlpha
            surface.wash.tintColor = tintColor
        }
    }

    /// The blur or glass view under the content, nil for the classic style
    var backdropView: NSView? {
        return surface.backdropView
    }
    private let surface: TrackAnnouncementSurfaceView
    private let content: TrackAnnouncementContentView

    init(announcement: TrackAnnouncement, frame: NSRect = .zero) {
        self.announcement = announcement
        let bounds = NSRect(origin: .zero, size: frame.size)
        surface = TrackAnnouncementSurfaceView(frame: bounds)
        content = TrackAnnouncementContentView(announcement: announcement, frame: bounds)
        super.init(frame: frame)
        wantsLayer = true
        if #available(macOS 14.0, *) {
            // The glass hangs below the strip; the window clips it, this view must not
            clipsToBounds = false
        }
        surface.autoresizingMask = [.width, .height]
        surface.wash.tintAlpha = tintAlpha
        surface.wash.tintColor = tintColor
        addSubview(surface)
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(announcement.accessibilityLabel)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutBackdrop()
        applyTypingWindow()
    }

    /// The frame the backdrop takes for the current style: the whole strip for a blur, and
    /// for glass a rectangle inset from the sides and hanging below the strip, so that only
    /// its top corners are ever seen
    var backdropFrame: NSRect {
        switch renderedStyle {
        case .classic, .blur:
            return bounds
        case .glass:
            return TrackAnnouncementLayout.glassFrame(in: bounds.size, scale: scale, leadingInset: leadingInset, trailingInset: trailingInset, cornerRadius: glassCornerRadius)
        }
    }

    /// The style the backdrop was actually built as: the requested one, except that glass is
    /// the blur where the system has no Liquid Glass. Geometry follows this, not the request,
    /// or the fallback would be a square blur inset from the sides with a rounded edge line
    /// drawn over it.
    private(set) var renderedStyle: TrackAnnouncementStyle = .classic

    static func effectiveStyle(for style: TrackAnnouncementStyle) -> TrackAnnouncementStyle {
        guard style == .glass else { return style }
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return .glass }
        #endif
        return .blur
    }

    /// The glass's corner radius at scale 1: the layout's, unless the experiment knob says otherwise
    private var glassCornerRadius: CGFloat {
        return TrackAnnouncementGlassKnobs.read().cornerRadius
    }

    /// Whether the wash draws the sheen over the glass
    var hasSheen: Bool {
        return surface.wash.sheen != nil
    }

    private func applyInsets() {
        let insets = TrackAnnouncementLayout.contentInsets(for: renderedStyle, scale: scale, leadingInset: leadingInset, trailingInset: trailingInset)
        content.leadingInset = insets.leading
        content.trailingInset = insets.trailing
        content.artworkCornerRadius = TrackAnnouncementLayout.artworkCornerRadius(for: renderedStyle, scale: scale)
    }

    /// The rounding on the artwork's corners, for tests
    var artworkCornerRadius: CGFloat {
        return content.artworkCornerRadius
    }

    private func layoutBackdrop() {
        let knobs = TrackAnnouncementGlassKnobs.read()
        surface.wash.sheen = (renderedStyle == .glass && (knobs.edgeLine || knobs.sheen))
            ? TrackAnnouncementWashView.Sheen(rect: backdropFrame, cornerRadius: glassCornerRadius * scale, edgeLine: knobs.edgeLine, shading: knobs.sheen)
            : nil
        guard let backdrop = backdropView else { return }
        backdrop.frame = backdropFrame
        TrackAnnouncementView.applyCornerRadius(to: backdrop, radius: glassCornerRadius * scale)
        surface.backdropDidLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The black drawn over the backdrop: all of it for the classic style, a lighter wash
    /// over a blur or glass, and opaque for Reduce Transparency whatever the style
    var tintAlpha: CGFloat {
        if backgroundAlpha >= 1 { return 1 }
        switch renderedStyle {
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
        renderedStyle = TrackAnnouncementView.effectiveStyle(for: style)
        surface.backdropView = TrackAnnouncementView.makeBackdrop(for: style)
        // Always, so the sheen drawn over a glass backdrop goes when the style loses it
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

/// The strip's drawn content: the artwork or its placeholder, the text and the rating row,
/// over a clear background. The tint under them is `TrackAnnouncementWashView`'s. Layout
/// comes from `TrackAnnouncementLayout`.
final class TrackAnnouncementContentView: NSView {

    var announcement: TrackAnnouncement {
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var frames: TrackAnnouncementLayout.Frames {
        return TrackAnnouncementLayout.frames(
            in: bounds.size,
            scale: scale,
            leadingInset: leadingInset,
            trailingInset: trailingInset,
            hasArtist: !announcement.artist.isEmpty,
            hasAlbum: !announcement.album.isEmpty
        )
    }

    private var titleFont: NSFont {
        return NSFont.boldSystemFont(ofSize: TrackAnnouncementLayout.titleFontSize * scale)
    }

    private var detailFont: NSFont {
        return NSFont.messageFont(ofSize: TrackAnnouncementLayout.detailFontSize * scale)
    }

    private var cannotRateFont: NSFont {
        return NSFont.systemFont(ofSize: TrackAnnouncementLayout.cannotRateFontSize * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        let frames = self.frames
        drawArtwork(in: frames.artwork)
        draw(announcement.title, in: frames.title, font: titleFont)
        if let artistRect = frames.artist {
            draw(announcement.artist, in: artistRect, font: detailFont)
        }
        if let albumRect = frames.album {
            draw(announcement.album, in: albumRect, font: detailFont.italic)
        }
        drawRating(in: frames.rating)
    }

    /// The part of the strip the artwork and text actually cover: the artwork, and each line
    /// as wide as its text rather than its slot, which runs most of the way across the strip.
    /// The typing window keeps the background under this.
    var occupiedRect: NSRect {
        let frames = self.frames
        var rect = frames.artwork
        rect = rect.union(used(announcement.title, in: frames.title, font: titleFont))
        if let artistRect = frames.artist {
            rect = rect.union(used(announcement.artist, in: artistRect, font: detailFont))
        }
        if let albumRect = frames.album {
            rect = rect.union(used(announcement.album, in: albumRect, font: detailFont.italic))
        }
        return rect.union(usedByRating(in: frames.rating))
    }

    /// The part of `slot` a line of text covers, measured as it is drawn
    private func used(_ text: String, in slot: NSRect, font: NSFont) -> NSRect {
        guard !text.isEmpty else { return .null }
        let width = (text.typographicPunctuation as NSString).size(withAttributes: [.font: font]).width
        return NSRect(x: slot.minX, y: slot.minY, width: min(slot.width, width.rounded(.up)), height: slot.height)
    }

    /// The stars and heart, or the heart and the "add it to rate it" line
    private func usedByRating(in slot: NSRect) -> NSRect {
        let starSize = NSSize(width: TrackAnnouncementLayout.ratingStarSize * scale, height: TrackAnnouncementLayout.ratingStarSize * scale)
        let spacing = TrackAnnouncementLayout.ratingSpacing * scale
        let width: CGFloat
        if announcement.canRate {
            let stars = Stars.rating(announcement.rating, starSize: starSize, spacing: spacing, isFavorited: announcement.isFavorited)
            // The stars, then the heart's slot: the width `Stars.image` would have, without
            // drawing it
            width = stars.starsWidth + spacing + starSize.width
        } else {
            let text = (TrackAnnouncement.cannotRateText as NSString).size(withAttributes: [.font: cannotRateFont]).width
            width = starSize.width + spacing * 2 + text.rounded(.up)
        }
        return NSRect(x: slot.minX, y: slot.minY, width: min(slot.width, width), height: slot.height)
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

        guard announcement.canRate else {
            drawCannotRate(in: rect, starSize: starSize, spacing: spacing)
            return
        }

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

    /// The heart on its own, then why there are no stars.
    ///
    /// Five empty dots would say "unrated", which is not what is true: the song is playing
    /// from the Apple Music catalog and isn't in the library, so it has no rating to show and
    /// cannot be given one until it is added.
    private func drawCannotRate(in rect: NSRect, starSize: NSSize, spacing: CGFloat) {
        let heartRect = NSRect(x: rect.minX, y: rect.midY - starSize.height / 2,
                               width: starSize.width, height: starSize.height)

        NSGraphicsContext.saveGraphicsState()
        textShadow.set()
        if announcement.isFavorited {
            Stars.filledFavoriteHeartImage(size: starSize).draw(in: heartRect)
        } else {
            let outline = NSImage(size: starSize, flipped: false) { bounds in
                Stars.drawFavoriteHeartOutline(in: bounds)
                return true
            }
            outline.isTemplate = true
            outline.withTintColor(.white).draw(in: heartRect)
        }
        NSGraphicsContext.restoreGraphicsState()

        let textMinX = heartRect.maxX + spacing * 2
        let font = cannotRateFont
        draw(TrackAnnouncement.cannotRateText,
             in: TrackAnnouncementLayout.textRect(centredOn: heartRect.midY, font: font,
                                                fromX: textMinX, toX: rect.maxX),
             font: font)
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

    /// Every line on the strip goes through here, so the typography is set in one place.
    ///
    /// Kerning is on because nothing turns it off: AppKit kerns by default, and setting
    /// `.kern` to 0 is what would disable it. Ligatures are left alone for the same reason,
    /// though they change nothing here -- the system font ships without the fi and fl
    /// ligatures, so there is none to form.
    private func draw(_ text: String, in rect: NSRect, font: NSFont) {
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        // Let a slightly-too-long album name tighten instead of losing its last word
        paragraph.allowsDefaultTighteningForTruncation = true

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .shadow: textShadow,
            .paragraphStyle: paragraph,
        ]
        (text.typographicPunctuation as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
        )
    }

}
