//
//  Stars.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-7-1.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa

struct Stars {
    
    let stars: [Star]
    let spacing: CGFloat
    /// Adds a favorite heart slot after the stars (menu bar only, not preference labels)
    let showsFavorite: Bool
    let isFavorited: Bool

    init(stars: [Star], spacing: CGFloat, showsFavorite: Bool = false, isFavorited: Bool = false) {
        self.stars = stars
        self.spacing = spacing
        self.showsFavorite = showsFavorite
        self.isFavorited = isFavorited
    }

    /// Star styles for a Music rating, 0 to 100: full stars, then a half star, then dots
    static func styles(forRating rating: Int) -> [Star.Style] {
        let clamped = min(100, max(0, rating))
        let fullStarCount = clamped / 20
        let halfStarCount = (clamped - 20 * fullStarCount) / 10
        let dotCount = 5 - fullStarCount - halfStarCount
        return Array(repeating: .full, count: fullStarCount)
            + Array(repeating: .half, count: halfStarCount)
            + Array(repeating: .dot, count: dotCount)
    }

    /// The five stars and the heart for a rating, as the menu bar draws them
    static func rating(_ rating: Int, starSize: NSSize, spacing: CGFloat, isFavorited: Bool) -> Stars {
        return Stars(
            stars: styles(forRating: rating).map { Star(size: starSize, style: $0) },
            spacing: spacing,
            showsFavorite: true,
            isFavorited: isFavorited
        )
    }

    /// Width of the five stars with their spacing, before the heart slot
    var starsWidth: CGFloat {
        return stars.map { $0.size.width }.reduce(into: 0.0, { $0 += $1 }) + CGFloat(stars.count + 1) * spacing
    }
    
    var image: NSImage {
        // spacing | star | spacing | … | star | spacing, then optionally spacing | heart.
        // Must match RatingControl.starsImage and favoriteMinX, or drawing squeezes the image.
        let starsWidth = self.starsWidth
        let heartWidth = stars.first?.size.width ?? 0
        let width = showsFavorite ? starsWidth + spacing + heartWidth : starsWidth
        
        let height = stars.map { $0.size.height }.max() ?? 0.0
        
        let canvasImage = NSImage(size: NSSize(width: width, height: height))
        canvasImage.lockFocus()
        
        // Draw stars
        for (i, star) in stars.enumerated() {
            let origin = CGPoint(x: spacing * CGFloat(1 + i) + star.size.width * CGFloat(i), y: 0.5 * (height - star.size.height))
            star.image.draw(in: NSRect(origin: origin, size: star.size))
        }
        
        // Draw favorite heart
        if showsFavorite, let firstStar = stars.first {
            let starSize = firstStar.size
            let favoriteOrigin = CGPoint(x: starsWidth + spacing, y: 0.5 * (height - starSize.height))
            
            let favoriteRect = NSRect(origin: favoriteOrigin, size: starSize)
            drawFavoriteHeart(in: favoriteRect, filled: isFavorited)
        }
        
        canvasImage.unlockFocus()
        
        return canvasImage
    }
    
    /// Fill colour for a favorited track's heart. It is drawn by `MenuBarRatingControl` as a
    /// separate, non-template image, because the template `starsImage` can only be one colour.
    static let favoriteHeartColor = NSColor(srgbRed: 0xF5 / 255.0, green: 0x00 / 255.0, blue: 0x2E / 255.0, alpha: 1)

    /// Filled heart in `favoriteHeartColor`, the same size as one star.
    static func filledFavoriteHeartImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let path = Stars.heartPath(in: rect, lineWidth: 1.0)
            Stars.favoriteHeartColor.setFill()
            Stars.favoriteHeartColor.setStroke()
            path.fill()
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Outline heart for the template image. A favorited track leaves this slot empty, so the
    /// coloured heart drawn on top has no template-coloured edge around it.
    private func drawFavoriteHeart(in rect: NSRect, filled: Bool) {
        guard !filled else { return }
        NSColor.black.setStroke()
        Stars.heartPath(in: rect, lineWidth: 1.5).stroke()
    }

    /// Heart outline for Music's "favorited" flag, so it reads differently from the rating stars.
    ///
    /// Two circles side by side, joined by tangent lines to a point at the bottom.
    /// AppKit's y axis points up, and arc angles are in degrees.
    private static func heartPath(in rect: NSRect, lineWidth: CGFloat) -> NSBezierPath {
        // Heart is 4r wide and (2 + 1.414)r tall; leave room for the stroke
        let radius = 0.95 * min((rect.width - lineWidth) / 4, (rect.height - lineWidth) / 3.414)
        let centerY = rect.midY + 0.707 * radius
        let leftCenter = NSPoint(x: rect.midX - radius, y: centerY)
        let rightCenter = NSPoint(x: rect.midX + radius, y: centerY)
        let bottom = NSPoint(x: rect.midX, y: centerY - 2.414 * radius)

        let path = NSBezierPath()
        path.move(to: bottom)
        path.appendArc(withCenter: leftCenter, radius: radius, startAngle: 225, endAngle: 0, clockwise: true)
        path.appendArc(withCenter: rightCenter, radius: radius, startAngle: 180, endAngle: -45, clockwise: true)
        path.close()
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth
        return path
    }
    
}
