//
//  MenuBarRatingControl.swift
//  Song Rating
//
//  Created by Cirno MainasuK on 2019-7-20.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa
import os

protocol TrackingAreaResponderDelegate: AnyObject {
    func mouseEntered(with event: NSEvent)
    func mouseExited(with event: NSEvent)
}

final class TrackingAreaResponder: NSView {

    weak var delegate: TrackingAreaResponderDelegate?

    override func mouseEntered(with event: NSEvent) {
        delegate?.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        delegate?.mouseExited(with: event)
    }

}

protocol PopoverProxyDelegate: AnyObject {
    func popoverDidClose(_ notification: Notification)
    func popoverShouldDetach(_ popover: NSPopover) -> Bool
    func popoverDidDetach(_ popover: NSPopover)
}

final class PopoverProxy: NSObject, NSPopoverDelegate {

    weak var delegate: PopoverProxyDelegate?

    func popoverDidClose(_ notification: Notification) {
        delegate?.popoverDidClose(notification)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        return delegate?.popoverShouldDetach(popover) ?? false
    }

    func popoverDidDetach(_ popover: NSPopover) {
        delegate?.popoverDidDetach(popover)
    }

}

final class MenuBarRatingControl {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let ratingControl = RatingControl(rating: 0)
    let menuBarIcon: MenuBarIcon
    let trackingAreaResponser = TrackingAreaResponder()
    /// Coloured heart shown over the empty heart slot in the template stars image
    private let favoriteHeartView: NSImageView = {
        let imageView = PassthroughImageView()
        imageView.imageScaling = .scaleNone
        imageView.isHidden = true
        // Stay centred with the stars image when the button resizes after statusItem.length changes
        imageView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        return imageView
    }()
    
    private let clickGestureRecognizer: NSClickGestureRecognizer = {
        let gestureRecognizer = NSClickGestureRecognizer()
        return gestureRecognizer
    }()
    /// Set while the user drags across the stars
    private var ratingDrag: RatingControl.Drag?
    /// Reads the cursor while the mouse button is held after a press on the stars
    private var ratingDragTimer: Timer?

    private(set) lazy var menuBarMenu: NSMenu = {
        let menu = NSMenu()
        let about = NSMenuItem(title: "About Music Rating", action: #selector(WindowManager.aboutMenuItemPressed(_:)), keyEquivalent: "")
        about.target = WindowManager.shared
        menu.addItem(about)
        let preferences = NSMenuItem(title: "Preferences…", action: #selector(WindowManager.preferencesMenuItemPressed(_:)), keyEquivalent: ",")
        preferences.target = WindowManager.shared
        menu.addItem(preferences)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Music Rating", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }()
    private(set) var isPlaying = false {
        didSet {
            if let playState = iTunesRadioStation.shared.latestPlayInfo?.playerState {
                self.playState = playState
            } else {
                if iTunesRadioStation.shared.iTunes?.playerState == .playing {
                    self.playState = .playing
                } else if iTunesRadioStation.shared.iTunes?.playerState == .paused {
                    self.playState = .paused
                } else {
                    self.playState = .unknown
                }
            }

            updateMenuBar()
        }
    }
    private(set) var playState: PlayInfo.PlayerState = .unknown {
        didSet {
            // FIXME: close attached popover when menu bar collapse
            if playState == .unknown {
                WindowManager.shared.attachedPopover?.close()
            }
            updateGestureRecognizerBehavior()
        }
    }

    var isStop: Bool {
        return playState == .unknown
    }
    
    func updateGestureRecognizerBehavior() {
        // deliver .leftMouseUp action without delay when player stop
        clickGestureRecognizer.delaysPrimaryMouseButtonEvents = !isStop
    }

    init() {
        menuBarIcon = MenuBarIcon(size: ratingControl.starSize)

        guard let button = statusItem.button else {
            os_log("%{public}s[%{public}ld], %{public}s: CRITICAL ERROR - Failed to create status item button", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        button.image = ratingControl.starsImage
        favoriteHeartView.image = Stars.filledFavoriteHeartImage(size: ratingControl.starSize)
        button.addSubview(favoriteHeartView)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(MenuBarRatingControl.action(_:))
        button.target = self
        button.setButtonType(.momentaryChange)
        
        // On macOS 27 the menu bar sends the app one synthesised click when the mouse goes down,
        // and no drag events. Pan and press recognizers never fire, so the click handler
        // follows a drag itself by reading the mouse while the button is held.
        clickGestureRecognizer.action = #selector(MenuBarRatingControl.clickGestureRecognizerHandler(_:))
        clickGestureRecognizer.target = self
        button.addGestureRecognizer(clickGestureRecognizer)

        let trackingArea = NSTrackingArea(rect: button.bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved], owner: trackingAreaResponser, userInfo: nil)
        button.addTrackingArea(trackingArea)

        trackingAreaResponser.delegate = self

        ratingControl.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesPlayerDidUpdated(_:)), name: .iTunesPlayerDidUpdated, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRatingUp(_:)), name: .iTunesRadioRequestTrackRatingUp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRatingDown(_:)), name: .iTunesRadioRequestTrackRatingDown, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating5(_:)), name: .iTunesRadioRequestTrackRating5, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating4(_:)), name: .iTunesRadioRequestTrackRating4, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating3(_:)), name: .iTunesRadioRequestTrackRating3, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating2(_:)), name: .iTunesRadioRequestTrackRating2, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating1(_:)), name: .iTunesRadioRequestTrackRating1, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating0(_:)), name: .iTunesRadioRequestTrackRating0, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.windowDidResize(_:)), name: NSWindow.didResizeNotification, object: nil)
    }

}

extension MenuBarRatingControl {

    private func updateMenuBar() {
        let margin: CGFloat = 4 + 4
        let playingWidth = margin + ratingControl.starsImage.size.width
        let pauseWidth = margin + CGFloat(2) * ratingControl.spacing + ratingControl.starSize.width

        statusItem.length = !isStop ? playingWidth : pauseWidth
        statusItem.button?.image = !isStop ? ratingControl.starsImage : menuBarIcon.image
        statusItem.button?.setButtonType(!isStop ? .momentaryChange : .onOff)
        updateFavoriteHeartView()
    }

    /// Show the coloured heart over the heart slot when the track is a favorite.
    /// The button centres `starsImage`, the same assumption the click hit-test makes.
    private func updateFavoriteHeartView() {
        guard let button = statusItem.button else { return }
        favoriteHeartView.isHidden = isStop || !ratingControl.isFavorited
        guard !favoriteHeartView.isHidden else { return }

        // Same geometry as RatingControl.imagePositionX(in:), so the heart and its click area agree
        let leftMargin = 0.5 * (button.bounds.width - ratingControl.starsImage.size.width)
        let size = ratingControl.starSize
        favoriteHeartView.frame = NSRect(
            x: leftMargin + ratingControl.favoriteMinX,
            y: 0.5 * (button.bounds.height - size.height),
            width: size.width,
            height: size.height
        )
    }
    
    /// Toggle the favorite status of the current track
    func toggleFavorite() {
        guard !isStop, let track = iTunesPlayer.shared.currentTrack else { return }

        os_log("%{public}s[%{public}ld], %{public}s: Toggling favorite status for track: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, track.name ?? "unknown")

        let isFavorited = !track.isFavorited
        track.updateFavorited(isFavorited)

        // Update our local state immediately
        ratingControl.updateFavorited(isFavorited)
        updateFavoriteHeartView()
        statusItem.button?.needsDisplay = true
        
        // Also trigger a full update to refresh data from iTunes
        iTunesPlayer.shared.update()
    }

}

extension MenuBarRatingControl {

    @objc private func action(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else {
            return
        }
        os_log("%{public}s[%{public}ld], %{public}s: menu bar button receive event %s", ((#file as NSString).lastPathComponent), #line, #function, event.debugDescription)

        switch event.type {
        case .leftMouseUp where isStop:
            let position = NSPoint(x: 0, y: sender.bounds.height + 8)
            menuBarMenu.popUp(positioning: nil, at: position, in: sender)
        case .rightMouseUp where isStop:
            let position = sender.convert(event.locationInWindow, to: nil)
            menuBarMenu.popUp(positioning: nil, at: position, in: sender)

        case .rightMouseUp:
            WindowManager.shared.triggerPopover()

        default:
            os_log("%{public}s[%{public}ld], %{public}s: no handler for event %s", ((#file as NSString).lastPathComponent), #line, #function, event.debugDescription)
        }
    }
    
    /// With half stars on, the left half of a star (or the gap before it) sets a half star
    private var ratingBehavior: RatingControl.Behavior {
        return UserDefaults.standard.allowHalfStar ? .both : .full
    }

    @objc private func clickGestureRecognizerHandler(_ sender: NSClickGestureRecognizer) {
        os_log("%{public}s[%{public}ld], %{public}s: %s", ((#file as NSString).lastPathComponent), #line, #function, sender.debugDescription)
        guard sender.state == .ended, let button = statusItem.button, !isStop else { return }

        if let positionX = ratingControl.imagePositionX(in: button),
           ratingControl.isFavoriteHit(positionX: positionX) {
            toggleFavorite()
        } else if isLeftMouseButtonHeld {
            beginRatingDrag(in: button)
        } else if let rating = ratingControl.ratingUnderCursor(in: button, behavior: ratingBehavior) {
            ratingControl.commit(rating: rating)
        }
    }

    private var isLeftMouseButtonHeld: Bool {
        return NSEvent.pressedMouseButtons & 1 != 0
    }

    /// Follow the cursor while the mouse button stays down: the stars show the rating under
    /// the cursor, and the rating is saved when the button is released.
    private func beginRatingDrag(in button: NSButton) {
        endRatingDrag()
        os_log("%{public}s[%{public}ld], %{public}s: mouse held, following drag", ((#file as NSString).lastPathComponent), #line, #function)

        ratingDrag = RatingControl.Drag(originalRating: ratingControl.rating)
        updateRatingDrag(in: button)

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak button] _ in
            guard let self = self, let button = button else { return }
            self.updateRatingDrag(in: button)
        }
        // .common keeps the timer firing while AppKit tracks the mouse
        RunLoop.main.add(timer, forMode: .common)
        ratingDragTimer = timer
    }

    private func updateRatingDrag(in button: NSButton) {
        guard var drag = ratingDrag else { return }
        let ratingUnderCursor = ratingControl.ratingUnderCursor(in: button, behavior: ratingBehavior)

        guard isLeftMouseButtonHeld, !isStop else {
            endRatingDrag()
            if !isStop, let rating = drag.releaseRating(at: ratingUnderCursor) {
                os_log("%{public}s[%{public}ld], %{public}s: drag released at rating %{public}ld", ((#file as NSString).lastPathComponent), #line, #function, rating)
                ratingControl.commit(rating: rating)
            }
            return
        }

        let shownRating = drag.move(to: ratingUnderCursor)
        ratingDrag = drag
        if shownRating != ratingControl.rating {
            ratingControl.update(rating: shownRating)
            button.needsDisplay = true
        }
    }

    private func endRatingDrag() {
        ratingDragTimer?.invalidate()
        ratingDragTimer = nil
        ratingDrag = nil
    }

}

// MARK: - RatingControlDelegate
extension MenuBarRatingControl: RatingControlDelegate {

    func ratingControl(_ ratingControl: RatingControl, shouldUpdateRating rating: Int) -> Bool {
        return !isStop
    }

    func ratingControl(_ ratingControl: RatingControl, userDidUpdateRating rating: Int) {
        // Update iTunes current track rating
        iTunesRadioStation.shared.setRating(rating)
        statusItem.button?.needsDisplay = true
    }

}

extension MenuBarRatingControl {

    @objc func iTunesPlayerDidUpdated(_ notification: Notification) {
        let player = iTunesPlayer.shared

        isPlaying = player.isPlaying
        // Each property read is an Apple Event, so read the track once
        let track = player.currentTrack
        // Don't overwrite the stars the user is dragging across
        if ratingDrag == nil {
            ratingControl.update(rating: track?.userRating ?? 0)
        }
        ratingControl.updateFavorited(track?.isFavorited ?? false)
        updateFavoriteHeartView()
    }

    @objc func iTunesRadioRequestTrackRatingUp(_ notification: Notification) {
        isPlaying = iTunesPlayer.shared.isPlaying
        guard !isStop else {
            return
        }
        let ratingChange: Int = UserDefaults.standard.allowHalfStar ? 10 : 20
        ratingControl.update(rating: ratingControl.rating + ratingChange)
        iTunesRadioStation.shared.setRating(ratingControl.rating)
    }

    @objc func iTunesRadioRequestTrackRatingDown(_ notification: Notification) {
        isPlaying = iTunesPlayer.shared.isPlaying
        guard !isStop else {
            return
        }

        let ratingChange: Int = UserDefaults.standard.allowHalfStar ? 10 : 20
        ratingControl.update(rating: ratingControl.rating - ratingChange)
        iTunesRadioStation.shared.setRating(ratingControl.rating)
    }

    @objc func iTunesRadioRequestTrackRating5(_ notification: Notification) {
        setRating(stars: 5)
    }

    @objc func iTunesRadioRequestTrackRating4(_ notification: Notification) {
        setRating(stars: 4)
    }

    @objc func iTunesRadioRequestTrackRating3(_ notification: Notification) {
        setRating(stars: 3)
    }

    @objc func iTunesRadioRequestTrackRating2(_ notification: Notification) {
        setRating(stars: 2)
    }

    @objc func iTunesRadioRequestTrackRating1(_ notification: Notification) {
        setRating(stars: 1)
    }

    @objc func iTunesRadioRequestTrackRating0(_ notification: Notification) {
        setRating(stars: 0)
    }

    @objc func setRating(stars: Int) {
      isPlaying = iTunesPlayer.shared.isPlaying
      guard !isStop else {
          return
      }

      ratingControl.update(rating: stars * 20)
      iTunesRadioStation.shared.setRating(ratingControl.rating)
    }

    @objc func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        // Always update menu bar to prevent wrong state when iTunes not running
        DispatchQueue.once(token: "firstDisplay") {
            updateMenuBar()
        }

        os_log("%{public}s[%{public}ld], %{public}s: window size change to %{public}s", ((#file as NSString).lastPathComponent), #line, #function, window.frame.debugDescription)
    }

}

// MARK: - TrackingAreaResponderDelegate
extension MenuBarRatingControl: TrackingAreaResponderDelegate {

    func mouseEntered(with event: NSEvent) {
        os_log("%{public}s[%{public}ld], %{public}s: mouse entered", ((#file as NSString).lastPathComponent), #line, #function)
    }

    func mouseExited(with event: NSEvent) {
        os_log("%{public}s[%{public}ld], %{public}s: mouse exited", ((#file as NSString).lastPathComponent), #line, #function)
    }

}

extension NSPopover {

    // tweak NSPopoverFrame: https://github.com/mstg/OSX-Runtime-Headers/blob/master/AppKit/NSPopoverFrame.h
    func configureCloseButton() {
        guard let popoverViewController = contentViewController as? PopoverViewController,
        let superView = popoverViewController.view.superview else {
            os_log("%{public}s[%{public}ld], %{public}s: ERROR - Unable to find popover superview", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        guard NSStringFromClass(type(of: superView)) == "NSPopoverFrame" else {
            os_log("%{public}s[%{public}ld], %{public}s: ERROR - Superview is not NSPopoverFrame: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, NSStringFromClass(type(of: superView)))
            return
        }

        guard let closeButton = superView.value(forKey: "closeButton") as? NSButton else {
            os_log("%{public}s[%{public}ld], %{public}s: ERROR - Unable to find closeButton in popover", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        // Tweak works under 10.14, 10.15

        closeButton.image = nil
        closeButton.isEnabled = false

        // tell view controller we tweak it
        popoverViewController.hostPopover = self
    }

}

/// Image view that never takes mouse events, so clicks on the favorite heart reach the status bar button.
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
