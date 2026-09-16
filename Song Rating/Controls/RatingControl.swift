//
//  RatingControl.swift
//  Song Rating
//
//  Created by Cirno MainasuK on 2019-7-1.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa
import os

protocol RatingControlDelegate: class {
    func ratingControl(_ ratingControl: RatingControl, shouldUpdateRating rating: Int) -> Bool
    func ratingControl(_ ratingControl: RatingControl, userDidUpdateRating rating: Int)
}

class RatingControl {
    
    weak var delegate: RatingControlDelegate?
    
    let starsImage: NSImage
    
    let starSize: NSSize
    let spacing: CGFloat
    /// 0 ~ 100
    private(set) var rating: Int
    /// true if the track is marked as a favorite in Apple Music (property still called "loved" in API)
    private(set) var isLoved: Bool = false
    
    var stars: Stars {
        let fullStarCount = rating / 20
        let halfStarCount: Int = {
            let remainRating = rating - 20 * fullStarCount
            return remainRating / 10
        }()
        let dotCount = 5 - fullStarCount - halfStarCount
        
        var stars: [Star] = []
        if fullStarCount > 0 {
            stars.append(contentsOf: Array(repeating: Star(size: starSize, style: .full), count: fullStarCount))
        }
        if halfStarCount > 0 {
            stars.append(contentsOf: Array(repeating: Star(size: starSize, style: .half), count: halfStarCount))
        }
        if dotCount > 0 {
            stars.append(contentsOf: Array(repeating: Star(size: starSize, style: .dot), count: dotCount))
        }
        
        return Stars(stars: stars, spacing: spacing, showsFavorite: true, isLoved: isLoved)
    }
    
    /// Stars rating control constructor
    ///
    /// - Parameters:
    ///   - rating: 0~100
    ///   - size: size for one star
    ///   - spacing: spacing between two stars
    init(rating: Int, starSize: NSSize = NSSize(width: 16, height: 16), spacing: CGFloat = 4) {
        self.rating = rating
        self.starSize = starSize
        self.spacing = spacing
        
        // Add extra space for heart icon
        self.starsImage = NSImage(size: NSSize(width: CGFloat(5) * starSize.width + CGFloat(7) * spacing + starSize.width, height: starSize.height))
        
        starsImage.isTemplate = true
        starsImage.cacheMode = .never
        drawStars()
    }
    
}

extension RatingControl {
    
    /// Update control rating
    ///
    /// - Parameter rating: 0 ~ 100
    func update(rating: Int) {
        let newRating = min(100, max(0, rating))
        self.rating = newRating
        
        drawStars()
        os_log("%{public}s[%{public}ld], %{public}s: draw rating control %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, newRating)
    }
    
    /// Update favorite status (called "loved" in the API)
    ///
    /// - Parameter loved: true if the track is favorited in Apple Music
    func updateLoved(_ loved: Bool) {
        self.isLoved = loved
        
        drawStars()
        os_log(.debug, "%{public}s[%{public}ld], %{public}s: update favorite status to %{public}d", ((#file as NSString).lastPathComponent), #line, #function, loved ? 1 : 0)
    }
    
    /// Stars draw only method
    private func drawStars() {
        let rect = NSRect(origin: .zero, size: starsImage.size)
        starsImage.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.clear(rect)
        }
        stars.image.draw(in: rect)
        starsImage.unlockFocus()
    }
    
}

extension RatingControl {
    
    /// Cursor x offset inside `starsImage`, read from the live mouse position.
    ///
    /// `NSGestureRecognizer.location(in:)` on a status bar button reports the same point for
    /// every click on macOS 27, so we convert `NSEvent.mouseLocation` into button coordinates.
    /// The button centres the image, so the margin is half of the spare width.
    func imagePositionX(in button: NSButton) -> CGFloat? {
        guard let window = button.window, starsImage.size.width > 0 else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let pointInButton = button.convert(pointInWindow, from: nil)
        let leftMargin = 0.5 * (button.bounds.width - starsImage.size.width)
        return pointInButton.x - leftMargin
    }

    /// Left edge of the favorite heart inside `starsImage`.
    /// Matches the layout in `Stars.image`: five star slots, then one more spacing.
    var favoriteMinX: CGFloat {
        return CGFloat(7) * spacing + CGFloat(5) * starSize.width
    }

    /// True when `positionX` (from `imagePositionX(in:)`) is over the favorite heart.
    func isFavoriteHit(positionX: CGFloat) -> Bool {
        let favoriteMinX = self.favoriteMinX
        return positionX >= favoriteMinX - 0.5 * spacing && positionX <= favoriteMinX + starSize.width + spacing
    }

    func action(from sender: NSButton, by gestureRecognizer: NSGestureRecognizer, behavior: Behavior) {
        guard let positionX = imagePositionX(in: sender), !isFavoriteHit(positionX: positionX) else { return }

        // Star i is drawn from spacing + i * slot to that plus starSize.width.
        // Split each gap between neighbouring stars so no click position is dead.
        let slot = starSize.width + spacing
        let rating: Int  // starRating: 0 ~ 10
        if positionX < spacing {
            rating = 0
        } else {
            let i = min(4, max(0, Int(((positionX - 0.5 * spacing) / slot).rounded(.down))))
            switch behavior {
            case .full:
                rating = 2 * (i + 1)
            case .half:
                rating = 2 * (i + 1) - 1
            case .both:
                let centerX = spacing + CGFloat(i) * slot + 0.5 * starSize.width
                rating = positionX > centerX ? (2 * (i + 1)) : (2 * (i + 1) - 1)
            }
        }

        os_log(.debug, "%{public}s[%{public}ld], %{public}s: click positionX %{public}.1f -> star rating %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, positionX, rating)

        guard delegate?.ratingControl(self, shouldUpdateRating: rating * 10) ?? false else {
            return
        }

        let newRating = rating * 10
        update(rating: newRating)
        delegate?.ratingControl(self, userDidUpdateRating: newRating)
    }
    
    enum Behavior {
        case full
        case half
        case both
    }
    
}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct RatingControl_Preview: PreviewProvider {
    
    static let ratings: [Int] = Array(stride(from: 0, through: 100, by: 10))
    
    static var previews: some View {
        ForEach(ratings, id: \.self) { rating in
            NSViewPreview {
                let ratingControl = RatingControl(rating: rating)
                return NSImageView(image: ratingControl.starsImage)
            }
        }
    }
    
}

#endif
