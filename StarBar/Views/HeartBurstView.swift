//
//  HeartBurstView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-09.
//

import Cocoa

/// One frame of the heart changing (`HeartChange`): the burst's ring and dots, and, when it is
/// given them, the outgoing and incoming hearts, all around `centre`. Whoever owns it steps
/// `elapsed` on a display link; it never animates by itself, because on macOS 27 a Core
/// Animation animation on the strip's panel ran to completion without being drawn.
///
/// The menu bar's burst window draws only the ring and dots, since the heart stays in the
/// status item; the strip's draws its hearts too, in place of the strip's own.
final class HeartBurstView: NSView {

    var change: HeartChange? {
        didSet { needsDisplay = true }
    }
    var elapsed: TimeInterval = 0 {
        didSet { needsDisplay = true }
    }
    /// The burst's geometry; nil draws only the hearts
    var burst: HeartBurst? {
        didSet { needsDisplay = true }
    }
    var palette: HeartBurstPalette = .music {
        didSet { needsDisplay = true }
    }
    /// The heart's centre in this view; nil is the middle of the view
    var centre: NSPoint? {
        didSet { needsDisplay = true }
    }
    /// The heart being replaced and the one taking its place, each drawn `size` at rest. Nil
    /// leaves the hearts to someone else.
    var hearts: (outgoing: NSImage, incoming: NSImage, size: NSSize)? {
        didSet { needsDisplay = true }
    }
    /// The shadow the hearts are drawn with, to match the text they sit beside
    var heartShadow: NSShadow? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Never in the way of a click: the strip's panel and the burst's window ignore the mouse
    /// anyway, and this keeps it so if either is ever reused
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let change = change else { return }
        let centre = self.centre ?? NSPoint(x: bounds.midX, y: bounds.midY)

        if change == .burst, let burst = burst {
            if let ring = burst.ring(at: elapsed) {
                let path = NSBezierPath(ovalIn: circle(around: centre, radius: ring.outerRadius))
                if ring.innerRadius > 0 {
                    path.append(NSBezierPath(ovalIn: circle(around: centre, radius: ring.innerRadius)))
                }
                path.windingRule = .evenOdd
                palette.ringColour(mix: ring.colourMix).setFill()
                path.fill()
            }
            for dot in burst.dots(at: elapsed) where dot.radius > 0.05 {
                palette.colour(of: dot).setFill()
                let dotCentre = NSPoint(x: centre.x + dot.offset.dx, y: centre.y + dot.offset.dy)
                NSBezierPath(ovalIn: circle(around: dotCentre, radius: dot.radius)).fill()
            }
        }

        guard let hearts = hearts else { return }
        let slot = NSRect(x: centre.x - hearts.size.width / 2, y: centre.y - hearts.size.height / 2,
                          width: hearts.size.width, height: hearts.size.height)
        NSGraphicsContext.saveGraphicsState()
        heartShadow?.set()
        draw(hearts.outgoing, as: change.outgoing(at: elapsed), in: slot)
        draw(hearts.incoming, as: change.incoming(at: elapsed), in: slot)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func draw(_ image: NSImage, as glyph: HeartGlyph, in slot: NSRect) {
        guard glyph.isVisible else { return }
        image.draw(in: glyph.frame(for: slot), from: .zero, operation: .sourceOver,
                   fraction: glyph.opacity, respectFlipped: true, hints: nil)
    }

    private func circle(around centre: NSPoint, radius: CGFloat) -> NSRect {
        return NSRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)
    }

}
