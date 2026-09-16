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
        
        // Draw favorite star
        if let firstStar = stars.first {
            let starSize = firstStar.size
            let favoriteOrigin = CGPoint(x: starsWidth + spacing, y: 0.5 * (height - starSize.height))
            
            // Draw favorite star shape
            let favoriteRect = NSRect(origin: favoriteOrigin, size: starSize)
            drawFavoriteStar(in: favoriteRect, filled: isLoved)
        }
        
        canvasImage.unlockFocus()
        
        return canvasImage
    }
    
    private func drawFavoriteStar(in rect: NSRect, filled: Bool) {
        // Draw a star instead of a heart since Apple Music uses stars for favorites
        let path = NSBezierPath()
        
        let width = rect.width
        let height = rect.height
        
        // Scale factors
        let scale = min(width, height) * 0.8
        
        // Center point
        let centerX = rect.midX
        let centerY = rect.midY
        
        // Star points
        let outerRadius = scale * 0.5
        let innerRadius = outerRadius * 0.4
        
        // Create 5-pointed star
        var points: [NSPoint] = []
        
        // Add the star points
        for i in 0..<10 {
            // Alternate between outer and inner points
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            // Calculate angle (36 degrees per point, offset by -90 degrees to start at top)
            let angle = Double.pi * (Double(i) * 36.0 / 180.0 - 90.0 / 180.0)
            
            let x = centerX + CGFloat(cos(angle)) * radius
            let y = centerY + CGFloat(sin(angle)) * radius
            points.append(NSPoint(x: x, y: y))
        }
        
        // Draw the star
        path.move(to: points[0])
        for i in 1..<points.count {
            path.line(to: points[i])
        }
        path.close()
        
        path.lineWidth = 1.0
        
        // Use a slightly different color for the favorite star to make it more distinct
        if filled {
            // Use a slightly darker shade for filled state to make it stand out
            NSColor.black.withAlphaComponent(0.9).setFill()
            path.fill()
            
            // Add a slight glow/shadow effect to the filled favorite star
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            shadow.shadowBlurRadius = 2.0
            
            shadow.set()
        } else {
            // For outline state, set a slightly thicker line
            path.lineWidth = 1.5
        }
        
        NSColor.black.setStroke()
        path.stroke()
    }
    
}
