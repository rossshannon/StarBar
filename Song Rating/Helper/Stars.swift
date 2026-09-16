//
//  Stars.swift
//  Song Rating
//
//  Created by Cirno MainasuK on 2019-7-1.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa

struct Stars {
    
    let stars: [Star]
    let spacing: CGFloat
    let isLoved: Bool
    
    init(stars: [Star], spacing: CGFloat, isLoved: Bool = false) {
        self.stars = stars
        self.spacing = spacing
        self.isLoved = isLoved
    }
    
    var image: NSImage {
        // Calculate width including heart icon space
        let starsWidth = stars.map { $0.size.width }.reduce(into: 0.0, { $0 += $1 }) + CGFloat(stars.count + 1) * spacing
        // Add extra space for heart icon
        let heartWidth = stars.first?.size.width ?? 0
        let width = starsWidth + spacing + heartWidth + spacing
        
        let height = stars.map { $0.size.height }.max() ?? 0.0
        
        let canvasImage = NSImage(size: NSSize(width: width, height: height))
        canvasImage.lockFocus()
        
        // Draw stars
        for (i, star) in stars.enumerated() {
            let origin = CGPoint(x: spacing * CGFloat(1 + i) + star.size.width * CGFloat(i), y: 0.5 * (height - star.size.height))
            star.image.draw(in: NSRect(origin: origin, size: star.size))
        }
        
        // Draw favorite heart
        if let firstStar = stars.first {
            let starSize = firstStar.size
            let favoriteOrigin = CGPoint(x: starsWidth + spacing, y: 0.5 * (height - starSize.height))
            
            let favoriteRect = NSRect(origin: favoriteOrigin, size: starSize)
            drawFavoriteHeart(in: favoriteRect, filled: isLoved)
        }
        
        canvasImage.unlockFocus()
        
        return canvasImage
    }
    
    /// Heart for Music's "favorited" flag, so it reads differently from the rating stars.
    ///
    /// Two circles side by side, joined by tangent lines to a point at the bottom.
    /// AppKit's y axis points up, and arc angles are in degrees.
    private func drawFavoriteHeart(in rect: NSRect, filled: Bool) {
        let lineWidth: CGFloat = filled ? 1.0 : 1.5
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

        NSColor.black.setStroke()
        if filled {
            NSColor.black.setFill()
            path.fill()
        }
        path.stroke()
    }
    
}
