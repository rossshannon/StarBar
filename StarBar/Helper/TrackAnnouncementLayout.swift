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
    /// Artwork inset from the left; it is centred vertically
    static let artworkInset: CGFloat = 8
    /// Gap between the artwork and the text
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
    /// The black wash over Liquid Glass, just enough for the white text; the blue is the
    /// glass view's own tint
    static let glassTintAlpha: CGFloat = 0.1
    static let shadowOffset = CGSize(width: 0, height: -2)
    static let shadowBlurRadius: CGFloat = 3
    /// The colour Liquid Glass is tinted with
    static let glassTint = NSColor.systemBlue.withAlphaComponent(0.35)
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

    /// The panel spans the whole screen width and rests on the visible frame's bottom edge:
    /// above a Dock at the bottom, and running behind a Dock at the side (the panel's window
    /// level is just below the Dock's)
    static func panelFrame(screenFrame: CGRect, visibleFrame: CGRect, scale: CGFloat = 1) -> CGRect {
        return CGRect(
            x: screenFrame.minX,
            y: visibleFrame.minY,
            width: screenFrame.width,
            height: TrackAnnouncementLayout.stripHeight(scale: scale)
        )
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
