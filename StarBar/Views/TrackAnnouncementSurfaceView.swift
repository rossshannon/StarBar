//
//  TrackAnnouncementSurfaceView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-23.
//

import Cocoa

/// The strip's background: the blur or glass, and the wash drawn over it. They sit in a
/// container of their own, under the content, so that the pointer's hole and the typing window
/// can take the background away and leave the text, artwork and stars where they are.
///
/// Both are layer masks. A mask on a view that holds a behind-window `NSVisualEffectView` or an
/// `NSGlassEffectView` does cut them, measured on macOS 27 with a striped pattern behind a test
/// window: the pattern showed sharp through the hole, with no lensing at its edge. Older systems
/// were not tried.
///
/// The two holes are on two views, this one and `stack` inside it, because masks multiply down
/// the view tree. In one mask the solid tiles around each hole would cover the other hole.
final class TrackAnnouncementSurfaceView: NSView {

    /// The tint and the glass's edge line, over the backdrop
    let wash: TrackAnnouncementWashView

    /// The backdrop and the wash, masked by the typing window
    private let stack: NSView

    /// The blur or glass, under the wash; nil for the classic style
    var backdropView: NSView? {
        didSet {
            guard backdropView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let backdrop = backdropView {
                stack.addSubview(backdrop, positioned: .below, relativeTo: wash)
            }
            applyMasks()
        }
    }

    /// Where the pointer's hole is, in this view's coordinates; nil for none. Each mask exists
    /// only while its hole does, so the strip renders exactly as before the rest of the time.
    var peephole: TrackAnnouncementPeephole? {
        didSet {
            guard peephole != oldValue else { return }
            applyMasks()
        }
    }

    /// The window opened while the user types, in this view's coordinates; nil for none
    var typingWindow: TrackAnnouncementTypingWindow? {
        didSet {
            guard typingWindow != oldValue else { return }
            applyMasks()
        }
    }

    private var peepholeMask: TrackAnnouncementPeepholeMask?
    private var typingMask: TrackAnnouncementTypingMask?

    override init(frame frameRect: NSRect) {
        let bounds = NSRect(origin: .zero, size: frameRect.size)
        wash = TrackAnnouncementWashView(frame: bounds)
        stack = NSView(frame: bounds)
        super.init(frame: frameRect)
        wantsLayer = true
        stack.wantsLayer = true
        if #available(macOS 14.0, *) {
            // The glass hangs below the strip; the window clips it, these views must not
            clipsToBounds = false
            stack.clipsToBounds = false
        }
        stack.autoresizingMask = [.width, .height]
        wash.autoresizingMask = [.width, .height]
        stack.addSubview(wash)
        addSubview(stack)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        applyMasks()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyMasks()
    }

    /// Place the masks again after the backdrop has moved or changed size: they cover the
    /// backdrop's frame, and nothing else tells this view that the frame changed
    func backdropDidLayout() {
        applyMasks()
    }

    /// The masks' extent: the strip, and the glass where it hangs below it. Anything outside a
    /// mask's frame is hidden, so a mask must cover all of the backdrop. `stack` has this view's
    /// bounds, so one extent serves both.
    private var maskBounds: CGRect {
        return bounds.union(backdropView?.frame ?? bounds)
    }

    private func applyMasks() {
        guard let layer = layer, let stackLayer = stack.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        if let peephole = peephole {
            let mask = peepholeMask ?? TrackAnnouncementPeepholeMask()
            peepholeMask = mask
            mask.place(peephole, in: maskBounds, scale: scale)
            if layer.mask !== mask {
                layer.mask = mask
            }
        } else {
            layer.mask = nil
        }

        if let typingWindow = typingWindow {
            let mask = typingMask ?? TrackAnnouncementTypingMask()
            typingMask = mask
            mask.place(typingWindow, in: maskBounds, scale: scale)
            if stackLayer.mask !== mask {
                stackLayer.mask = mask
            }
        } else {
            stackLayer.mask = nil
        }
    }

    /// The typing window's mask, for tests
    var typingWindowMask: CALayer? {
        return stack.layer?.mask
    }

}

/// The strip's wash, and for the glass the bright line along its top edge and the optional
/// shading: everything drawn over the backdrop that belongs with it rather than with the text.
final class TrackAnnouncementWashView: NSView {

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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Moving the strip must not redraw it
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
        // In dark mode the native glass already defines its edge; our extra white stroke
        // reads as a border rather than a glint. Match the view, including high contrast.
        if sheen.edgeLine && effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua {
            // The specular line along the top edge, following the rounded corners: the
            // shape stroked twice as wide and clipped, so only the inner half shows
            let edgeWidth = TrackAnnouncementLayout.glassSheenEdgeWidth * scale
            NSColor.white.withAlphaComponent(TrackAnnouncementLayout.glassSheenEdgeAlpha).setStroke()
            shape.lineWidth = edgeWidth * 2
            shape.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

}

/// A layer mask with one soft round hole in it: an image of the hole, drawn once for each
/// size, and four solid rectangles filling the rest. Moving the hole moves five layers and
/// redraws nothing, so it can follow the pointer on every display refresh.
final class TrackAnnouncementPeepholeMask: CALayer {

    private let hole = CALayer()
    private let tiles: [CALayer] = (0..<4).map { _ in CALayer() }
    /// The size the hole's image was drawn at, to redraw it only when that changes
    private var drawn: (radius: CGFloat, feather: CGFloat)?

    /// Pixels per point in the hole's image, whatever the screen's. The image is a soft
    /// gradient around a flat clear middle, so stretching a coarse one looks the same as a
    /// sharp one, and at full resolution a hole of the default size took 2 to 8 MB and several
    /// milliseconds to draw. The layer's frame still lands on whole screen pixels.
    static let imageScale: CGFloat = 0.5
    /// And never more than this many pixels across, whatever the radius: the typing window at
    /// scale 2 would otherwise draw a 720 pixel image for a gradient
    static let maximumImageSide: CGFloat = 512

    override init() {
        super.init()
        for tile in tiles {
            tile.backgroundColor = CGColor(gray: 0, alpha: 1)
            addSublayer(tile)
        }
        addSublayer(hole)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Put the hole at `peephole`'s centre, in the coordinates of the layer being masked,
    /// covering `bounds` everywhere else
    func place(_ peephole: TrackAnnouncementPeephole, in bounds: CGRect, scale: CGFloat) {
        CATransaction.begin()
        // Plain layers animate every change by default; the hole must track the pointer exactly
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        frame = bounds
        if drawn.map({ $0.radius != peephole.radius || $0.feather != peephole.feather }) ?? true {
            let imageScale = min(TrackAnnouncementPeepholeMask.imageScale,
                                 TrackAnnouncementPeepholeMask.maximumImageSide / max(1, peephole.radius * 2))
            hole.contents = TrackAnnouncementPeepholeMask.holeImage(radius: peephole.radius, feather: peephole.feather, scale: imageScale)
            hole.contentsScale = imageScale
            drawn = (peephole.radius, peephole.feather)
        }
        // Sublayers are placed in this layer's own coordinates, which start at the mask's corner
        let local = TrackAnnouncementPeephole(
            centre: CGPoint(x: peephole.centre.x - bounds.minX, y: peephole.centre.y - bounds.minY),
            radius: peephole.radius,
            feather: peephole.feather
        )
        let holeRect = TrackAnnouncementSeeThrough.holeRect(for: local, scale: scale)
        hole.frame = holeRect
        let rects = TrackAnnouncementSeeThrough.maskTiles(around: holeRect, in: CGRect(origin: .zero, size: bounds.size))
        for (tile, rect) in zip(tiles, rects) {
            tile.frame = rect
        }
    }

    /// Solid, with a clear disc in the middle whose edge fades back to solid over `feather`
    /// along a smoothstep curve, which reads as softer than a straight ramp
    static func holeImage(radius: CGFloat, feather: CGFloat, scale: CGFloat) -> CGImage? {
        let side = Int((radius * 2 * scale).rounded(.up))
        guard side > 0, let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let size = CGFloat(side) / scale
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Drawn with destinationOut, so the gradient's alpha is how much it clears
        context.setBlendMode(.destinationOut)
        let inner = radius > 0 ? max(0, (radius - feather) / radius) : 0
        let steps = 8
        var colours: [CGColor] = [CGColor(gray: 0, alpha: 1)]
        var locations: [CGFloat] = [0]
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let smooth = t * t * (3 - 2 * t)
            colours.append(CGColor(gray: 0, alpha: 1 - smooth))
            locations.append(inner + (1 - inner) * t)
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: locations) else { return nil }
        let centre = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
        return context.makeImage()
    }

}

/// The typing window's mask: a large soft hole (a `TrackAnnouncementPeepholeMask`), solid over
/// the part of the strip the artwork and text use with a soft edge after it, and a solid fill
/// over everything at `1 - progress`. A mask is the union of its layers, so the fill closes the
/// hole as progress falls, and the window opens and closes by changing one opacity rather than
/// redrawing anything.
final class TrackAnnouncementTypingMask: CALayer {

    private let hole = TrackAnnouncementPeepholeMask()
    /// Solid over the artwork and text
    private let keep = CALayer()
    /// Solid to clear, after `keep`, so the window's edge there is soft rather than a cut
    private let keepEdge = CAGradientLayer()
    /// Solid everywhere at `1 - progress`
    private let fill = CALayer()

    override init() {
        super.init()
        let solid = CGColor(gray: 0, alpha: 1)
        keep.backgroundColor = solid
        keepEdge.colors = [solid, CGColor(gray: 0, alpha: 0)]
        keepEdge.startPoint = CGPoint(x: 0, y: 0.5)
        keepEdge.endPoint = CGPoint(x: 1, y: 0.5)
        fill.backgroundColor = solid
        for layer in [hole, keep, keepEdge, fill] {
            addSublayer(layer)
        }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lay the window out in the coordinates of the layer being masked, covering `bounds`
    func place(_ window: TrackAnnouncementTypingWindow, in bounds: CGRect, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        frame = bounds
        // Sublayers are placed in this layer's own coordinates, which start at the mask's corner
        let local = CGRect(origin: .zero, size: bounds.size)
        var hole = window.hole
        hole.centre = CGPoint(x: hole.centre.x - bounds.minX, y: hole.centre.y - bounds.minY)
        self.hole.place(hole, in: local, scale: scale)

        // On a whole pixel, so the solid part and its soft edge don't leave a seam between them
        let pixels = max(1, scale)
        let keepWidth = max(0, ((window.keepUntilX - bounds.minX) * pixels).rounded() / pixels)
        keep.frame = CGRect(x: 0, y: 0, width: keepWidth, height: local.height)
        keepEdge.frame = CGRect(x: keepWidth, y: 0, width: window.keepFeather, height: local.height)

        fill.frame = local
        fill.opacity = Float(1 - min(1, max(0, window.progress)))
    }

}
