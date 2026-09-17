//
//  RatingClickController.swift
//  Song Rating
//
//  Turns a click on the menu bar stars into a rating, a favorite toggle, or a drag.
//

import Cocoa
import os

/// The mouse, as the menu bar stars see it. `StatusButtonPointer` reads the real mouse;
/// tests use a fake.
protocol RatingPointer: AnyObject {
    /// True while the left mouse button is down
    var isLeftButtonHeld: Bool { get }
    /// Cursor x inside `RatingControl.starsImage`, or nil when it can't be read
    var imagePositionX: CGFloat? { get }
}

/// Handles clicks and drags on the menu bar stars.
///
/// On macOS 27 the menu bar sends the status item one synthesised click (mouse down and up
/// together) when the mouse goes down, and no drag events. So `click()` checks whether the
/// button is still held. If it is, a drag begins: the owner calls `tick()` on a timer, the
/// stars follow the cursor, and the rating is saved once, when the button is released.
final class RatingClickController {

    let ratingControl: RatingControl
    let pointer: RatingPointer
    /// Whole stars, or half stars when that preference is on
    var behavior: () -> RatingControl.Behavior
    /// True when nothing is playing, so there is no track to rate
    var isStopped: () -> Bool
    var toggleFavorite: () -> Void
    /// Called after the stars change during a drag, so the owner can redraw
    var didPreview: () -> Void = {}

    private(set) var drag: RatingControl.Drag?

    var isDragging: Bool {
        return drag != nil
    }

    init(ratingControl: RatingControl,
         pointer: RatingPointer,
         behavior: @escaping () -> RatingControl.Behavior,
         isStopped: @escaping () -> Bool,
         toggleFavorite: @escaping () -> Void) {
        self.ratingControl = ratingControl
        self.pointer = pointer
        self.behavior = behavior
        self.isStopped = isStopped
        self.toggleFavorite = toggleFavorite
    }

    /// Handle the menu bar's click. Returns true when a drag began and the owner should
    /// call `tick()` until it returns false.
    @discardableResult
    func click() -> Bool {
        drag = nil
        guard !isStopped(), let positionX = pointer.imagePositionX else { return false }

        if ratingControl.isFavoriteHit(positionX: positionX) {
            toggleFavorite()
            return false
        }

        let rating = ratingControl.rating(atPositionX: positionX, behavior: behavior())
        guard pointer.isLeftButtonHeld else {
            if let rating = rating {
                ratingControl.commit(rating: rating)
            }
            return false
        }

        os_log("%{public}s[%{public}ld], %{public}s: mouse held, following drag", ((#file as NSString).lastPathComponent), #line, #function)
        var drag = RatingControl.Drag(originalRating: ratingControl.rating)
        preview(drag.move(to: rating))
        self.drag = drag
        return true
    }

    /// Follow the cursor during a drag. Returns false once the drag has ended.
    func tick() -> Bool {
        guard var drag = drag else { return false }
        let rating = pointer.imagePositionX.flatMap { ratingControl.rating(atPositionX: $0, behavior: behavior()) }

        guard pointer.isLeftButtonHeld, !isStopped() else {
            self.drag = nil
            if !isStopped(), let releaseRating = drag.releaseRating(at: rating) {
                os_log("%{public}s[%{public}ld], %{public}s: drag released at rating %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, releaseRating)
                ratingControl.commit(rating: releaseRating)
            } else {
                // Nothing saved: put back the rating the stars showed before the drag,
                // so later changes (such as the rating shortcuts) don't build on the preview
                os_log("%{public}s[%{public}ld], %{public}s: drag cancelled, restoring rating %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, drag.originalRating)
                preview(drag.originalRating)
            }
            return false
        }

        preview(drag.move(to: rating))
        self.drag = drag
        return true
    }

    private func preview(_ rating: Int) {
        guard rating != ratingControl.rating else { return }
        ratingControl.update(rating: rating)
        didPreview()
    }

}

/// Reads the real mouse for a status bar button.
final class StatusButtonPointer: RatingPointer {

    private weak var button: NSButton?
    private let ratingControl: RatingControl

    init(button: NSButton?, ratingControl: RatingControl) {
        self.button = button
        self.ratingControl = ratingControl
    }

    var isLeftButtonHeld: Bool {
        return NSEvent.pressedMouseButtons & 1 != 0
    }

    var imagePositionX: CGFloat? {
        return button.flatMap { ratingControl.imagePositionX(in: $0) }
    }

}
