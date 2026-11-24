//
//  StarFinaleView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-24.
//

import Cocoa

/// One frame of the five-star finale (`StarFinale`): the small coloured stars and their dots,
/// around `origin`, the first star's centre. Whoever owns it steps `elapsed` with the stars'
/// flourish; it never animates by itself, because on macOS 27 a Core Animation animation on
/// the strip's panel ran to completion without being drawn.
///
/// The menu bar's finale window holds one over the stars, and the strip's panel one beside the
/// strip. Neither draws the five stars themselves, which stay where they are.
final class StarFinaleView: NSView {

    /// The finale to draw; nil draws nothing
    var finale: StarFinale? {
        didSet { needsDisplay = true }
    }
    var elapsed: TimeInterval = 0 {
        didSet { needsDisplay = true }
    }
    /// The first star's centre in this view
    var origin: NSPoint = .zero {
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

    /// The frame, in whole points, that holds everything `finale` draws around a first star
    /// centred at `centre`, with room to spare, and where that centre falls inside it: the
    /// frame the menu bar's finale window and the strip's finale view are given
    static func frame(for finale: StarFinale, firstStarAt centre: NSPoint) -> (frame: NSRect, origin: NSPoint) {
        let reach = finale.bounds.insetBy(dx: -2, dy: -2).offsetBy(dx: centre.x, dy: centre.y)
        let minX = reach.minX.rounded(.down)
        let minY = reach.minY.rounded(.down)
        let frame = NSRect(x: minX, y: minY, width: reach.maxX.rounded(.up) - minX, height: reach.maxY.rounded(.up) - minY)
        return (frame, NSPoint(x: centre.x - frame.minX, y: centre.y - frame.minY))
    }

    /// Never in the way of a click: the strip's panel and the finale's window ignore the mouse
    /// anyway, and this keeps it so if either is ever reused
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let finale = finale else { return }
        for piece in finale.pieces(at: elapsed) where piece.radius > 0.05 {
            StarFinale.colour(of: piece).setFill()
            let centre = NSPoint(x: origin.x + piece.offset.dx, y: origin.y + piece.offset.dy)
            StarFinaleView.path(for: piece, at: centre).fill()
        }
    }

    /// A piece's outline with its centre at `centre`: a five-pointed star, turned about its
    /// own middle as far as it has turned, or its dot
    static func path(for piece: StarFinale.Piece, at centre: NSPoint) -> NSBezierPath {
        guard piece.isStar else {
            return NSBezierPath(ovalIn: NSRect(x: centre.x - piece.radius, y: centre.y - piece.radius,
                                               width: 2 * piece.radius, height: 2 * piece.radius))
        }
        let sine = sin(piece.rotation)
        let cosine = cos(piece.rotation)
        let points = Star.starPoints(at: .zero, with: piece.radius).map { point in
            NSPoint(x: centre.x + point.x * cosine - point.y * sine,
                    y: centre.y + point.x * sine + point.y * cosine)
        }
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points[1...] {
            path.line(to: point)
        }
        path.close()
        return path
    }

}
