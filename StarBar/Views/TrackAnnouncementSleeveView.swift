//
//  TrackAnnouncementSleeveView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-02.
//

import Cocoa

/// The break-out sleeve: the strip's cover on layers of its own, so that it can stand above
/// the strip's top edge, lean in 3D and tip towards the pointer. The rules are
/// `TrackAnnouncementSleeve`'s.
///
/// `TrackAnnouncementView` owns it and keeps its cover, cross-fade and scale up to date; the
/// panel hosts it in its own container, beside the strip rather than inside it, because the
/// strip only stops clipping what hangs outside it on macOS 14 and later, and the panel moves
/// it with the strip on every step of the slide. Its frame is the sleeve's square with
/// `TrackAnnouncementSleeve.margin` around it.
///
/// A layer-hosting view: the layers are this view's own, so AppKit never resets their
/// transforms. Every change is made with Core Animation's implicit animations off, and anything
/// that moves is stepped by the panel's clock, because on macOS 27 a Core Animation animation
/// on this panel ran to completion without ever being drawn.
final class TrackAnnouncementSleeveView: NSView {

    /// The cover, or nil for the placeholder
    var artwork: NSImage? {
        didSet {
            guard artwork !== oldValue else { return }
            updateContents()
            layoutLayers()
        }
    }

    /// How much of the cover shows over the placeholder, 0 to 1: the strip's `artworkFade`,
    /// which the panel steps when a cover arrives after the strip went up
    var coverFade: CGFloat = 1 {
        didSet {
            guard coverFade != oldValue else { return }
            applyFade()
        }
    }

    /// How much bigger than scale 1 to draw, the strip's
    var scale: CGFloat = 1 {
        didSet {
            guard scale != oldValue else { return }
            updatePlaceholder()
            layoutLayers()
        }
    }

    /// The pointer's tilt, on top of the lean
    var tilt = TrackAnnouncementSleeve.Tilt.rest {
        didSet {
            guard tilt != oldValue else { return }
            applyTransform()
        }
    }

    /// How far through its rise the sleeve is: 0 sunk into the strip, 1 in place, and a
    /// little over 1 while it overshoots
    var rise: CGFloat = 1 {
        didSet {
            guard rise != oldValue else { return }
            applyRise()
        }
    }

    /// False under Reduce Transparency: the glare is a translucent wash over the cover
    var showsGlare = true {
        didSet {
            guard showsGlare != oldValue else { return }
            applyTransform()
        }
    }

    /// The sleeve's square before it turns, in this view's coordinates
    var slot: CGRect {
        let margin = TrackAnnouncementSleeve.margin * scale
        return bounds.insetBy(dx: margin, dy: margin)
    }

    /// The sleeve itself, in this view's coordinates: the slot, or the cover's shape scaled to
    /// fit it, as the flat artwork is drawn
    var sleeveRect: CGRect {
        guard let artwork = artwork, artwork.size.width > 0, artwork.size.height > 0 else { return slot }
        return TrackAnnouncementLayout.artworkDrawingRect(imageSize: artwork.size, in: slot)
    }

    /// The layer that turns, for tests
    var turnedLayer: CALayer {
        return turnLayer
    }

    /// How much of the cover shows, for tests: 0 while there is none
    var coverOpacity: Float {
        return coverLayer.isHidden ? 0 : coverLayer.opacity
    }

    var glareOpacity: Float {
        return glareLayer.isHidden ? 0 : glareLayer.opacity
    }

    /// Turns, rises and casts the shadow
    private let turnLayer = CALayer()
    /// Rounds the corners and draws the rim
    private let clipLayer = CALayer()
    private let placeholderLayer = CALayer()
    private let noteLayer = CALayer()
    private let coverLayer = CALayer()
    private let glareLayer = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // The layer first, then wantsLayer: a layer-hosting view, whose layers AppKit leaves alone
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true

        turnLayer.allowsEdgeAntialiasing = true
        turnLayer.masksToBounds = false
        turnLayer.shadowColor = NSColor.black.cgColor
        turnLayer.shadowOpacity = TrackAnnouncementSleeve.shadowOpacity

        clipLayer.masksToBounds = true
        clipLayer.allowsEdgeAntialiasing = true
        clipLayer.cornerCurve = .continuous
        clipLayer.borderColor = NSColor.white.withAlphaComponent(TrackAnnouncementSleeve.rimAlpha).cgColor

        placeholderLayer.backgroundColor = NSColor.white.withAlphaComponent(TrackAnnouncementContentView.placeholderFillAlpha).cgColor
        noteLayer.contentsGravity = .resizeAspect
        placeholderLayer.addSublayer(noteLayer)

        coverLayer.contentsGravity = .resize
        // Covers are usually far bigger than the sleeve: filter the shrink, or it shimmers as it turns
        coverLayer.minificationFilter = .trilinear

        glareLayer.type = .radial
        glareLayer.colors = [
            NSColor.white.withAlphaComponent(TrackAnnouncementSleeve.glareAlpha).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        glareLayer.opacity = 0

        clipLayer.addSublayer(placeholderLayer)
        clipLayer.addSublayer(coverLayer)
        clipLayer.addSublayer(glareLayer)
        turnLayer.addSublayer(clipLayer)
        root.addSublayer(turnLayer)

        setAccessibilityElement(false)
        updatePlaceholder()
        updateContents()
        layoutLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The panel ignores the mouse anyway; never take a click meant for the strip's window
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            layoutLayers()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updatePlaceholder()
        updateContents()
    }

    /// The screen's pixels per point, for the images handed to the layers
    private var contentsScale: CGFloat {
        return window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private func updateContents() {
        withoutAnimation {
            if let artwork = artwork, artwork.size.width > 0, artwork.size.height > 0 {
                coverLayer.contentsScale = artwork.recommendedLayerContentsScale(contentsScale)
                // An image with nothing to draw draws nothing, as the flat strip would
                coverLayer.contents = artwork.representations.isEmpty
                    ? nil
                    : artwork.layerContents(forContentsScale: coverLayer.contentsScale)
                coverLayer.isHidden = false
            } else {
                coverLayer.contents = nil
                coverLayer.isHidden = true
            }
        }
        applyFade()
    }

    /// The music note, drawn at the strip's 36 points in 80 and in proportion here
    private func updatePlaceholder() {
        guard let note = TrackAnnouncementContentView.placeholderImage else { return }
        let factor = TrackAnnouncementSleeve.size / TrackAnnouncementLayout.artworkSize * scale
        let size = CGSize(width: note.size.width * factor, height: note.size.height * factor)
        let image = NSImage(size: size, flipped: false) { rect in
            note.draw(in: rect, from: .zero, operation: .sourceOver, fraction: TrackAnnouncementContentView.placeholderNoteAlpha)
            return true
        }
        withoutAnimation {
            noteLayer.contentsScale = image.recommendedLayerContentsScale(contentsScale)
            noteLayer.contents = image.layerContents(forContentsScale: noteLayer.contentsScale)
            noteLayer.bounds = CGRect(origin: .zero, size: size)
        }
    }

    /// The cover fades in over the placeholder, which fades out under it, as the flat strip
    /// draws it; with no cover, the placeholder alone
    private func applyFade() {
        let fade = Float(min(1, max(0, coverFade)))
        withoutAnimation {
            if coverLayer.isHidden {
                placeholderLayer.opacity = 1
            } else {
                placeholderLayer.opacity = 1 - fade
                coverLayer.opacity = fade
            }
        }
    }

    private func layoutLayers() {
        let sleeve = sleeveRect
        let radius = TrackAnnouncementSleeve.cornerRadius * scale
        let bounds = CGRect(origin: .zero, size: sleeve.size)
        withoutAnimation {
            turnLayer.bounds = bounds
            turnLayer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: min(radius, bounds.width / 2), cornerHeight: min(radius, bounds.height / 2), transform: nil)
            turnLayer.shadowRadius = TrackAnnouncementSleeve.shadowRadius * scale
            turnLayer.shadowOffset = CGSize(
                width: TrackAnnouncementSleeve.shadowOffset.width * scale,
                height: TrackAnnouncementSleeve.shadowOffset.height * scale
            )
            clipLayer.frame = bounds
            clipLayer.cornerRadius = radius
            clipLayer.borderWidth = TrackAnnouncementSleeve.rimWidth
            placeholderLayer.frame = bounds
            noteLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            coverLayer.frame = bounds
            glareLayer.frame = bounds
        }
        applyRise()
    }

    /// Where the rise puts the sleeve, and how big: all that changes on each step of the rise
    /// and the sink, so the rest of the layout isn't redone at the display's rate
    private func applyRise() {
        let sleeve = sleeveRect
        withoutAnimation {
            turnLayer.position = CGPoint(x: sleeve.midX, y: sleeve.midY - TrackAnnouncementSleeve.riseDrop(rise, scale: scale))
        }
        applyTransform()
    }

    private func applyTransform() {
        withoutAnimation {
            turnLayer.transform = TrackAnnouncementSleeve.transform(
                tilt,
                scale: scale,
                riseScale: TrackAnnouncementSleeve.riseScale(rise)
            )
            glareLayer.isHidden = !showsGlare || tilt.glare <= 0
            glareLayer.opacity = Float(tilt.glare)
            glareLayer.startPoint = tilt.glareCentre
            // A radial gradient's end point sets the ellipse's radii: most of the way across
            glareLayer.endPoint = CGPoint(x: tilt.glareCentre.x + 0.62, y: tilt.glareCentre.y + 0.62)
        }
    }
}
