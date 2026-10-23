//
//  SpotifyGlyph.swift
//  StarBar
//
//  The Spotify icon, drawn beside the menu bar's green heart while a song plays in Spotify.
//

import Cocoa

/// Spotify's icon: the circle with three sound waves knocked out of it.
///
/// It sits left of the heart and opens Spotify when clicked, because once the user has
/// connected their account the heart likes songs instead, and nothing else in the menu bar
/// went to Spotify. Spotify's design guidelines decide how it looks:
/// - the icon is never altered, so this is its own path, unchanged;
/// - the green icon goes only on black or white, and the menu bar is neither, so it is drawn
///   in one colour into the template strip, which the menu bar turns black or white;
/// - clear space of half the icon's height, which is the gap left before the heart
///   (`RatingControl.spotifyIconClearSpace`).
///
/// The outline is in a 24 x 24 box, in SVG coordinates where y grows downwards, so it is
/// flipped on the way out. Drawn with the even-odd rule, which cuts the waves out of the circle.
struct SpotifyGlyph {

    /// Fill the icon in the current colour, fitted inside `rect` and centred
    func draw(in rect: NSRect) {
        let bounds = SpotifyGlyph.outline.bounds
        guard bounds.width > 0, bounds.height > 0, rect.width > 0, rect.height > 0 else { return }
        guard let drawn = SpotifyGlyph.outline.copy() as? NSBezierPath else { return }

        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = AffineTransform.identity
        transform.translate(x: rect.midX, y: rect.midY)
        // Negative y flips it the right way up for AppKit
        transform.scale(x: scale, y: -scale)
        transform.translate(x: -bounds.midX, y: -bounds.midY)
        drawn.transform(using: transform)

        drawn.windingRule = .evenOdd
        drawn.fill()
    }

    /// Parsed once: the answer never changes and this runs on every menu bar redraw
    static let outline: NSBezierPath = SVGPath.path(fromPathData: pathData)

    /// The Spotify icon's path, in a 24 x 24 box: the circle, then the three waves from the
    /// bottom one up
    static let pathData =
"M12 0C5.4 0 0 5.4 0 12s5.4 12 12 12s12-5.4 12-12S18.66 0 12 0"
        + "m5.521 17.34c-.24.359-.66.48-1.021.24c-2.82-1.74-6.36-2.101-10.561-1.141c-.418.122-.779-.179-.899-.539"
        + "c-.12-.421.18-.78.54-.9c4.56-1.021 8.52-.6 11.64 1.32c.42.18.479.659.301 1.02"
        + "m1.44-3.3c-.301.42-.841.6-1.262.3c-3.239-1.98-8.159-2.58-11.939-1.38c-.479.12-1.02-.12-1.14-.6"
        + "s.12-1.021.6-1.141C9.6 9.9 15 10.561 18.72 12.84c.361.181.54.78.241 1.2"
        + "m.12-3.36C15.24 8.4 8.82 8.16 5.16 9.301c-.6.179-1.2-.181-1.38-.721c-.18-.601.18-1.2.72-1.381"
        + "c4.26-1.26 11.28-1.02 15.721 1.621c.539.3.719 1.02.419 1.56c-.299.421-1.02.599-1.559.3"

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct SpotifyGlyph_Preview: PreviewProvider {

    static var previews: some View {
        ForEach([CGFloat(16), 64, 128], id: \.self) { size in
            NSViewPreview {
                let image = NSImage(size: NSSize(width: size, height: size))
                image.lockFocus()
                NSColor.black.setFill()
                SpotifyGlyph().draw(in: NSRect(x: 0, y: 0, width: size, height: size))
                image.unlockFocus()
                return NSImageView(image: image)
            }
        }
    }

}

#endif
