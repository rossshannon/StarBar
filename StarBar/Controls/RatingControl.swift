//
//  RatingControl.swift
//  StarBar
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
    /// True if the track is a favorite in Music (see `iTunesTrack.isFavorited`)
    private(set) var isFavorited: Bool = false
    /// Position (0 ~ 4) of the hollow star in the rating reminder sweep, or nil when no sweep
    /// is running. Display only: it never changes `rating`.
    private(set) var sweepPosition: Int?
    /// Called after the rating or favorite changes and the stars are redrawn
    var didChange: (() -> Void)?
    
    var stars: Stars {
        var stars = Stars.styles(forRating: rating).map { Star(size: starSize, style: $0) }
        // The sweep only replaces a dot, never a star the user chose
        if let sweepPosition = sweepPosition, stars.indices.contains(sweepPosition), stars[sweepPosition].style == .dot {
            stars[sweepPosition] = Star(size: starSize, style: .outline)
        }

        return Stars(stars: stars, spacing: spacing, showsFavorite: true, isFavorited: isFavorited)
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
    
    /// Update favorite status
    ///
    /// - Parameter favorited: true if the track is a favorite in Music
    func updateFavorited(_ favorited: Bool) {
        self.isFavorited = favorited

        drawStars()
        os_log(.debug, "%{public}s[%{public}ld], %{public}s: update favorite status to %{public}d", ((#file as NSString).lastPathComponent), #line, #function, favorited ? 1 : 0)
    }
    
    /// Move the rating reminder's hollow star, or remove it with nil
    ///
    /// - Parameter position: 0 ~ 4, or nil
    func updateSweep(position: Int?) {
        guard position != sweepPosition else { return }
        sweepPosition = position

        drawStars()
    }

    /// Stars draw only method
    private func drawStars() {
        defer { didChange?() }
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
    /// This is the click area for toggling the favorite: 2pt left of the heart to 4pt right of it.
    /// `rating(atPositionX:)` deliberately uses a wider zone (from the same left edge to
    /// infinity), so don't make the two match.
    func isFavoriteHit(positionX: CGFloat) -> Bool {
        let favoriteMinX = self.favoriteMinX
        return positionX >= favoriteMinX - 0.5 * spacing && positionX <= favoriteMinX + starSize.width + spacing
    }

    /// Star rating (0 ~ 10, one unit per half star) for a click at `positionX` inside `starsImage`.
    ///
    /// Star i is drawn from spacing + i * slot to that plus starSize.width.
    /// Each gap between neighbouring stars is split, so no click position is dead.
    /// Positions past the last star clamp to star 5. This ignores the heart; use
    /// `rating(atPositionX:)`, which returns nil from the heart rightwards.
    func starRating(atPositionX positionX: CGFloat, behavior: Behavior) -> Int {
        guard positionX >= spacing else { return 0 }

        let slot = starSize.width + spacing
        let i = min(4, max(0, Int(((positionX - 0.5 * spacing) / slot).rounded(.down))))
        switch behavior {
        case .full:
            return 2 * (i + 1)
        case .both:
            let centerX = spacing + CGFloat(i) * slot + 0.5 * starSize.width
            return positionX > centerX ? (2 * (i + 1)) : (2 * (i + 1) - 1)
        }
    }

    /// Rating (0 ~ 100) at `positionX` inside `starsImage`, or nil over the heart.
    /// Everything from the heart's hit area rightwards counts as the heart, so a drag that
    /// carries on past the heart keeps its last star rating instead of setting 5 stars.
    /// This zone is wider than `isFavoriteHit(positionX:)` on purpose: a click there toggles
    /// the favorite, but a drag released there must not save a rating.
    func rating(atPositionX positionX: CGFloat, behavior: Behavior) -> Int? {
        guard positionX < favoriteMinX - 0.5 * spacing else { return nil }

        let rating = 10 * starRating(atPositionX: positionX, behavior: behavior)
        os_log(.debug, "%{public}s[%{public}ld], %{public}s: positionX %{public}.1f -> rating %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, positionX, rating)
        return rating
    }

    /// Spoken description of a rating and favorite, such as "3½ stars, favourite".
    /// VoiceOver reads it, and the UI tests check it.
    static func accessibilityDescription(rating: Int, isFavorited: Bool) -> String {
        let halfStars = min(10, max(0, rating / 10))
        let wholeStars = halfStars / 2
        let hasHalf = halfStars % 2 == 1
        let text: String
        switch (wholeStars, hasHalf) {
        case (0, false): text = "No rating"
        case (0, true): text = "½ star"
        case (1, false): text = "1 star"
        default: text = "\(wholeStars)\(hasHalf ? "½" : "") stars"
        }
        return isFavorited ? text + ", favourite" : text
    }

    /// Set a rating the user chose, if the delegate allows it, and tell the delegate to save it.
    ///
    /// - Parameter rating: 0 ~ 100
    func commit(rating: Int) {
        guard delegate?.ratingControl(self, shouldUpdateRating: rating) ?? false else { return }

        update(rating: rating)
        delegate?.ratingControl(self, userDidUpdateRating: rating)
    }

    enum Behavior {
        /// Whole stars only
        case full
        /// Left half of a star (or the gap before it) is a half star
        case both
    }

    /// A drag across the stars. The stars follow the cursor, and the rating is saved on release.
    struct Drag {

        /// Rating (0 ~ 100) when the drag began, restored if the drag is cancelled
        let originalRating: Int
        /// Last rating the cursor was over. Nil until the cursor reaches the stars.
        private(set) var lastRating: Int?

        init(originalRating: Int) {
            self.originalRating = originalRating
        }

        /// Move the cursor to `rating` (nil over the heart). Returns the rating to show.
        /// Over the heart the stars keep showing the last rating.
        mutating func move(to rating: Int?) -> Int {
            if let rating = rating {
                lastRating = rating
            }
            return lastRating ?? originalRating
        }

        /// Rating to save when the mouse is released over `rating` (nil over the heart),
        /// or nil when the drag never reached the stars.
        func releaseRating(at rating: Int?) -> Int? {
            return rating ?? lastRating
        }

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
