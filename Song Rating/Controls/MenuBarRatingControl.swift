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
    private let panGestureRecognizer = NSPanGestureRecognizer()
    /// Turns the menu bar's click into a rating, a favorite toggle, or a drag
    private lazy var clickController: RatingClickController = {
        let controller = RatingClickController(
            ratingControl: ratingControl,
            pointer: StatusButtonPointer(button: statusItem.button, ratingControl: ratingControl),
            // With half stars on, the left half of a star (or the gap before it) sets a half star
            behavior: { UserDefaults.standard.allowHalfStar ? .both : .full },
            isStopped: { [unowned self] in self.isStop },
            toggleFavorite: { [unowned self] in self.toggleFavorite() }
        )
        controller.didPreview = { [unowned self] in self.statusItem.button?.needsDisplay = true }
        return controller
    }()
    /// Calls `clickController.tick()` while a drag is under way
    private var dragTimer: Timer?

    /// Launched by the UI tests with `-UITesting YES`: shows the stars as if a song is
    /// playing and never reads from or writes to Music.
    static let isUITesting = UserDefaults.standard.bool(forKey: "UITesting")

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
        // and no drag events, so the click recognizer starts drags too. On earlier macOS a drag
        // makes the click recognizer fail, and the pan recognizer starts it instead. Either way
        // RatingClickController then follows the drag by reading the mouse.
        clickGestureRecognizer.action = #selector(MenuBarRatingControl.clickGestureRecognizerHandler(_:))
        clickGestureRecognizer.target = self
        button.addGestureRecognizer(clickGestureRecognizer)

        panGestureRecognizer.action = #selector(MenuBarRatingControl.panGestureRecognizerHandler(_:))
        panGestureRecognizer.target = self
        button.addGestureRecognizer(panGestureRecognizer)

        let trackingArea = NSTrackingArea(rect: button.bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved], owner: trackingAreaResponser, userInfo: nil)
        button.addTrackingArea(trackingArea)

        trackingAreaResponser.delegate = self

        ratingControl.delegate = self
        ratingControl.didChange = { [unowned self] in self.updateAccessibility() }
        button.setAccessibilityLabel("Music Rating")

        if MenuBarRatingControl.isUITesting {
            // Property observers don't run inside init, so update by hand
            playState = .playing
            updateGestureRecognizerBehavior()
            updateMenuBar()
            return
        }

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
        updateAccessibility()
    }

    /// VoiceOver reads the rating, and the UI tests check it
    private func updateAccessibility() {
        let value = isStop
            ? "Not playing"
            : RatingControl.accessibilityDescription(rating: ratingControl.rating, isFavorited: ratingControl.isFavorited)
        statusItem.button?.setAccessibilityValue(value)
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
        if MenuBarRatingControl.isUITesting {
            ratingControl.updateFavorited(!ratingControl.isFavorited)
            updateFavoriteHeartView()
            return
        }
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
    
    @objc private func clickGestureRecognizerHandler(_ sender: NSClickGestureRecognizer) {
        os_log("%{public}s[%{public}ld], %{public}s: %s", ((#file as NSString).lastPathComponent), #line, #function, sender.debugDescription)
        guard sender.state == .ended else { return }
        handlePress()
    }

    /// Before macOS 27, dragging sends real drag events: start following the drag when it begins.
    @objc private func panGestureRecognizerHandler(_ sender: NSPanGestureRecognizer) {
        os_log("%{public}s[%{public}ld], %{public}s: %s", ((#file as NSString).lastPathComponent), #line, #function, sender.debugDescription)
        guard sender.state == .began, !clickController.isDragging else { return }
        handlePress()
    }

    /// Hand the press to the click controller, and follow the drag if one begins
    private func handlePress() {
        dragTimer?.invalidate()
        dragTimer = nil
        guard clickController.click() else { return }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self, self.clickController.tick() else {
                timer.invalidate()
                return
            }
        }
        // .common keeps the timer firing while AppKit tracks the mouse
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

}

// MARK: - RatingControlDelegate
extension MenuBarRatingControl: RatingControlDelegate {

    func ratingControl(_ ratingControl: RatingControl, shouldUpdateRating rating: Int) -> Bool {
        return !isStop
    }

    func ratingControl(_ ratingControl: RatingControl, userDidUpdateRating rating: Int) {
        // Update iTunes current track rating
        if !MenuBarRatingControl.isUITesting {
            iTunesRadioStation.shared.setRating(rating)
        }
        statusItem.button?.needsDisplay = true
    }

}

extension MenuBarRatingControl {

    @objc func iTunesPlayerDidUpdated(_ notification: Notification) {
        guard !MenuBarRatingControl.isUITesting else { return }
        let player = iTunesPlayer.shared

        isPlaying = player.isPlaying
        // Each property read is an Apple Event, so read the track once
        let track = player.currentTrack
        // Don't overwrite the stars the user is dragging across
        if !clickController.isDragging {
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
