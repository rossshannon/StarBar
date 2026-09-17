//
//  TrackAnnouncementLayout.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Foundation
import CoreGraphics
import AppKit

/// Where everything goes on the announcement strip. The base numbers are the original Growl
/// "Music Video" display's: a 96 point strip, 80 point artwork inset 8 points, bold 16 point
/// title over 12 point text, black at 60%, sliding in 0.3 seconds and holding for 5. Growl
/// drew for 1280 by 800 screens, so everything scales up with the screen height, and the text
/// block is centred in the strip rather than sitting near its bottom edge.
enum TrackAnnouncementLayout {

    /// Strip height, in points, at scale 1
    static let height: CGFloat = 96
    static let artworkSize: CGFloat = 80
    /// Artwork inset from the left, Growl's 8; it is centred vertically. The glass's 8 point
    /// corner sits happily beside the square artwork.
    static let artworkInset: CGFloat = 8
    /// Gap between the artwork and the text, Growl's 16
    static let textGap: CGFloat = 16
    /// Gap between the text and the right edge
    static let textTrailingPad: CGFloat = 16
    static let titleFontSize: CGFloat = 16
    static let detailFontSize: CGFloat = 12
    static let titleHeight: CGFloat = 20
    static let detailHeight: CGFloat = 16
    /// Vertical gap between text lines
    static let lineGap: CGFloat = 2
    /// The rating row: five stars and the heart, drawn like the menu bar's
    static let ratingHeight: CGFloat = 16
    static let ratingStarSize: CGFloat = 12
    static let ratingSpacing: CGFloat = 3
    static let backgroundAlpha: CGFloat = 0.6
    /// The black wash over a blurred backdrop, lighter than the classic strip
    static let blurTintAlpha: CGFloat = 0.25
    /// No wash over Liquid Glass: the darkness is the glass view's own tint, so the glass
    /// material is what shows
    static let glassTintAlpha: CGFloat = 0
    static let shadowOffset = CGSize(width: 0, height: -2)
    static let shadowBlurRadius: CGFloat = 3
    /// The colour Liquid Glass is tinted with. Alpha 0 means no tint at all: the glass's
    /// own frost and lensing are what shows, and the text shadow does the work of legibility.
    static let glassTint = NSColor.black.withAlphaComponent(0)
    /// The glass strip's top corners. Liquid Glass shows its lensing and highlights along a
    /// curved rim, so square corners read as a blur; 8 is the radius Ross picked from a grid
    /// of samples, tight enough to sit beside the square artwork.
    static let glassCornerRadius: CGFloat = 8
    /// How far the glass stands in from each screen edge, so that the top corners exist
    static let glassSideInset: CGFloat = 16
    /// The artwork's corners on the glass strip: a little rounding, to sit with the glass's
    /// own corners. Square on the classic and blur strips, as Growl drew it.
    static let glassArtworkCornerRadius: CGFloat = 6

    static func artworkCornerRadius(for style: TrackAnnouncementStyle, scale: CGFloat = 1) -> CGFloat {
        return style == .glass ? glassArtworkCornerRadius * scale : 0
    }
    /// The sheen that suggests a domed surface: a rim light fading down from the top edge
    /// over the top part of the strip, and a soft shade rising from the bottom. Drawn over
    /// the glass, clipped to its shape, because the glass view's own geometry is flat.
    static let glassSheenHighlightAlpha: CGFloat = 0.35
    static let glassSheenHighlightFraction: CGFloat = 0.5
    /// Kept faint: the shade is the one part of the sheen that darkens the glass, and it
    /// read as a tint
    static let glassSheenShadeAlpha: CGFloat = 0.07
    static let glassSheenShadeFraction: CGFloat = 0.5
    /// A crisp bright line along the top edge, the specular catch of a curved surface; over
    /// light content the soft highlight alone disappears
    static let glassSheenEdgeAlpha: CGFloat = 0.6
    static let glassSheenEdgeWidth: CGFloat = 1

    /// The glass view's frame inside the strip: inset from the sides, and hanging below the
    /// strip by its corner radius so that the bottom corners are always below the screen edge
    /// and only the top corners round. `leadingInset` and `trailingInset` are the strip's
    /// Dock insets.
    static func glassFrame(in size: CGSize, scale: CGFloat = 1, leadingInset: CGFloat = 0, trailingInset: CGFloat = 0, cornerRadius: CGFloat = glassCornerRadius) -> CGRect {
        let inset = glassSideInset * scale
        let overhang = (cornerRadius * scale).rounded(.up)
        return CGRect(
            x: leadingInset + inset,
            y: -overhang,
            width: max(0, size.width - leadingInset - trailingInset - 2 * inset),
            height: size.height + overhang
        )
    }

    /// The space the content keeps clear at each side: the Dock insets, plus the glass inset
    /// for the glass style so that text never hangs past the glass
    static func contentInsets(for style: TrackAnnouncementStyle, scale: CGFloat = 1, leadingInset: CGFloat = 0, trailingInset: CGFloat = 0) -> (leading: CGFloat, trailing: CGFloat) {
        guard style == .glass else { return (leadingInset, trailingInset) }
        let inset = glassSideInset * scale
        return (leadingInset + inset, trailingInset + inset)
    }
    /// Slide in and slide out, each
    static let slideDuration: TimeInterval = 0.3
    /// Time fully on screen between the slides
    static let holdDuration: TimeInterval = 5.0

    /// Screen height at which the strip is drawn at scale 1
    static let referenceScreenHeight: CGFloat = 1000
    static let maximumScale: CGFloat = 2

    /// How much bigger to draw everything on a screen this tall: 1 up to the reference
    /// height, then in proportion, capped so a wall of pixels doesn't get a wall of strip
    static func scale(forScreenHeight screenHeight: CGFloat) -> CGFloat {
        return min(maximumScale, max(1, screenHeight / referenceScreenHeight))
    }

    /// The strip's height at `scale`, in whole points, because window frames are
    static func stripHeight(scale: CGFloat) -> CGFloat {
        return (height * scale).rounded(.up)
    }

    /// Rectangles for the strip's contents, in the strip's own coordinates
    struct Frames: Equatable {
        let artwork: CGRect
        let title: CGRect
        /// Nil when the announcement has no artist
        let artist: CGRect?
        /// Nil when the announcement has no album
        let album: CGRect?
        /// The stars and heart, always the last row
        let rating: CGRect
    }

    /// Lay out a strip of `size` drawn at `scale`. The text block (title, the detail lines
    /// that exist, and the rating row) is centred vertically.
    ///
    /// - Parameters:
    ///   - leadingInset: space at the left the content must keep clear, such as a Dock the
    ///     strip runs behind
    ///   - trailingInset: the same at the right
    static func frames(in size: CGSize, scale: CGFloat = 1, leadingInset: CGFloat = 0, trailingInset: CGFloat = 0, hasArtist: Bool = true, hasAlbum: Bool = true) -> Frames {
        let artworkSize = TrackAnnouncementLayout.artworkSize * scale
        let inset = leadingInset + artworkInset * scale
        let textX = inset + artworkSize + textGap * scale
        let textWidth = max(0, size.width - trailingInset - textX - textTrailingPad * scale)
        let titleHeight = TrackAnnouncementLayout.titleHeight * scale
        let detailHeight = TrackAnnouncementLayout.detailHeight * scale
        let ratingHeight = TrackAnnouncementLayout.ratingHeight * scale
        let lineGap = TrackAnnouncementLayout.lineGap * scale

        let artwork = CGRect(x: inset, y: (size.height - artworkSize) / 2, width: artworkSize, height: artworkSize)

        let detailLines = (hasArtist ? 1 : 0) + (hasAlbum ? 1 : 0)
        let blockHeight = titleHeight + CGFloat(detailLines) * (detailHeight + lineGap) + ratingHeight + lineGap
        var y = (size.height + blockHeight) / 2
        y -= titleHeight
        let title = CGRect(x: textX, y: y, width: textWidth, height: titleHeight)
        var artist: CGRect?
        var album: CGRect?
        if hasArtist {
            y -= lineGap + detailHeight
            artist = CGRect(x: textX, y: y, width: textWidth, height: detailHeight)
        }
        if hasAlbum {
            y -= lineGap + detailHeight
            album = CGRect(x: textX, y: y, width: textWidth, height: detailHeight)
        }
        y -= lineGap + ratingHeight
        let rating = CGRect(x: textX, y: y, width: textWidth, height: ratingHeight)
        return Frames(artwork: artwork, title: title, artist: artist, album: album, rating: rating)
    }

    /// Where to draw an image of `imageSize` inside `slot`: scaled down to fit, never scaled
    /// up, and centred. Growl's `drawScaledInRect:`.
    static func artworkDrawingRect(imageSize: CGSize, in slot: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return slot }
        let scale = min(1, min(slot.width / imageSize.width, slot.height / imageSize.height))
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: slot.midX - size.width / 2,
            y: slot.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

}

/// Where the strip's panel goes on a screen, and how it moves
enum TrackAnnouncementPlacement {

    enum Transition: Equatable {
        case slide
        case fade
    }

    /// Empty window above the strip. Liquid Glass refracts what lies just outside its edge
    /// into its rim, and a backdrop only covers the window: with the window's top flush with
    /// the glass's top there was nothing to bend, and the straight edge showed no lensing at
    /// all while the corners, with window either side of them, did. The panel ignores the
    /// mouse, so the headroom costs nothing.
    static let panelHeadroom: CGFloat = 48

    static func panelHeadroom(scale: CGFloat) -> CGFloat {
        return (panelHeadroom * scale).rounded(.up)
    }

    /// The panel spans the whole screen width and rests on the visible frame's bottom edge:
    /// above a Dock at the bottom, and running behind a Dock at the side (the panel's window
    /// level is just below the Dock's). It is taller than the strip by the headroom.
    static func panelFrame(screenFrame: CGRect, visibleFrame: CGRect, scale: CGFloat = 1) -> CGRect {
        return CGRect(
            x: screenFrame.minX,
            y: visibleFrame.minY,
            width: screenFrame.width,
            height: TrackAnnouncementLayout.stripHeight(scale: scale) + panelHeadroom(scale: scale)
        )
    }

    /// The strip's size inside the panel: the panel's width, the strip's height
    static func stripSize(panelFrame: CGRect, scale: CGFloat = 1) -> CGSize {
        return CGSize(width: panelFrame.width, height: TrackAnnouncementLayout.stripHeight(scale: scale))
    }

    /// The strip view's origin inside the panel: on screen, or just below it
    static func stripOrigin(shown: Bool, scale: CGFloat = 1) -> CGPoint {
        return CGPoint(x: 0, y: shown ? 0 : -TrackAnnouncementLayout.stripHeight(scale: scale))
    }

    static func transition(reduceMotion: Bool) -> Transition {
        return reduceMotion ? .fade : .slide
    }

    /// Growl's slide curve (NSAnimationEaseInOut): slow at both ends, 0 to 1 over 0 to 1
    static func easeInOut(_ progress: Double) -> Double {
        let clamped = min(1, max(0, progress))
        return 0.5 - 0.5 * cos(.pi * clamped)
    }

}
