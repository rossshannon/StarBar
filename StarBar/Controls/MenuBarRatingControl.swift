//
//  MenuBarRatingControl.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-7-20.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa
import ScriptingBridge
import os

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
    let ratingControl = RatingControl(rating: 0, drawsFavorite: false)
    let menuBarIcon: MenuBarIcon
    /// Both heart appearances share a view anchored independently of the centred strip.
    private let favoriteHeartView: NSImageView = {
        let imageView = PassthroughImageView()
        imageView.imageScaling = .scaleNone
        imageView.isHidden = true
        // Follow the actual button right edge when AppKit applies a pending resize.
        imageView.autoresizingMask = MenuBarRatingControl.favoriteHeartAutoresizingMask
        return imageView
    }()
    
    private lazy var filledHeartImage = Stars.filledFavoriteHeartImage(size: ratingControl.starSize)
    private lazy var outlinedHeartImage = Stars.outlinedFavoriteHeartImage(size: ratingControl.starSize)

    /// Shown in the plus's place while the song is being added: the turning circle with a gap
    /// that Apple Music itself shows. Music takes about 3.5 seconds, so the button has to look
    /// busy, and this is the indicator the user has just seen in Music.
    private let addToLibrarySpinner: AddToLibrarySpinnerView = {
        let view = AddToLibrarySpinnerView()
        view.isHidden = true
        // Stay centred with the strip when the button resizes after statusItem.length changes
        view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        return view
    }()
    /// Turns the spinner while the add is in flight
    private var spinnerTimer: RatingReminderTimer?
    private var spinnerStart: Date?

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
            isStopped: { [unowned self] in !self.playbackState.canInteract },
            toggleFavorite: { [unowned self] in self.toggleFavorite() }
        )
        controller.addToLibrary = { [unowned self] in self.addCurrentTrackToLibrary() }
        controller.didPreview = { [unowned self] in self.statusItem.button?.needsDisplay = true }
        controller.didEndDrag = { saved in
            // Player updates are ignored during a drag, and a drag that saves nothing restores
            // the rating from when it began. The track may have changed meanwhile, so ask Music.
            // After a save, don't: the write is still in flight, so Music may answer with the
            // old rating and undo what the user just set.
            guard !saved, !MenuBarRatingControl.isUITesting else { return }
            iTunesPlayer.shared.update()
        }
        return controller
    }()
    /// Calls `clickController.tick()` while a drag is under way
    private var dragTimer: Timer?
    /// The heart the user just set, which song it was for, and when to stop believing it.
    ///
    /// Music takes a moment to apply the write, so its reads are ignored until they agree or
    /// this expires. Without it a player update arriving in between flips the heart back.
    private var pendingFavorite: (value: Bool, trackID: String?, expires: Date)?

    /// How long a heart the user set wins over Music's reads
    static let favoriteWriteWindow: TimeInterval = 2.0

    /// Steps the current width or in-place glyph transition
    private var widthTimer: RatingReminderTimer?
    private var displayedStopped = true
    private var displayedMode: RatingControl.Mode = .rating
    private var rolloutProgress: Double?
    private var collapseProgress: Double?
    private var ratingTransitionTarget: [Star.Style]?
    private var displayedContentWidth: CGFloat?
    private var stripLayout: MenuBarStripLayout {
        MenuBarStripLayout(starSize: ratingControl.starSize, spacing: ratingControl.spacing)
    }
    private let widthClock: RatingReminderClock
    private var displayedSongIdentity: String?
    private lazy var playbackState = MenuBarPlaybackState { [weak self] in
        guard let self = self else { return }
        os_log("Music quit; returning to the stopped icon and resetting the menu bar session")
        // The player popover has nothing left to show
        WindowManager.shared.attachedPopover?.close()
        self.displayedSongIdentity = nil
        self.updateGestureRecognizerBehavior()
        self.updateMenuBar()
    }
    /// How long the status item takes to grow or shrink when the mode changes
    static let modeChangeDuration: TimeInterval = 0.22
    /// Bell and star sweep when an unrated track nears its end. Nil in UI-test mode, which
    /// never reads from Music.
    private var reminderController: RatingReminderController?
    private var reminderSettingObservation: NSKeyValueObservation?

    /// Launched by the UI tests with `-UITesting YES`: shows the stars as if a song is
    /// playing and never reads from or writes to Music: the Music connection isn't started and
    /// the player popover is blocked.
    /// Read from the launch arguments only, not UserDefaults, so a stray `defaults write`
    /// can't switch a normal launch into this mode. Accepts YES, yes, true or 1.
    static let isUITesting: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-UITesting"), index + 1 < arguments.count else { return false }
        return ["yes", "true", "1"].contains(arguments[index + 1].lowercased())
    }()

    private(set) lazy var menuBarMenu: NSMenu = {
        let menu = NSMenu()
        let about = NSMenuItem(title: "About StarBar", action: #selector(WindowManager.aboutMenuItemPressed(_:)), keyEquivalent: "")
        about.target = WindowManager.shared
        menu.addItem(about)
        let preferences = NSMenuItem(title: "Preferences…", action: #selector(WindowManager.preferencesMenuItemPressed(_:)), keyEquivalent: ",")
        preferences.target = WindowManager.shared
        menu.addItem(preferences)
        let showCurrentTrack = NSMenuItem(title: "Show Current Track", action: #selector(TrackAnnouncementController.showCurrentTrackMenuItemPressed(_:)), keyEquivalent: "")
        showCurrentTrack.target = TrackAnnouncementController.shared
        menu.addItem(showCurrentTrack)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit StarBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        }
    }
    private(set) var playState: PlayInfo.PlayerState = .unknown {
        didSet {
            // Not a reason to close the popover: Music sends events with no player state
            // around song changes, streamed songs especially, and the menu bar holds its
            // display through them. The popover closes when Music quits instead.
            updateGestureRecognizerBehavior()
        }
    }

    var isStop: Bool {
        return playbackState.isStopped
    }

    /// Say why a rating shortcut did nothing. Silence here reads as a broken shortcut.
    private func logUnratableShortcut() {
        os_log("%{public}s[%{public}ld], %{public}s: this song has nowhere to keep a rating, so the shortcut does nothing", ((#file as NSString).lastPathComponent), #line, #function)
    }

    /// Where a rating the user chooses should go, or nil when this song cannot be rated.
    ///
    /// Read once per gesture: it reaches `PlayingTrack`, which asks Music whether the track
    /// still exists.
    private var ratingTarget: iTunesTrack? {
        return iTunesPlayer.shared.playing?.ratingTrack
    }
    
    func updateGestureRecognizerBehavior() {
        // Deliver the menu action immediately when there is no current track to rate.
        clickGestureRecognizer.delaysPrimaryMouseButtonEvents = playbackState.canInteract
    }

    init(widthClock: RatingReminderClock = DisplayLinkClock(screen: { NSScreen.main })) {
        self.widthClock = widthClock
        menuBarIcon = MenuBarIcon(size: ratingControl.starSize)

        guard let button = statusItem.button else {
            os_log("%{public}s[%{public}ld], %{public}s: CRITICAL ERROR - Failed to create status item button", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }

        button.image = ratingControl.starsImage
        favoriteHeartView.image = outlinedHeartImage
        button.addSubview(favoriteHeartView)
        button.addSubview(addToLibrarySpinner)
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

        ratingControl.delegate = self
        ratingControl.didChange = { [unowned self] in self.updateAccessibility() }
        button.setAccessibilityLabel("StarBar")

        if MenuBarRatingControl.isUITesting {
            // Property observers don't run inside init, so update by hand
            playState = .playing
            _ = playbackState.update(hasTrack: true, isStopped: false, musicIsRunning: true)
            updateGestureRecognizerBehavior()
            updateMenuBar()
            return
        }

        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesPlayerDidUpdated(_:)), name: .iTunesPlayerDidUpdated, object: nil)

        let reminderController = RatingReminderController(
            ratingControl: ratingControl,
            readPlayer: {
                MenuBarRatingControl.withShortTimeout { _ in
                    guard let track = iTunesPlayer.shared.currentTrack else { return nil }
                    return MenuBarRatingControl.readPlayerSnapshot(track: track, userRating: track.userRating)
                } ?? nil
            },
            readPosition: {
                MenuBarRatingControl.withShortTimeout { iTunes in iTunes.playerPosition } ?? nil
            },
            redraw: { [unowned self] in self.statusItem.button?.needsDisplay = true },
            isBusy: { [unowned self] in self.clickController.isDragging }
        )
        self.reminderController = reminderController
        reminderSettingObservation = UserDefaults.standard.observe(\.remindToRateUnrated, options: [.new]) { [weak reminderController] defaults, _ in
            reminderController?.setEnabled(defaults.remindToRateUnrated)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRatingUp(_:)), name: .iTunesRadioRequestTrackRatingUp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRatingDown(_:)), name: .iTunesRadioRequestTrackRatingDown, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating5(_:)), name: .iTunesRadioRequestTrackRating5, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating4(_:)), name: .iTunesRadioRequestTrackRating4, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating3(_:)), name: .iTunesRadioRequestTrackRating3, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating2(_:)), name: .iTunesRadioRequestTrackRating2, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating1(_:)), name: .iTunesRadioRequestTrackRating1, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.iTunesRadioRequestTrackRating0(_:)), name: .iTunesRadioRequestTrackRating0, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.windowDidResize(_:)), name: NSWindow.didResizeNotification, object: nil)

        // Establish the compact launch state before any player or window notification.
        updateMenuBar(animate: false)
    }

}

extension MenuBarRatingControl {

    /// Width of the visible content, which can be narrower than the allocation while a
    /// collapse is still taking the stars away.
    private var menuBarWidth: CGFloat {
        let margin: CGFloat = 4 + 4
        return isStop
            ? margin + CGFloat(2) * ratingControl.spacing + ratingControl.starSize.width
            : margin + ratingControl.starsImage.size.width
    }

    /// Native width once nothing is animating: the stars keep the full strip, while the add
    /// button and the stopped dot give the unused space back to the menu bar.
    private var settledAllocation: CGFloat {
        return !isStop && ratingControl.mode == .rating ? stripLayout.statusItemWidth : menuBarWidth
    }

    /// A collapse is fading the add button in: the item narrowed a while ago, so clicks land
    private var collapseShowsBadge: Bool {
        return collapseProgress.map { StarCollapse.showsBadge(progress: $0) } ?? false
    }

    /// The content right-aligned in the item's current width
    private func padded(_ content: NSImage) -> NSImage {
        return stripLayout.image(containing: content, allocation: statusItem.length)
    }

    private func updateMenuBar(animate: Bool = true, previousStars: Stars? = nil, animateRatingChange: Bool = false) {
        let wasStopped = displayedStopped
        let changed = displayedStopped != isStop || displayedMode != ratingControl.mode
        let rolls = StarRollout.shouldRoll(wasStopped: wasStopped, isStopped: isStop,
                                          previousMode: displayedMode, mode: ratingControl.mode)
        let collapses = StarCollapse.shouldCollapse(wasStopped: wasStopped, isStopped: isStop,
                                                    previousMode: displayedMode, mode: ratingControl.mode)
        let outgoingStars = previousStars ?? ratingControl.stars
        // Animate changes of control width even when they belong to a new song.
        let changesRating = animateRatingChange && StarRatingTransition.shouldAnimate(
            wasStopped: wasStopped, isStopped: isStop, previousMode: displayedMode,
            mode: ratingControl.mode, from: outgoingStars, to: ratingControl.stars)
        let shouldAnimate = animate || rolls || collapses || changesRating
        displayedStopped = isStop
        displayedMode = ratingControl.mode
        statusItem.button?.setButtonType(!isStop ? .momentaryChange : .onOff)
        updateAccessibility()

        // A library save, a rating update, or the same song coming back after Music briefly
        // sent no track must not restart the current motion or cut it short.
        let canContinueRatingTransition = ratingTransitionTarget == nil
            || (previousStars != nil && ratingTransitionTarget == ratingControl.stars.stars.map { $0.style })
        if widthTimer != nil, !changed, !changesRating, canContinueRatingTransition {
            updateFavoriteHeartView()
            updateAddToLibrarySpinner()
            return
        }
        if widthTimer != nil {
            os_log("Menu bar transition superseded: display changed %{public}d, rating change %{public}d, animate %{public}d",
                   changed, changesRating, shouldAnimate)
        }

        let fromWidth = displayedContentWidth ?? statusItem.length
        widthTimer?.invalidate()
        widthTimer = nil
        rolloutProgress = nil
        collapseProgress = nil
        ratingTransitionTarget = nil
        let toWidth = menuBarWidth
        // A collapse keeps the current width until the stars have gone and narrows the item
        // only while it is empty; see StarCollapse. Widening moves nothing visibly.
        if !collapses {
            statusItem.length = settledAllocation
        }
        guard shouldAnimate, (changed || changesRating), !isStop, fromWidth > 0,
              (fromWidth != toWidth || changesRating || rolls),
              !MenuBarRatingControl.isUITesting,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishWidthAnimation()
            return
        }

        let duration = changesRating ? StarRatingTransition.duration
            : (rolls ? StarRollout.duration : (collapses ? StarCollapse.duration : Self.modeChangeDuration))
        let start = widthClock.now()
        if changesRating {
            ratingTransitionTarget = ratingControl.stars.stars.map { $0.style }
            displayedContentWidth = toWidth
            os_log("Starting in-place menu bar rating transition")
            drawRatingTransition(from: outgoingStars, progress: 0)
        } else if rolls {
            rolloutProgress = 0
            os_log("Starting menu bar star rollout from %{public}s", wasStopped ? "stopped icon" : "add-to-library button")
            drawRollout(progress: 0, fromWidth: fromWidth, toWidth: toWidth)
        } else if collapses {
            os_log("Starting menu bar star collapse to add-to-library button")
            drawCollapse(stars: outgoingStars, progress: 0, fromWidth: fromWidth, toWidth: toWidth)
        } else {
            statusItem.button?.image = padded(ratingControl.starsImage)
        }
        var drawnFrames = 0
        var timing = MenuBarAnimationTiming(duration: duration)
        var firstFrameDelay: TimeInterval?
        var narrowedAt: Date?
        widthTimer = widthClock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            guard let self = self else { return }
            let now = self.widthClock.now()
            let elapsed = now.timeIntervalSince(start)
            if firstFrameDelay == nil {
                firstFrameDelay = elapsed
                if collapses { os_log("Menu bar collapse drew its first frame after %{public}.3f s", elapsed) }
            }
            var progress = timing.progress(at: now)
            if collapses {
                // Time the hidden wait from the narrowing itself, however late that frame was
                progress = StarCollapse.progress(elapsed: progress * duration,
                                                 sinceNarrowing: narrowedAt.map { now.timeIntervalSince($0) })
            }
            if progress >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                if changesRating || collapses {
                    os_log("Completed menu bar transition: %{public}d frames, first-frame wait %{public}.3f s", drawnFrames, firstFrameDelay ?? 0)
                }
                self.finishWidthAnimation()
                return
            }
            drawnFrames += 1
            if changesRating {
                self.drawRatingTransition(from: outgoingStars, progress: progress)
            } else if rolls {
                self.drawRollout(progress: progress, fromWidth: fromWidth, toWidth: toWidth)
            } else if collapses {
                self.drawCollapse(stars: outgoingStars, progress: progress, fromWidth: fromWidth, toWidth: toWidth)
                if narrowedAt == nil, StarCollapse.hasShrunk(progress: progress) { narrowedAt = now }
            } else {
                let eased = CGFloat(TrackAnnouncementPlacement.easeInOut(progress))
                self.displayedContentWidth = fromWidth + (toWidth - fromWidth) * eased
            }
            self.updateFavoriteHeartView()
            self.updateAddToLibrarySpinner()
        }
    }

    private func drawRatingTransition(from stars: Stars, progress: Double) {
        statusItem.button?.image = StarRatingTransition.image(from: stars, to: ratingControl.stars, progress: progress)
        updateFavoriteHeartView()
    }

    private func drawRollout(progress: Double, fromWidth: CGFloat, toWidth: CGFloat) {
        rolloutProgress = progress
        let width = StarRollout.width(from: fromWidth, to: toWidth, progress: progress)
        displayedContentWidth = width
        statusItem.button?.image = padded(StarRollout.image(
            stars: ratingControl.stars, width: max(1, width - 8), progress: progress))
        updateFavoriteHeartView()
    }

    private func drawCollapse(stars: Stars, progress: Double, fromWidth: CGFloat, toWidth: CGFloat) {
        collapseProgress = progress
        if StarCollapse.hasShrunk(progress: progress), statusItem.length != settledAllocation {
            // Nothing is showing now, so the menu bar's slide of the narrower item is unseen
            statusItem.length = settledAllocation
            os_log("Stars gone; narrowing the menu bar item to %{public}.0f pt", settledAllocation)
        }
        let width = StarCollapse.width(from: fromWidth, to: toWidth, progress: progress)
        displayedContentWidth = width
        statusItem.button?.image = padded(StarCollapse.image(
            stars: stars, width: max(1, width - 8), progress: progress,
            isFavorited: ratingControl.isFavorited, isPending: ratingControl.isAddingToLibrary))
        updateFavoriteHeartView()
    }

    private func finishWidthAnimation() {
        widthTimer?.invalidate()
        widthTimer = nil
        rolloutProgress = nil
        collapseProgress = nil
        ratingTransitionTarget = nil
        displayedContentWidth = menuBarWidth
        statusItem.length = settledAllocation
        statusItem.button?.image = !isStop ? padded(ratingControl.starsImage) : menuBarIcon.image
        updateFavoriteHeartView()
        updateAddToLibrarySpinner()
    }

    /// VoiceOver reads the rating, and the UI tests check it
    private func updateAccessibility() {
        let value = isStop
            ? "Not playing"
            : RatingControl.accessibilityDescription(mode: ratingControl.mode, rating: ratingControl.rating, isFavorited: ratingControl.isFavorited, isAddingToLibrary: ratingControl.isAddingToLibrary)
        statusItem.button?.setAccessibilityValue(value)
    }

    static let favoriteHeartAutoresizingMask: NSView.AutoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]

    static func favoriteHeartFrame(in bounds: NSRect, size: NSSize) -> NSRect {
        return NSRect(x: bounds.maxX - 4 - size.width,
                      y: 0.5 * (bounds.height - size.height), width: size.width, height: size.height)
    }

    /// Show the current heart appearance over the strip’s reserved, empty slot.
    /// Independent of image width: AppKit may apply the requested status item width later.
    private func updateFavoriteHeartView() {
        guard let button = statusItem.button else { return }
        favoriteHeartView.alphaValue = rolloutProgress.map { StarRollout.heartOpacity(progress: $0) }
            ?? collapseProgress.map { StarCollapse.heartOpacity(progress: $0) } ?? 1
        favoriteHeartView.isHidden = isStop
        guard !favoriteHeartView.isHidden else { return }

        favoriteHeartView.image = ratingControl.isFavorited ? filledHeartImage : outlinedHeartImage
        favoriteHeartView.frame = Self.favoriteHeartFrame(in: button.bounds, size: ratingControl.starSize)
    }
    
    /// Spin a progress indicator where the plus is while the song is being added.
    ///
    /// `AddToLibraryBadge` leaves that slot empty while it waits, so the two never overlap.
    private func updateAddToLibrarySpinner() {
        guard let button = statusItem.button else { return }

        let showsBadge = collapseProgress.map { StarCollapse.showsBadge(progress: $0) } ?? true
        let isWaiting = !isStop && showsBadge && ratingControl.mode == .addToLibrary && ratingControl.isAddingToLibrary
        guard isWaiting else {
            spinnerTimer?.invalidate()
            spinnerTimer = nil
            spinnerStart = nil
            addToLibrarySpinner.isHidden = true
            return
        }

        // Same geometry as the heart overlay, so both sit on their slots in the strip
        let contentWidth = (displayedContentWidth ?? menuBarWidth) - 8
        let leftMargin = MenuBarStripLayout.contentOriginX(in: button.bounds, contentWidth: contentWidth)
        let size = ratingControl.addToLibrarySpinnerSize
        addToLibrarySpinner.frame = NSRect(
            x: leftMargin + ratingControl.addToLibrarySpinnerMinX,
            y: 0.5 * (button.bounds.height - size),
            width: size,
            height: size
        )
        addToLibrarySpinner.isHidden = false

        guard spinnerTimer == nil else { return }
        // Step the angle on each display refresh, like the track announcement's slide, rather
        // than animating it: Core Animation on this kind of window has been seen not to draw
        let start = Date()
        spinnerStart = start
        spinnerTimer = widthClock.schedule(after: 1.0 / 60.0, repeats: true) { [weak self] in
            guard let self = self else { return }
            let turns = Date().timeIntervalSince(start) * Double(AddToLibrarySpinnerView.turnsPerSecond)
            // Clockwise, which is the direction Music turns it
            self.addToLibrarySpinner.angle = CGFloat(-360.0 * turns.truncatingRemainder(dividingBy: 1))
        }
    }

    /// Toggle the favorite status of the current track
    func toggleFavorite() {
        if MenuBarRatingControl.isUITesting {
            ratingControl.updateFavorited(!ratingControl.isFavorited)
            updateFavoriteHeartView()
            return
        }
        guard playbackState.canInteract, let playing = iTunesPlayer.shared.playing else { return }

        os_log("%{public}s[%{public}ld], %{public}s: Toggling favorite status for track: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, playing.track.name ?? "unknown")

        // Flip the heart the user can see, not the one Music last answered with. Music applies
        // the write a moment later, so asking it again straight away can still report the old
        // value -- and two presses in a row then set the same thing, which is how the heart
        // got stuck.
        let isFavorited = !ratingControl.isFavorited
        // The heart goes where the rating goes: the user's own copy of the song, not the
        // catalog track playing it. Music keeps a separate `favorited` on each.
        playing.favoriteTrack.updateFavorited(isFavorited)
        pendingFavorite = (isFavorited, playing.persistentID,
                           Date().addingTimeInterval(MenuBarRatingControl.favoriteWriteWindow))

        // Update our local state immediately
        ratingControl.updateFavorited(isFavorited)
        updateFavoriteHeartView()
        statusItem.button?.needsDisplay = true
        TrackAnnouncementController.shared?.userDidFavorite(isFavorited)

        // Deliberately no forced player update here: it reads Music back before the write has
        // landed, and the stale answer would put the heart straight back.
    }

    /// The heart to show: the user's own while Music has yet to report it, otherwise Music's.
    ///
    /// Music is believed again as soon as it agrees, so a change made in Music straight
    /// afterwards isn't held back for the rest of the window.
    private func favoriteToShow(musicSays: Bool, trackID: String?, now: Date = Date()) -> Bool {
        guard let pending = pendingFavorite else { return musicSays }
        guard pending.trackID == trackID, now < pending.expires, musicSays != pending.value else {
            pendingFavorite = nil
            return musicSays
        }
        return pending.value
    }

}

extension MenuBarRatingControl {

    @objc private func action(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else {
            return
        }
        os_log("%{public}s[%{public}ld], %{public}s: menu bar button receive event %s", ((#file as NSString).lastPathComponent), #line, #function, event.debugDescription)

        switch event.type {
        case .leftMouseUp where !playbackState.canInteract:
            let position = NSPoint(x: 0, y: sender.bounds.height + 8)
            menuBarMenu.popUp(positioning: nil, at: position, in: sender)
        case .rightMouseUp where !playbackState.canInteract:
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
        if ratingTransitionTarget != nil || collapseShowsBadge { finishWidthAnimation() }
        // The strip is mid-resize: the mode and image have already changed but the button has
        // not finished narrowing, so a click maps to the wrong position. That is enough to add
        // a song the user did not mean to add. Once a collapse shows the add button the width
        // has long stopped changing, so the click is taken and the collapse finished above.
        guard widthTimer == nil else {
            os_log("%{public}s[%{public}ld], %{public}s: ignoring a click while the strip is still resizing", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }
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
        if ratingTransitionTarget != nil || collapseShowsBadge { finishWidthAnimation() }
        guard widthTimer == nil, playbackState.canInteract else { return }
        reminderController?.stopSweep()
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
        // A deleted track can keep its stars until the library notification arrives. Check
        // before committing: a refused gesture must not change the stars, announcement or
        // reminder. UI tests intentionally have no Music target.
        if !MenuBarRatingControl.isUITesting && ratingTarget?.exists?() != true {
            os_log("%{public}s[%{public}ld], %{public}s: rating target disappeared; refreshing the player", ((#file as NSString).lastPathComponent), #line, #function)
            iTunesPlayer.shared.update()
            return false
        }
        return playbackState.canInteract
    }

    func ratingControl(_ ratingControl: RatingControl, userDidUpdateRating rating: Int) {
        reminderController?.userDidRate()
        TrackAnnouncementController.shared?.userDidRate(rating)
        // Update iTunes current track rating
        if !MenuBarRatingControl.isUITesting {
            iTunesRadioStation.shared.setRating(rating, on: ratingTarget)
        }
        statusItem.button?.needsDisplay = true
    }

}

extension MenuBarRatingControl {

    @objc func iTunesPlayerDidUpdated(_ notification: Notification) {
        guard !MenuBarRatingControl.isUITesting else { return }
        let player = iTunesPlayer.shared

        isPlaying = player.isPlaying
        // One record answers what is playing and where its rating lives, so the stars, the
        // shortcuts and the track announcement cannot disagree about it
        applyTrackDisplay(player.playing, isStopped: playState == .unknown,
                          musicIsRunning: iTunesRadioStation.shared.iTunes != nil)
    }

    /// Apply a refreshed track through the same transition path whether it came from a
    /// song change, a library edit, or a rejected click on a deleted rating target.
    func applyTrackDisplay(_ playing: PlayingTrack?, isStopped: Bool, musicIsRunning: Bool) {
        let wasStopped = isStop
        let wasWaiting = playbackState.isWaitingForTrack
        let canShowTrack = playbackState.update(hasTrack: playing != nil,
                                               isStopped: isStopped,
                                               musicIsRunning: musicIsRunning)
        updateGestureRecognizerBehavior()
        guard canShowTrack else {
            if !wasStopped, !wasWaiting, playbackState.isWaitingForTrack {
                os_log("Menu bar holding its last display until Music supplies a track or quits")
            }
            reminderController?.playerDidUpdate(nil)
            return
        }

        let identity = playing?.persistentID ?? iTunesRadioStation.shared.latestPlayInfo?.songIdentity
        let isNewSong = identity != displayedSongIdentity
        displayedSongIdentity = identity
        let ratedTrack = playing?.ratingTrack
        let previousStars = ratingControl.stars

        // Apply only a usable track. An empty update above leaves the previous strip intact;
        // a catalog track without a library copy shows the add button instead of stars.
        ratingControl.update(mode: playing.map { $0.canRate ? .rating : .addToLibrary } ?? .rating)

        let userRating = ratedTrack?.userRating
        // Don't overwrite the stars the user is dragging across
        if !clickController.isDragging {
            ratingControl.update(rating: userRating ?? 0)
        }
        ratingControl.updateFavorited(favoriteToShow(musicSays: playing?.favoriteTrack.isFavorited ?? false,
                                                     trackID: playing?.persistentID))
        // Replacement songs change glyphs in place; mode changes also animate the width.
        // Preserve the old star shapes before the new song replaces the control's contents.
        updateMenuBar(animate: wasStopped || (!isNewSong && !wasWaiting), previousStars: previousStars,
                      animateRatingChange: isNewSong || wasWaiting)
        if !wasStopped, isNewSong || wasWaiting, widthTimer == nil {
            os_log("Menu bar replaced the displayed song without animation")
        }
        // A catalog track is permanently unrated, so without this the reminder would ring for
        // every one of them and sweep a star across a control that has no stars
        if UserDefaults.standard.remindToRateUnrated && ratingControl.mode == .rating {
            let snapshot = ratedTrack.flatMap { MenuBarRatingControl.readPlayerSnapshot(track: $0, userRating: userRating, isPlaying: isPlaying, trackID: playing?.persistentID) }
            reminderController?.playerDidUpdate(snapshot)
        } else {
            reminderController?.playerDidUpdate(nil)
        }
    }

    /// The Apple Music button was pressed: add the song, then show its stars.
    ///
    /// Music's add is asynchronous, so the stars appear a moment later, once the song is
    /// really in the library. Waiting is the point: stars shown before then would have
    /// nowhere to write.
    func addCurrentTrackToLibrary() {
        let pressedForPlayingID = iTunesPlayer.shared.playing?.persistentID
        // Music takes seconds over this, so say so rather than leaving the button untouched
        ratingControl.update(isAddingToLibrary: true)
        statusItem.button?.image = padded(ratingControl.starsImage)
        updateAddToLibrarySpinner()
        statusItem.button?.needsDisplay = true

        iTunesRadioStation.shared.addCurrentTrackToLibrary { [weak self] added in
            guard let self = self else { return }
            self.ratingControl.update(isAddingToLibrary: false)
            if self.widthTimer == nil {
                self.statusItem.button?.image = self.padded(self.ratingControl.starsImage)
            }
            self.updateAddToLibrarySpinner()
            self.statusItem.button?.needsDisplay = true

            guard let added = added else {
                // The add failed and was logged. Leave the button up rather than showing
                // stars that would go nowhere.
                return
            }
            // The song can change while the add is in flight, and the stars would then belong
            // to the wrong one. The song is still in the library either way.
            guard let playing = iTunesPlayer.shared.playing,
                  pressedForPlayingID != nil,
                  playing.persistentID == pressedForPlayingID else {
                os_log("%{public}s[%{public}ld], %{public}s: the song changed while it was being added, leaving the stars alone", ((#file as NSString).lastPathComponent), #line, #function)
                return
            }

            playing.didAddToLibrary(added)
            // The heart moves with the rating: from here on it is read from the new copy,
            // which starts out unfavourited. A heart set before the song was added was
            // written to the catalog track, so carry it across or the next read empties it.
            // Only ever set, never clear -- nothing here should undo a favourite Music has.
            if self.ratingControl.isFavorited && !added.isFavorited {
                added.updateFavorited(true)
                self.pendingFavorite = (true, playing.persistentID,
                                        Date().addingTimeInterval(MenuBarRatingControl.favoriteWriteWindow))
            }
            self.ratingControl.update(mode: .rating)
            self.ratingControl.update(rating: added.userRating ?? 0)
            self.updateMenuBar()
        }
    }

    /// Run the rating reminder's own reads with a 1 second Apple Event timeout. Returns nil
    /// without sending anything when Music isn't running, so a stale track never relaunches it.
    ///
    /// A position read usually takes about 17 ms. These reads run on the main thread from a
    /// timer, so if Music hangs, the default timeout of about 2 minutes would freeze the menu bar.
    static func withShortTimeout<T>(_ read: (iTunesApplication) -> T) -> T? {
        guard let iTunes = iTunesRadioStation.shared.iTunes, let application = iTunes as? SBApplication else { return nil }
        let timeout = application.timeout
        application.timeout = 60  // ticks: 1/60 s each
        defer { application.timeout = timeout }
        return read(iTunes)
    }

    /// Read what the rating reminder needs. Each property read is an Apple Event, so pass in
    /// values already read. Call only while Music is running.
    ///
    /// - Parameter isPlaying: the player state, or nil to read it
    static func readPlayerSnapshot(track: iTunesTrack, userRating: Int?, isPlaying: Bool? = nil, trackID: String? = nil) -> RatingReminderController.PlayerSnapshot? {
        // A read that timed out gives an empty ID, which would look like a different track
        guard let iTunes = iTunesRadioStation.shared.iTunes,
              let trackID = trackID ?? track.persistentID, !trackID.isEmpty else { return nil }
        return RatingReminderController.PlayerSnapshot(
            trackID: trackID,
            isPlaying: isPlaying ?? (iTunes.playerState == .playing),
            position: iTunes.playerPosition ?? 0,
            duration: track.duration ?? 0,
            isRated: (userRating ?? 0) > 0
        )
    }

    @objc func iTunesRadioRequestTrackRatingUp(_ notification: Notification) {
        isPlaying = iTunesPlayer.shared.isPlaying
        defer { updateMenuBar() }
        guard playbackState.canInteract else {
            return
        }
        // The stars aren't showing for a song that can't be rated, and the keyboard must not
        // put a rating where the mouse can't -- Music would refuse it and the user would see
        // a rating that never saved
        guard let target = ratingTarget else { return logUnratableShortcut() }
        let ratingChange: Int = UserDefaults.standard.allowHalfStar ? 10 : 20
        ratingControl.update(rating: ratingControl.rating + ratingChange)
        iTunesRadioStation.shared.setRating(ratingControl.rating, on: target)
        reminderController?.userDidRate()
        TrackAnnouncementController.shared?.userDidRate(ratingControl.rating)
    }

    @objc func iTunesRadioRequestTrackRatingDown(_ notification: Notification) {
        isPlaying = iTunesPlayer.shared.isPlaying
        defer { updateMenuBar() }
        guard playbackState.canInteract else {
            return
        }

        guard let target = ratingTarget else { return logUnratableShortcut() }
        let ratingChange: Int = UserDefaults.standard.allowHalfStar ? 10 : 20
        ratingControl.update(rating: ratingControl.rating - ratingChange)
        iTunesRadioStation.shared.setRating(ratingControl.rating, on: target)
        reminderController?.userDidRate()
        TrackAnnouncementController.shared?.userDidRate(ratingControl.rating)
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
      defer { updateMenuBar() }
      guard playbackState.canInteract else {
          return
      }

      guard let target = ratingTarget else { return logUnratableShortcut() }
      ratingControl.update(rating: stars * 20)
      iTunesRadioStation.shared.setRating(ratingControl.rating, on: target)
      reminderController?.userDidRate()
      TrackAnnouncementController.shared?.userDidRate(ratingControl.rating)
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

/// Image view that never takes mouse events, so clicks on the favorite heart reach the status bar button.
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
