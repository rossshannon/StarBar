//
//  AddToLibraryBadge.swift
//  StarBar
//
//  What the menu bar shows in place of the stars when the track can't be rated.
//

import Cocoa

/// A music note and a plus, then the favorite heart: the strip the menu bar shows while an
/// Apple Music track that isn't in the library is playing.
///
/// Music refuses to store a rating on such a track (see `iTunesTrack.isCatalogStream`), so
/// showing five stars invites a rating that is silently thrown away. The note and the plus are
/// **one button**: clicking anywhere left of the heart adds the song to the library, after
/// which it rates normally. The heart works either way, so it keeps its usual slot.
///
/// The layout matches `Stars`: a spacing before each glyph and one after, then a spacing and
/// the heart. That keeps `RatingControl.favoriteMinX` the same expression in both modes.
struct AddToLibraryBadge {

    /// One glyph's box, the same size as a star
    let glyphSize: NSSize
    let spacing: CGFloat
    let isFavorited: Bool
    /// The song is being added and we're waiting for Music. Measured at about 3.5 seconds,
    /// which is far too long for the button to look untouched, so the plus is left out and
    /// `MenuBarRatingControl` spins a real progress indicator in its place.
    let isPending: Bool

    init(glyphSize: NSSize, spacing: CGFloat, isFavorited: Bool = false, isPending: Bool = false) {
        self.glyphSize = glyphSize
        self.spacing = spacing
        self.isFavorited = isFavorited
        self.isPending = isPending
    }

    /// Number of glyphs before the heart: the note and the plus
    static let glyphCount = 2

    /// Left edge of the note
    var noteMinX: CGFloat {
        return spacing
    }

    /// Left edge of the plus, where the spinner goes while the add is in flight.
    /// The plus sits straight after the note with no gap, so the two read as one control
    /// rather than as a note and a separate button.
    var plusMinX: CGFloat {
        return spacing + glyphSize.width
    }

    /// Width of the note and plus, before the heart slot: a spacing, the two glyphs touching,
    /// then a spacing. `Stars.starsWidth` is the same shape but spaces its five stars apart.
    var contentWidth: CGFloat {
        return CGFloat(AddToLibraryBadge.glyphCount) * glyphSize.width + CGFloat(2) * spacing
    }

    /// The strip, drawn as a template image the menu bar recolours
    var image: NSImage {
        let width = contentWidth + spacing + glyphSize.width
        let height = glyphSize.height

        let canvasImage = NSImage(size: NSSize(width: width, height: height))
        canvasImage.lockFocus()

        NSColor.black.set()
        AppleMusicGlyph().draw(in: NSRect(origin: CGPoint(x: noteMinX, y: 0), size: glyphSize))

        // The plus is left out while the add is in flight: the spinner takes its place, and
        // drawing both would show the plus through the gaps in the circle
        if !isPending {
            AddToLibraryBadge.drawSymbol("plus", in: NSRect(origin: CGPoint(x: plusMinX, y: 0), size: glyphSize))
        }

        // The heart keeps the slot it has in the stars strip. A favorited track leaves it
        // empty, because `MenuBarRatingControl` draws the coloured heart over the top.
        if !isFavorited {
            let heartRect = NSRect(
                origin: CGPoint(x: contentWidth + spacing, y: 0),
                size: glyphSize
            )
            Stars.drawFavoriteHeartOutline(in: heartRect)
        }

        canvasImage.unlockFocus()
        return canvasImage
    }

    /// Draw one SF Symbol centred in `rect`, in black so the template image picks it up.
    ///
    /// Only the plus comes from SF Symbols. The note is drawn by `AppleMusicGlyph`, because
    /// SF Symbols has no beamed pair and a single note doesn't read as Apple Music.
    private static func drawSymbol(_ name: String, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.72, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }

        let size = symbol.size
        let drawRect = NSRect(
            x: rect.midX - 0.5 * size.width,
            y: rect.midY - 0.5 * size.height,
            width: size.width,
            height: size.height
        )

        NSColor.black.set()
        symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct AddToLibraryBadge_Preview: PreviewProvider {

    static var previews: some View {
        Group {
            NSViewPreview {
                let badge = AddToLibraryBadge(glyphSize: NSSize(width: 16, height: 16), spacing: 4)
                return NSImageView(image: badge.image)
            }
            NSViewPreview {
                let badge = AddToLibraryBadge(glyphSize: NSSize(width: 64, height: 64), spacing: 16, isFavorited: true)
                return NSImageView(image: badge.image)
            }
        }
    }

}

#endif
