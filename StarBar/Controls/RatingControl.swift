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

    /// The strip drawn in the menu bar. Replaced when the mode changes, because the two modes
    /// are different widths: read it again after `update(mode:)` rather than holding on to it.
    private(set) var starsImage: NSImage

    let starSize: NSSize
    let spacing: CGFloat
    /// 0 ~ 100
    private(set) var rating: Int
    /// Stars and heart, or the Apple Music button and heart
    private(set) var mode: Mode = .rating
    /// True while the song is being added to the library and we're waiting for Music. The
    /// button dims, because the add takes seconds and an unchanged button looks unpressed.
    private(set) var isAddingToLibrary = false
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

        self.starsImage = RatingControl.makeImage(
            width: RatingControl.imageWidth(mode: .rating, starSize: starSize, spacing: spacing),
            height: starSize.height
        )
        drawStars()
    }

    /// An empty template strip for the menu bar to recolour
    private static func makeImage(width: CGFloat, height: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.isTemplate = true
        image.cacheMode = .never
        return image
    }

    /// What the control offers for the track that is playing.
    enum Mode: Equatable {
        /// Five stars and the heart: the track is in the library, so it can be rated
        case rating
        /// The Apple Music button and the heart: the track is streamed from the Apple Music
        /// catalog, so Music has nowhere to store a rating until it is added to the library.
        /// See `iTunesTrack.isCatalogStream`.
        case addToLibrary
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
    
    /// Switch between the stars and the Apple Music button.
    ///
    /// The two strips are different widths, so this replaces `starsImage`. The owner must read
    /// it again and resize the status item; `MenuBarRatingControl` does that from `didChange`.
    ///
    /// - Parameter mode: what the control should offer for the track now playing
    func update(mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        // Leaving the button behind ends any wait it was showing
        isAddingToLibrary = false

        starsImage = RatingControl.makeImage(
            width: RatingControl.imageWidth(mode: mode, starSize: starSize, spacing: spacing),
            height: starSize.height
        )
        drawStars()
        os_log("%{public}s[%{public}ld], %{public}s: rating control mode is now %{public}s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: mode))
    }

    /// Dim the Apple Music button while the song is on its way into the library.
    ///
    /// - Parameter isAdding: true from the press until Music has the song
    func update(isAddingToLibrary isAdding: Bool) {
        guard isAdding != isAddingToLibrary else { return }
        isAddingToLibrary = isAdding

        drawStars()
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
        strip.draw(in: rect)
        starsImage.unlockFocus()
    }

    /// What `drawStars()` puts in `starsImage`, for the mode the control is in
    private var strip: NSImage {
        switch mode {
        case .rating:
            return stars.image
        case .addToLibrary:
            return AddToLibraryBadge(glyphSize: starSize, spacing: spacing, isFavorited: isFavorited, isPending: isAddingToLibrary).image
        }
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

    /// Width of what comes before the heart slot, for a mode.
    ///
    /// Both strips lay out the same way -- a spacing before each glyph and one after -- so
    /// only the number of glyphs differs: five stars, or the note and the plus.
    static func contentWidth(mode: Mode, starSize: NSSize, spacing: CGFloat) -> CGFloat {
        let glyphCount: Int
        switch mode {
        case .rating:       glyphCount = 5
        case .addToLibrary: glyphCount = AddToLibraryBadge.glyphCount
        }
        return CGFloat(glyphCount) * starSize.width + CGFloat(glyphCount + 1) * spacing
    }

    /// Left edge of the plus in the Apple Music button, inside `starsImage`. The menu bar
    /// spins a progress indicator here while the song is being added.
    var addToLibraryPlusMinX: CGFloat {
        return AddToLibraryBadge(glyphSize: starSize, spacing: spacing).plusMinX
    }

    /// Left edge of the favorite heart inside `starsImage`, for a mode
    static func favoriteMinX(mode: Mode, starSize: NSSize, spacing: CGFloat) -> CGFloat {
        return contentWidth(mode: mode, starSize: starSize, spacing: spacing) + spacing
    }

    /// Width of the whole strip, for a mode. The heart takes one glyph slot at the end.
    static func imageWidth(mode: Mode, starSize: NSSize, spacing: CGFloat) -> CGFloat {
        return favoriteMinX(mode: mode, starSize: starSize, spacing: spacing) + starSize.width
    }

    /// Left edge of the favorite heart inside `starsImage`.
    /// Matches the layout in `Stars.image`: five star slots, then one more spacing.
    /// In `.addToLibrary` the strip is shorter, so the heart sits further left.
    var favoriteMinX: CGFloat {
        return RatingControl.favoriteMinX(mode: mode, starSize: starSize, spacing: spacing)
    }

    /// True when `positionX` (from `imagePositionX(in:)`) is over the favorite heart.
    /// This is the click area for toggling the favorite: 2pt left of the heart to 4pt right of it.
    /// `rating(atPositionX:)` deliberately uses a wider zone (from the same left edge to
    /// infinity), so don't make the two match.
    func isFavoriteHit(positionX: CGFloat) -> Bool {
        let favoriteMinX = self.favoriteMinX
        return positionX >= favoriteMinX - 0.5 * spacing && positionX <= favoriteMinX + starSize.width + spacing
    }

    /// True when a click at `positionX` should add the song to the library.
    ///
    /// The note and the plus are one button, so the whole strip up to the heart counts and
    /// there is no dead gap between the two glyphs. The boundary is the one `isFavoriteHit`
    /// starts at, so every position belongs to exactly one of them.
    /// Always false in `.rating`, where that area is the stars.
    func isAddToLibraryHit(positionX: CGFloat) -> Bool {
        guard mode == .addToLibrary else { return false }
        return positionX >= 0 && positionX < favoriteMinX - 0.5 * spacing
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
        // Nothing left of the heart is a rating in `.addToLibrary`: it is the add button, and
        // Music would refuse the rating anyway
        guard mode == .rating else { return nil }
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

    /// Spoken description for a mode. In `.addToLibrary` there is no rating to read out, so it
    /// says why and what the button does.
    static func accessibilityDescription(mode: Mode, rating: Int, isFavorited: Bool, isAddingToLibrary: Bool = false) -> String {
        switch mode {
        case .rating:
            return accessibilityDescription(rating: rating, isFavorited: isFavorited)
        case .addToLibrary:
            let text = isAddingToLibrary ? "Adding to your library" : "Not in your library, add to rate"
            return isFavorited ? text + ", favourite" : text
        }
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
