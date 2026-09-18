//
//  AppleMusicGlyph.swift
//  StarBar
//
//  The Apple Music icon, drawn on the "add to library" button.
//

import Cocoa

/// The Apple Music icon: the rounded square with the beamed pair of notes knocked out of it.
///
/// The whole icon rather than the note alone, so the button reads as "add to Apple Music"
/// rather than as a generic music button. SF Symbols has nothing like it: "music.note" is a
/// single note and "music.quarternote.3" is three separate ones.
///
/// The outline is the icon's own path, in a 512 x 512 box, in SVG coordinates where y grows
/// downwards -- so it is flipped on the way out. Drawn with the even-odd rule, which is what
/// cuts the note out of the square.
struct AppleMusicGlyph {

    /// Breathing room inside the glyph box, as a fraction of it. The icon is a solid shape
    /// where its neighbours are thin ones, so a little inset stops it looking oversized.
    static let inset: CGFloat = 0.06

    /// Fill the icon in the current colour, fitted inside  and centred.
    func draw(in rect: NSRect) {
        let bounds = AppleMusicGlyph.outline.bounds
        guard bounds.width > 0, bounds.height > 0, rect.width > 0, rect.height > 0 else { return }
        guard let drawn = AppleMusicGlyph.outline.copy() as? NSBezierPath else { return }

        let box = rect.insetBy(dx: rect.width * AppleMusicGlyph.inset,
                               dy: rect.height * AppleMusicGlyph.inset)
        let scale = min(box.width / bounds.width, box.height / bounds.height)

        var transform = AffineTransform.identity
        transform.translate(x: box.midX, y: box.midY)
        // Negative y flips it the right way up for AppKit
        transform.scale(x: scale, y: -scale)
        transform.translate(x: -bounds.midX, y: -bounds.midY)
        drawn.transform(using: transform)

        // Even-odd is what knocks the note out of the square
        drawn.windingRule = .evenOdd
        drawn.fill()
    }

    /// Parsed once: the answer never changes and this runs on every menu bar redraw
    static let outline: NSBezierPath = SVGPath.path(fromPathData: pathData)

    /// The Apple Music icon's path, in a 512 x 512 box
    private static let pathData =
"M511.8,130.7c0-15.7-1.3-31.4-5.1-46.7C500,56,484,34.7,460.2,19C448,11,434.5,6.1,420.1,3.5c-11-2-22.2-2.9-33.3-3.2 "
        + "L384.1,0H127.6c-3.2,0.3-6.5,0.4-9.7,0.6C102,1.5,86.2,3.2,71.1,9.2C42.7,20.4,22.1,40.1,10.1,68.4C5.9,78,3.8,88.2,2.3,98.5 "
        + "c-1.2,8.3-1.9,16.8-2.2,25.2l-0.2,2v260.7c0.2,3,0.3,6,0.5,9c1.1,17.4,3.3,34.7,10.7,50.7c13.8,30.3,37.1,50.2,69,59.7 "
        + "c8.9,2.8,18.2,4,27.6,4.8c11.8,1.2,23.7,1.3,35.5,1.3h235.3c11.2,0,22.3-0.7,33.5-2.2c17.6-2.2,34.1-7.4,49-17.2 "
        + "c17.9-11.8,31.4-27.5,40.1-47.1c4-9,6.2-18.6,7.9-28.2c2.4-14.4,2.9-29,2.9-43.6c-0.1-81,0-162-0.1-243L511.8,130.7z "
        + "M374.8,215.8 "
        + "v121.8c0,8.9-1.2,17.7-5.2,25.7c-6.2,12.6-16.2,20.5-29.6,24.3c-7.4,2.2-15.1,3.3-22.8,3.7c-20.2,1-37.8-12.7-41.4-32.7 "
        + "c-3.1-16.5,4.8-34.7,22.2-43.2c6.8-3.3,14.2-5.3,21.7-6.8c8.1-1.7,16.2-3.3,24.2-5.2c5.9-1.3,9.7-4.9,10.9-11l0.4-4.1 "
        + "c0-38.7,0-77.5,0-116.2l-0.6-3.9c-0.8-3.2-3.2-5.2-6.5-5c-3.4,0.2-6.7,0.7-10.1,1.4c-16.3,3.2-32.5,6.4-48.7,9.7l-78.9,15.9 "
        + "l-1.1,0.3c-5.9,1.7-8,4.3-8.3,10.5v2.7c-0.1,55.5,0,111-0.1,166.5c0,9-1,17.8-4.6,26.2c-5.9,13.7-16.4,22.3-30.6,26.3 "
        + "c-7.5,2.2-15.2,3.4-23,3.7c-20.4,0.8-37.4-12.8-40.9-32.9c-3-17.3,4.9-36,24.6-44.3c7.7-3.2,15.6-4.9,23.7-6.6 "
        + "c6.1-1.2,12.3-2.5,18.3-3.7c8.2-1.7,12.4-6.9,12.8-15.2v-3.2c0-63.2,0-126.3,0-189.5c0-2.7,0.3-5.3,0.9-7.9 "
        + "c1.5-6.1,5.8-9.6,11.7-11c5.4-1.4,11-2.4,16.5-3.6c15.7-3.2,31.2-6.3,46.9-9.4l48.4-9.8c14.3-2.8,28.6-5.7,42.9-8.6 "
        + "c4.7-0.9,9.4-1.9,14.2-2.3c6.6-0.6,11.2,3.6,11.8,10.3c0.2,1.6,0.3,3.2,0.3,4.7C374.8,134.2,374.8,174.9,374.8,215.8L374.8,215.8z "

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct AppleMusicGlyph_Preview: PreviewProvider {

    static var previews: some View {
        ForEach([CGFloat(16), 64, 128], id: \.self) { size in
            NSViewPreview {
                let image = NSImage(size: NSSize(width: size, height: size))
                image.lockFocus()
                NSColor.black.setFill()
                AppleMusicGlyph().draw(in: NSRect(x: 0, y: 0, width: size, height: size))
                image.unlockFocus()
                return NSImageView(image: image)
            }
        }
    }

}

#endif
