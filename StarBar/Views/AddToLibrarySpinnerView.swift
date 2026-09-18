//
//  AddToLibrarySpinnerView.swift
//  StarBar
//
//  Apple Music's "working" indicator: a circle with a gap in it, turning.
//

import Cocoa

/// A circle with a gap, turning: what Apple Music shows while it adds a song.
///
/// `NSProgressIndicator`'s spinner is the spoked wheel, which is the wrong indicator here --
/// this is the one the user has just seen in Music itself.
///
/// The angle is stepped from outside, on each display refresh, rather than animated with Core
/// Animation. A Core Animation animation on the track announcement's panel ran to completion
/// on macOS 27 without ever being drawn, and the menu bar is the same kind of window.
final class AddToLibrarySpinnerView: NSView {

    /// How much of the circle is missing, in degrees
    static let gapDegrees: CGFloat = 70
    /// Stroke width as a fraction of the circle's diameter
    static let lineWidthRatio: CGFloat = 0.12
    /// Turns per second
    static let turnsPerSecond: CGFloat = 1.0

    /// Where the gap is, in degrees. Set it from a timer to make the circle turn.
    var angle: CGFloat = 0 {
        didSet {
            guard angle != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Clicks belong to the status item button underneath, not to this
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override var isFlipped: Bool {
        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height)
        guard diameter > 0 else { return }

        let lineWidth = diameter * AddToLibrarySpinnerView.lineWidthRatio
        let radius = diameter / 2 - lineWidth / 2

        let path = NSBezierPath()
        path.appendArc(
            withCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: radius,
            startAngle: angle,
            endAngle: angle + (360 - AddToLibrarySpinnerView.gapDegrees)
        )
        path.lineWidth = lineWidth
        path.lineCapStyle = .round

        // The menu bar decides whether its contents are dark or light, and the status item's
        // appearance already reflects that, so the label colour resolves to the right one.
        NSColor.labelColor.setStroke()
        path.stroke()
    }

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct AddToLibrarySpinnerView_Preview: PreviewProvider {

    static var previews: some View {
        NSViewPreview {
            let view = AddToLibrarySpinnerView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
            view.angle = 45
            return view
        }
    }

}

#endif
