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
    private lazy var spotifyHeartImage = Stars.spotifyHeartImage(size: ratingControl.starSize)
    private lazy var spotifyOutlinedHeartImage = Stars.spotifyOutlinedHeartImage(size: ratingControl.starSize)

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
    /// The mouse the stars read, when a test supplies one
    private let pointer: RatingPointer?
    /// Turns the menu bar's click into a rating, a favorite toggle, or a drag. Not private
    /// only so the tests can click.
    private(set) lazy var clickController: RatingClickController = {
        let controller = RatingClickController(
            ratingControl: ratingControl,
            pointer: pointer ?? StatusButtonPointer(button: statusItem.button, ratingControl: ratingControl),
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
    /// The heart the user just set, held over Music's reads until Music agrees.
    ///
    /// Music takes a moment to apply the write, so its reads are ignored until they agree or
    /// the hold runs out. Without it a player update arriving in between flips the heart back.
    private var heldFavorite = HeldChoice<Bool>()

    /// How long a heart the user set wins over Music's reads
    static let favoriteWriteWindow: TimeInterval = 2.0

    /// The rating the user just chose, held as the heart is. A rating can wait in
    /// `RatingWriter` for up to `iTunesRadioStation.ratingSaveDelay` before Music has it, and
    /// a read in that time put the old stars back: the library read a rating's own library
    /// change starts, answering for the user's copy of a Spotify song (the second review,
    /// 2026-10-29).
    private var heldRating = HeldChoice<Int>()

    /// How long a rating the user chose wins over Music's reads: the save delay, plus time for
    /// the Apple Event, as the strip allows
    static let ratingWriteWindow: TimeInterval = iTunesRadioStation.ratingSaveDelay + 1.0

    /// The user's own Music copy of the Spotify song on show, whose stars and heart stand in
    /// for Spotify's. Nil whenever Music's own song or Spotify's heart is on show.
    private var libraryMatch: LibraryMatch? {
        didSet {
            // A drag under way would be let go of over another copy's stars, or Music's own
            if libraryMatch?.song.persistentID != oldValue?.song.persistentID {
                clickController.cancelDrag()
            }
        }
    }
    /// The display waits for the answer about a Spotify song's Music copy, briefly, rather
    /// than show Spotify's heart and then swap it for stars
    private let matchWait = LibraryMatchWait()
    /// The Spotify song whose Music copy is being looked for
    private var awaitingMatch: String? {
        return matchWait.identity
    }
    /// How long to wait for that answer before showing Spotify's heart anyway. Reading the
    /// library took about 250 ms when measured, and the matcher is built after it.
    static let libraryMatchWait: TimeInterval = 1.0
    /// The same, before the library has been read at all. The first read builds the matcher
    /// from nothing, about 420 ms of the 1.1 s the first song took measured on 2026-10-29,
    /// where the next five took 0.1 to 0.25 s; at 1 s, the first song after a launch showed
    /// Spotify's heart and then swapped it for stars.
    static let firstLibraryMatchWait: TimeInterval = 2.0

    /// The wait for the answer about the song on show now
    static var libraryMatchWaitNow: TimeInterval {
        return LibraryMatchFinder.shared.hasReadLibrary ? libraryMatchWait : firstLibraryMatchWait
    }

    /// A Spotify song is on show, or about to be: its heart, or its Music copy's stars
    private var showsSpotifySong: Bool {
        return ratingControl.mode == .spotify || libraryMatch != nil || awaitingMatch != nil
    }

    /// Steps the current width or in-place glyph transition
    private var widthTimer: RatingReminderTimer?
    private var displayedStopped = true
    private var displayedMode: RatingControl.Mode = .rating
    private var rolloutProgress: Double?
    /// How far Spotify's green heart has faded, while it fades out ahead of a rollout
    private var spotifyHeartFadeProgress: Double?
    /// Whether Spotify's heart was last drawn filled, so it keeps that look while it fades
    /// out after the mode has changed
    private var spotifyHeartWasFilled = true
    private var collapseProgress: Double?
    private var ratingTransitionTarget: [Star.Style]?
    private var displayedContentWidth: CGFloat?
    private var stripLayout: MenuBarStripLayout {
        MenuBarStripLayout(starSize: ratingControl.starSize, spacing: ratingControl.spacing)
    }
    private let widthClock: RatingReminderClock
    /// The song on show, Music's or Spotify's. A drag under way began on the one before, so a
    /// change drops it: let go of over the new song's stars, it would rate that song.
    private var displayedSongIdentity: String? {
        didSet {
            if displayedSongIdentity != oldValue {
                clickController.cancelDrag()
            }
        }
    }
    private lazy var playbackState = MenuBarPlaybackState { [weak self] in
        guard let self = self else { return }
        os_log("Music quit; returning to the stopped icon and resetting the menu bar session")
        // The player popover has nothing left to show
        WindowManager.shared.closeAttachedPopover()
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

    /// True while the user drags across the stars, when Apple Events would stall the preview
    var isDragging: Bool {
        return clickController.isDragging
    }

    /// Say why a rating shortcut did nothing. Silence here reads as a broken shortcut.
    private func logUnratableShortcut() {
        os_log("%{public}s[%{public}ld], %{public}s: this song has nowhere to keep a rating, so the shortcut does nothing", ((#file as NSString).lastPathComponent), #line, #function)
    }

    /// Where a rating the user chooses should go, or nil when this song cannot be rated.
    ///
    /// Read once per gesture: it reaches `PlayingTrack`, which asks Music whether the track
    /// still exists. For a Spotify song it is the user's own copy in Music, when they have
    /// one, and otherwise nil, so the rating shortcuts can't rate the song left paused in
    /// Music -- nor while that copy is still being looked for, nor once Music has quit, which
    /// an Apple Event to the copy would open again.
    private var ratingTarget: iTunesTrack? {
        guard awaitingMatch == nil else { return nil }
        if let match = libraryMatch {
            return iTunesRadioStation.shared.iTunes == nil ? nil : match.track
        }
        guard ratingControl.mode != .spotify else { return nil }
        return iTunesPlayer.shared.playing?.ratingTrack
    }

    /// The persistent ID a rating chosen now is held and written under: the user's copy of the
    /// Spotify song on show, or Music's own song
    private var ratedTrackID: String? {
        return libraryMatch?.song.persistentID ?? iTunesPlayer.shared.playing?.persistentID
    }

    /// The user chose `rating` for the song on show: tell the reminder and the strip, then
    /// save it. The strip is told first, so that it counts Music's refusals from before the
    /// write: one arrives while the write is sent. Where the rating goes is worked out once,
    /// before the strip asks Music which song is playing, so that the strip's hold, the menu
    /// bar's and the write are all for the one song: a hold under another persistent ID than
    /// the write's never hears that Music refused it.
    private func choose(rating: Int) {
        reminderController?.userDidRate()
        let match = libraryMatch
        let trackID = ratedTrackID
        let target = ratingTarget
        TrackAnnouncementController.shared?.userDidRate(rating, heldFor: trackID)
        saveRating(rating, to: match, on: target, heldFor: trackID)
    }

    /// Save a rating the user chose for the song on show: to the user's copy of the Spotify
    /// song, `match`, a write the station logs in full, or else to Music's own song, `target`,
    /// held under `trackID`
    private func saveRating(_ rating: Int, to match: LibraryMatch?, on target: iTunesTrack?, heldFor trackID: String?) {
        let station = iTunesRadioStation.shared
        // Held before the write is sent, so that Music refusing it ends the hold
        if let match = match {
            let trackID = match.song.persistentID
            heldRating.hold(rating, for: trackID, during: MenuBarRatingControl.ratingWriteWindow,
                            refusals: station.refusedWrites(.rating, to: trackID))
            LibraryMatchFinder.shared.userDidRate(trackID, rating: rating)
            station.setRating(rating, on: match)
        } else {
            heldRating.hold(rating, for: trackID, during: MenuBarRatingControl.ratingWriteWindow,
                            refusals: station.refusedWrites(.rating, to: trackID))
            station.setRating(rating, on: target, heldFor: trackID)
        }
    }

    /// Whether a rating shortcut has somewhere to put a rating, saying why not in the log.
    /// The user's copy of a Spotify song is checked as a click on its stars is: a copy deleted
    /// in Music keeps its stars until Music's notification comes, and the library is read
    /// again instead. The write would fail safely, since it finds the copy by persistent ID,
    /// but the stars would say it was saved.
    private func shortcutCanRate() -> Bool {
        guard ratingTarget != nil else {
            logUnratableShortcut()
            return false
        }
        if let match = libraryMatch, matchedCopyHasGone(match) {
            return false
        }
        return true
    }
    
    func updateGestureRecognizerBehavior() {
        // Deliver the menu action immediately when there is no current track to rate.
        clickGestureRecognizer.delaysPrimaryMouseButtonEvents = playbackState.canInteract
    }

    /// `pointer` is for the tests; the menu bar reads the real mouse
    init(widthClock: RatingReminderClock = DisplayLinkClock(screen: { NSScreen.main }), pointer: RatingPointer? = nil) {
        self.widthClock = widthClock
        self.pointer = pointer
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
            _ = playbackState.update(hasTrack: true, isStopped: false, isRunning: true)
            updateGestureRecognizerBehavior()
            updateMenuBar()
            return
        }

        // Through the arbiter rather than straight from Music: while Spotify is the player
        // being followed, Music's own updates (a library re-read, a wake) must not paint its
        // stars over Spotify's heart
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.nowPlayingDidUpdate(_:)), name: .nowPlayingDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.spotifyLikeDidChange(_:)), name: .spotifyLikeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenuBarRatingControl.spotifyLikeDidChange(_:)), name: .spotifyAccountDidChange, object: nil)

        let reminderController = RatingReminderController(
            ratingControl: ratingControl,
            readPlayer: {
                // The song's rating where the stars read it, and none when any of it went
                // unanswered: a rating read Music didn't answer is 0, which rang the reminder
                // for a rated song (the sixth review, 2026-10-30)
                MenuBarRatingControl.withShortTimeoutIfAnswered { _ in
                    guard let playing = iTunesPlayer.shared.playing, let track = playing.ratingTrack else { return nil }
                    return MenuBarRatingControl.readPlayerSnapshot(track: track, userRating: track.userRating, trackID: playing.persistentID)
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
        let rollsFromSpotify = rolls && !wasStopped && displayedMode == .spotify
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
        spotifyHeartFadeProgress = nil
        ratingTransitionTarget = nil
        let toWidth = menuBarWidth
        // A collapse keeps the current width until the stars have gone and narrows the item
        // only while it is empty; see StarCollapse. A rollout from Spotify keeps it until the
        // green heart has faded, because macOS 27 first draws a widened item over the icon to
        // its right: measured, the heart faded out a whole icon away from where it had been.
        if !collapses && !rollsFromSpotify {
            statusItem.length = settledAllocation
        }
        guard shouldAnimate, (changed || changesRating), !isStop, fromWidth > 0,
              (fromWidth != toWidth || changesRating || rolls),
              !MenuBarRatingControl.isUITesting,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishWidthAnimation()
            return
        }

        let heartFade = rollsFromSpotify ? StarRollout.outgoingHeartFadeDuration : 0
        let duration = changesRating ? StarRatingTransition.duration
            : (rolls ? heartFade + StarRollout.duration : (collapses ? StarCollapse.duration : Self.modeChangeDuration))
        let start = widthClock.now()
        if changesRating {
            ratingTransitionTarget = ratingControl.stars.stars.map { $0.style }
            displayedContentWidth = toWidth
            os_log("Starting in-place menu bar rating transition")
            drawRatingTransition(from: outgoingStars, progress: 0)
        } else if rollsFromSpotify {
            os_log("Starting menu bar star rollout from Spotify's heart")
            spotifyHeartFadeProgress = 0
            drawOutgoingSpotifyIcon(progress: 0)
            updateFavoriteHeartView()
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
                let elapsed = progress * duration
                if elapsed < heartFade {
                    self.spotifyHeartFadeProgress = elapsed / heartFade
                    self.drawOutgoingSpotifyIcon(progress: elapsed / heartFade)
                } else {
                    if self.spotifyHeartFadeProgress != nil {
                        // The heart has gone, so the widened item is drawn empty
                        self.spotifyHeartFadeProgress = nil
                        self.statusItem.length = self.settledAllocation
                    }
                    self.drawRollout(progress: (elapsed - heartFade) / StarRollout.duration,
                                     fromWidth: fromWidth, toWidth: toWidth)
                }
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

    /// Spotify's icon fading out with its heart, where it was, ahead of a rollout. The mode has
    /// already moved on, so the strip is drawn afresh rather than read from the control.
    private func drawOutgoingSpotifyIcon(progress: Double) {
        let strip = RatingControl.spotifyStrip(starSize: ratingControl.starSize, spacing: ratingControl.spacing)
        let opacity = StarRollout.outgoingHeartOpacity(progress: progress)
        let image = NSImage(size: strip.size, flipped: false) { rect in
            strip.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity)
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = padded(image)
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
            isFavorited: ratingControl.isFavorited, isPending: ratingControl.isAddingToLibrary,
            incoming: ratingControl.mode))
        updateFavoriteHeartView()
    }

    private func finishWidthAnimation() {
        widthTimer?.invalidate()
        widthTimer = nil
        rolloutProgress = nil
        collapseProgress = nil
        spotifyHeartFadeProgress = nil
        ratingTransitionTarget = nil
        displayedContentWidth = menuBarWidth
        statusItem.length = settledAllocation
        statusItem.button?.image = !isStop ? padded(ratingControl.starsImage) : menuBarIcon.image
        updateFavoriteHeartView()
        updateAddToLibrarySpinner()
    }

    /// VoiceOver reads the rating, and the UI tests check it
    private func updateAccessibility() {
        let value: String
        if isStop {
            value = "Not playing"
        } else if ratingControl.mode == .spotify {
            value = RatingControl.spotifyAccessibilityDescription(isLiked: spotifyIsLiked)
        } else {
            value = RatingControl.accessibilityDescription(mode: ratingControl.mode, rating: ratingControl.rating, isFavorited: ratingControl.isFavorited, isAddingToLibrary: ratingControl.isAddingToLibrary)
        }
        statusItem.button?.setAccessibilityValue(value)
    }

    static let favoriteHeartAutoresizingMask: NSView.AutoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]

    static func favoriteHeartFrame(in bounds: NSRect, size: NSSize) -> NSRect {
        return NSRect(x: bounds.maxX - 4 - size.width,
                      y: 0.5 * (bounds.height - size.height), width: size.width, height: size.height)
    }

    /// Where the player popover's arrow points, across the button: the gap just left of the
    /// heart, which is between the heart and the stars or the Apple Music button in both modes.
    /// The heart is anchored to the button's right edge, so this point stays with it whatever
    /// width the item has; the middle of the button would not, because while the strip animates
    /// the allocation can be wider than what is drawn, with blank space on the left. The middle
    /// of the icon when stopped.
    static func popoverAnchorX(in bounds: NSRect, starSize: NSSize, spacing: CGFloat, isStopped: Bool) -> CGFloat {
        guard !isStopped else { return bounds.midX }
        return favoriteHeartFrame(in: bounds, size: starSize).minX - 0.5 * spacing
    }

    /// `popoverAnchorX` as a zero-width rect the height of the button, in screen coordinates
    var popoverAnchorInScreen: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let x = Self.popoverAnchorX(in: button.bounds, starSize: ratingControl.starSize,
                                    spacing: ratingControl.spacing, isStopped: isStop)
        let rect = NSRect(x: x, y: button.bounds.minY, width: 0, height: button.bounds.height)
        return window.convertToScreen(button.convert(rect, to: nil))
    }

    /// Show the current heart appearance over the strip’s reserved, empty slot.
    /// Independent of image width: AppKit may apply the requested status item width later.
    private func updateFavoriteHeartView() {
        guard let button = statusItem.button else { return }
        // Every layout change comes through here, so an open popover follows the heart
        WindowManager.shared.updatePopoverAnchor()
        // A rollout from Spotify fades the green heart out, in place, before the stars come in
        let showsOutgoingSpotifyHeart = spotifyHeartFadeProgress != nil
        favoriteHeartView.alphaValue = spotifyHeartFadeProgress.map { StarRollout.outgoingHeartOpacity(progress: $0) }
            ?? rolloutProgress.map { StarRollout.heartOpacity(progress: $0) }
            ?? collapseProgress.map { StarCollapse.heartOpacity(progress: $0) } ?? 1
        favoriteHeartView.isHidden = isStop
        guard !favoriteHeartView.isHidden else { return }

        // A collapse into Spotify mode keeps Music's heart until it has faded out with the
        // stars: turning green at once made the outgoing Music song look like a favourite
        let showsIncomingHeart = collapseProgress.map { StarCollapse.showsBadge(progress: $0) } ?? true
        if (ratingControl.mode == .spotify && showsIncomingHeart) || showsOutgoingSpotifyHeart {
            if ratingControl.mode == .spotify {
                // Without a sign-in the heart only says that Spotify is playing, as it did
                // before likes, so it stays filled. Signed in, it is filled only for a song
                // Spotify has said is liked: an outline while the answer is on its way.
                spotifyHeartWasFilled = !SpotifyAccount.shared.isConnected || spotifyIsLiked == true
            }
            favoriteHeartView.image = spotifyHeartWasFilled ? spotifyHeartImage : spotifyOutlinedHeartImage
        } else {
            favoriteHeartView.image = ratingControl.isFavorited ? filledHeartImage : outlinedHeartImage
        }
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
        guard awaitingMatch == nil else { return }
        if let match = libraryMatch {
            return toggleFavorite(of: match)
        }
        guard playbackState.canInteract, ratingControl.mode != .spotify,
              let playing = iTunesPlayer.shared.playing else { return }

        os_log("%{public}s[%{public}ld], %{public}s: Toggling favorite status for track: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, playing.track.name ?? "unknown")

        // Flip the heart the user can see, not the one Music last answered with. Music applies
        // the write a moment later, so asking it again straight away can still report the old
        // value -- and two presses in a row then set the same thing, which is how the heart
        // got stuck.
        let isFavorited = !ratingControl.isFavorited
        // Before the write, so that the strip counts Music's refusals from before it
        TrackAnnouncementController.shared?.userDidFavorite(isFavorited, heldFor: playing.persistentID)
        // The heart goes where the rating goes: the user's own copy of the song, not the
        // catalog track playing it. Music keeps a separate `favorited` on each.
        writeFavorite(isFavorited, heldFor: playing.persistentID) {
            playing.favoriteTrack.updateFavorited(isFavorited)
        }

        // Update our local state immediately
        ratingControl.updateFavorited(isFavorited)
        updateFavoriteHeartView()
        statusItem.button?.needsDisplay = true

        // Deliberately no forced player update here: it reads Music back before the write has
        // landed, and the stale answer would put the heart straight back.
    }

    /// The heart of the user's own copy of the Spotify song on show. The same as Music's own
    /// heart, written to the copy, and logged because it changes the user's library.
    private func toggleFavorite(of match: LibraryMatch) {
        guard playbackState.canInteract else { return }
        // Flipped on screen for a copy that has gone, the heart would say it was saved
        guard !matchedCopyHasGone(match) else { return }
        let isFavorited = !ratingControl.isFavorited
        os_log("%{public}s[%{public}ld], %{public}s: favourite %{public}d chosen for %{public}s; saving it to library song %{public}s, \u{201C}%{public}s\u{201D} by %{public}s", ((#file as NSString).lastPathComponent), #line, #function, isFavorited ? 1 : 0, match.identity, match.song.persistentID, match.song.name, match.song.artist)
        let trackID = match.song.persistentID
        LibraryMatchFinder.shared.userDidFavorite(trackID, isFavorited: isFavorited)
        TrackAnnouncementController.shared?.userDidFavorite(isFavorited, heldFor: trackID)
        writeFavorite(isFavorited, heldFor: trackID) {
            match.track.updateFavorited(isFavorited)
        }
        ratingControl.updateFavorited(isFavorited)
        updateFavoriteHeartView()
        statusItem.button?.needsDisplay = true
    }

    /// Whether the user's copy of the Spotify song on show is still in Music: false when
    /// Music says it has gone, or has quit, and nil when Music doesn't answer. A copy deleted
    /// there keeps its stars until Music's notification arrives, seconds later. Never asks a
    /// Music that has quit, which the question would open again, and asks under the short
    /// timeout, since this is the main thread.
    ///
    /// No answer is not a copy that has gone: after Music sat idle, the first click was
    /// refused and the whole library read again (the second review, 2026-10-29). So the
    /// gesture goes through, and a write to a copy that has gone fails rather than lands
    /// elsewhere, since `match.track` finds it by persistent ID.
    private func copyIsInMusic(_ match: LibraryMatch) -> Bool? {
        guard iTunesRadioStation.shared.iTunes != nil else { return false }
        return MenuBarRatingControl.withShortTimeoutIfAnswered { _ in match.track.exists?() } ?? nil
    }

    /// True when the copy on show has gone from Music, or Music has quit; starts a new look.
    /// No answer is not gone.
    private func matchedCopyHasGone(_ match: LibraryMatch) -> Bool {
        guard copyIsInMusic(match) == false else { return false }
        lookForSpotifySongAgain()
        return true
    }

    /// The copy on show has gone from Music, or Music has quit. Reading Music's player would
    /// bring the same answer back; the library has to be read again.
    private func lookForSpotifySongAgain() {
        os_log("%{public}s[%{public}ld], %{public}s: the library copy on show has gone, or Music has quit; looking for the Spotify song again", ((#file as NSString).lastPathComponent), #line, #function)
        LibraryMatchFinder.shared.copyIsGone()
        applySpotifyDisplay()
    }

    /// Hold the heart the user chose for the track `trackID` over Music's reads, then `send`
    /// it. Hold first: a refusal arrives inside `send`.
    private func writeFavorite(_ isFavorited: Bool, heldFor trackID: String?, _ send: () -> Void) {
        let station = iTunesRadioStation.shared
        heldFavorite.hold(isFavorited, for: trackID, during: MenuBarRatingControl.favoriteWriteWindow,
                          refusals: station.refusedWrites(.favorite, to: trackID))
        station.sendingWrite(.favorite, to: trackID, send)
    }

    /// Show the stars and heart for the track `trackID` when Music answers `rating` and
    /// `favorite`, nil where it didn't answer: the user's own choice while Music has yet to
    /// report it, otherwise Music's answer. Where Music didn't answer, the stars or heart on
    /// show stay while they are this song's (`isSameSong`), unless Music has refused a write
    /// since they were shown, when its last answer comes back; and otherwise `otherwise`
    /// (`HeldChoice`). The stars stay as they are while the user drags across them.
    ///
    /// Music is believed again as soon as it agrees, so a change made in Music straight
    /// afterwards isn't held back for the rest of the window.
    private func show(rating: Int?, favorite: Bool?, for trackID: String?, isSameSong: Bool, otherwise: (rating: Int, isFavorited: Bool)) {
        let station = iTunesRadioStation.shared
        if !clickController.isDragging {
            ratingControl.update(rating: heldRating.value(answered: rating, trackID: trackID,
                                                          refusals: station.refusedWrites(.rating, to: trackID),
                                                          onShow: ratingControl.rating, isSameSong: isSameSong,
                                                          otherwise: otherwise.rating))
        }
        ratingControl.updateFavorited(heldFavorite.value(answered: favorite, trackID: trackID,
                                                         refusals: station.refusedWrites(.favorite, to: trackID),
                                                         onShow: ratingControl.isFavorited, isSameSong: isSameSong,
                                                         otherwise: otherwise.isFavorited))
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
        case .rightMouseUp where !playbackState.canInteract || showsSpotifySong:
            // The player popover shows Music, which isn't what is playing in Spotify mode,
            // even when the stars on show are the user's own copy of the song
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
        guard awaitingMatch == nil else {
            // What is on show belongs to the last song, and in a moment it won't be there
            os_log("%{public}s[%{public}ld], %{public}s: ignoring a click while looking for the Spotify song in the library", ((#file as NSString).lastPathComponent), #line, #function)
            return
        }
        guard ratingControl.mode != .spotify else {
            // The icon brings Spotify forward. Signed in, the heart likes the song, as Music's
            // heart favourites one. Otherwise, or for a song the Web API can't like (a local
            // file), the heart brings Spotify forward too.
            let positionX = statusItem.button.flatMap { ratingControl.imagePositionX(in: $0) }
            let isOnIcon = positionX.map { ratingControl.isSpotifyIconHit(positionX: $0) } ?? false
            if !isOnIcon, let uri = displayedSongIdentity, SpotifyAccount.shared.canLike(uri) {
                SpotifyAccount.shared.toggleLike(uri)
            } else {
                SpotifyPlayer.shared.activate()
            }
            return
        }
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
        guard awaitingMatch == nil else { return false }
        // A deleted track can keep its stars until the library notification arrives. Check
        // before committing: a refused gesture must not change the stars, announcement or
        // reminder. UI tests intentionally have no Music target.
        if !MenuBarRatingControl.isUITesting, let match = libraryMatch {
            guard !matchedCopyHasGone(match) else { return false }
        } else if !MenuBarRatingControl.isUITesting && ratingTarget?.exists?() != true {
            os_log("%{public}s[%{public}ld], %{public}s: rating target disappeared; refreshing the player", ((#file as NSString).lastPathComponent), #line, #function)
            iTunesPlayer.shared.update()
            return false
        }
        return playbackState.canInteract
    }

    func ratingControl(_ ratingControl: RatingControl, userDidUpdateRating rating: Int) {
        if MenuBarRatingControl.isUITesting {
            reminderController?.userDidRate()
            TrackAnnouncementController.shared?.userDidRate(rating, heldFor: nil)
        } else {
            choose(rating: rating)
        }
        statusItem.button?.needsDisplay = true
    }

}

extension MenuBarRatingControl {

    /// Music or Spotify sent an update, and the arbiter has chosen which one to follow
    @objc func nowPlayingDidUpdate(_ notification: Notification) {
        guard !MenuBarRatingControl.isUITesting else { return }
        if NowPlayingArbiter.shared.active == .spotify {
            applySpotifyDisplay()
            return
        }
        // Following Music, or nothing. A Spotify update changes nothing here, unless Spotify
        // was on show and has just handed the menu bar back.
        guard NowPlayingArbiter.source(of: notification) == .music || showsSpotifySong else { return }
        iTunesPlayerDidUpdated(notification)
    }

    func iTunesPlayerDidUpdated(_ notification: Notification) {
        guard !MenuBarRatingControl.isUITesting else { return }
        let player = iTunesPlayer.shared
        let isRunning = iTunesRadioStation.shared.iTunes != nil

        isPlaying = player.isPlaying
        if showsSpotifySong, player.playing == nil {
            // Spotify has handed back to a Music with nothing to show. Holding the last
            // display would leave Spotify's heart up for a song that is no longer playing.
            applyTrackDisplay(nil, isStopped: true, musicIsRunning: false)
            return
        }
        // One record answers what is playing and where its rating lives, so the stars, the
        // shortcuts and the track announcement cannot disagree about it
        applyTrackDisplay(player.playing, isStopped: playState == .unknown,
                          musicIsRunning: isRunning)
    }

    /// Spotify is the player being followed: its heart on its own, or the user's own Music
    /// copy of the song when they have one, or the last display held while Spotify has no
    /// song to show (an ad, or between songs)
    func applySpotifyDisplay() {
        let spotify = SpotifyPlayer.shared
        let info = spotify.latest
        let canShowTrack = playbackState.update(hasTrack: info?.isAnnounceable == true,
                                               isStopped: info?.state == .stopped,
                                               isRunning: spotify.isRunning)
        updateGestureRecognizerBehavior()
        // Nothing for the reminder to time: it reads Music's position
        reminderController?.playerDidUpdate(nil)
        guard canShowTrack, let info = info, let identity = info.trackID else {
            matchWait.cancel()
            // Holding the last display is right for Spotify's own heart, but not for stars:
            // Music's song is no longer the one on show, since the arbiter only hands over
            // from Music when Music stopped playing or quit, and stars held for the user's
            // copy of a Spotify song would rate it during whatever plays next. Measured:
            // Music quitting while Spotify sat stopped with no track left Music's stars up.
            if ratingControl.mode != .spotify {
                applyTrackDisplay(nil, isStopped: true, musicIsRunning: false)
            }
            return
        }

        if identity != displayedSongIdentity {
            // A heart or rating set for the last song, in Music or on its copy, no longer
            // applies
            heldFavorite.drop()
            heldRating.drop()
        }
        displayedSongIdentity = identity
        // One request per song, and only once signed in
        SpotifyAccount.shared.refreshLike(for: identity)

        var answered = false
        LibraryMatchFinder.shared.match(for: info) { [weak self] match in
            answered = true
            guard let self = self, self.displayedSongIdentity == identity,
                  NowPlayingArbiter.shared.active == .spotify else { return }
            self.matchWait.cancel()
            self.showSpotifySong(match)
        }
        // Music is reading its library. The copy already on show for this song stays until
        // the new answer comes; for a new song, wait a moment rather than show Spotify's
        // heart and swap it for stars straight after.
        guard !answered, libraryMatch?.identity != identity, awaitingMatch != identity else { return }
        // The stars on show are the last song's copy's until the answer comes, and nothing
        // may rate that copy in the meantime
        libraryMatch = nil
        matchWait.start(identity) { [weak self] in
            guard let self = self else { return }
            os_log("%{public}s[%{public}ld], %{public}s: still looking for %{public}s in the library; showing Spotify's heart meanwhile", ((#file as NSString).lastPathComponent), #line, #function, identity)
            self.showSpotifySong(nil)
        }
    }

    /// Show the Spotify song on display: the stars and heart of the user's own copy in Music,
    /// or Spotify's icon and heart when they don't have one
    private func showSpotifySong(_ match: LibraryMatch?) {
        let previousStars = ratingControl.stars
        let isNewMatch = match?.identity != libraryMatch?.identity
        let isSameCopy = match != nil && match?.song.persistentID == libraryMatch?.song.persistentID
        libraryMatch = match
        guard let match = match else {
            ratingControl.update(mode: .spotify)
            guard displayedStopped || displayedMode != .spotify else {
                // Same mode, perhaps a new song: its heart may differ
                updateFavoriteHeartView()
                updateAccessibility()
                return
            }
            updateMenuBar(animate: true, previousStars: previousStars)
            return
        }
        ratingControl.update(mode: .rating)
        // A new match brings what was read with it. After that the copy is read again each
        // time rather than kept, so a rating changed in Music shows at the next update. That
        // read is on the main thread, so under the short timeout: at the default, a Music
        // that hangs would hold the menu bar for two minutes.
        let read = match.currentShown()
        // A read Music didn't answer says nothing, where taking it would show a rated copy as
        // unrated and a rating shortcut pressed then would count up from none (the second
        // review, 2026-10-29): a rating or heart just chosen stays, as it would for any
        // answer, and otherwise the copy's stars stay as they are, or, for a copy not on
        // show, what was last read of it comes back. None of those is Music's answer, so
        // none of them ends a hold: taking the stars on show for one put the old stars back
        // at the next read (the third review). Stars or a heart Music has refused since they
        // were shown don't stay either.
        let lastRead = LibraryMatch.Shown(song: match.song)
        show(rating: read.map { $0.rating ?? 0 }, favorite: read?.isFavorited, for: match.song.persistentID,
             isSameSong: isSameCopy, otherwise: (lastRead.rating ?? 0, lastRead.isFavorited))
        updateMenuBar(animate: true, previousStars: previousStars, animateRatingChange: isNewMatch)
    }

    /// Whether the Spotify song on show is liked: nil when not signed in or not known yet
    private var spotifyIsLiked: Bool? {
        guard ratingControl.mode == .spotify, let uri = displayedSongIdentity else { return nil }
        return SpotifyAccount.shared.isLiked(uri)
    }

    /// A like was read or changed, or the sign-in came or went
    @objc func spotifyLikeDidChange(_ notification: Notification) {
        if let uri = notification.userInfo?[SpotifyPlayer.identityKey] as? String, uri != displayedSongIdentity { return }
        guard ratingControl.mode == .spotify else { return }
        updateFavoriteHeartView()
        updateAccessibility()
    }

    /// Apply a refreshed track through the same transition path whether it came from a
    /// song change, a library edit, or a rejected click on a deleted rating target.
    func applyTrackDisplay(_ playing: PlayingTrack?, isStopped: Bool, musicIsRunning: Bool) {
        // Music's own song, or nothing: no Spotify song's copy is on show any more
        libraryMatch = nil
        matchWait.cancel()
        let wasStopped = isStop
        let wasWaiting = playbackState.isWaitingForTrack
        let canShowTrack = playbackState.update(hasTrack: playing != nil,
                                               isStopped: isStopped,
                                               isRunning: musicIsRunning)
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

        // A read Music didn't answer comes back as 0 or false rather than an error, and taken
        // for Music's answer it ended a rating or heart just chosen, so the next read, still
        // the old value, put the old one back (the fourth review, 2026-10-29). It says
        // nothing: what is held stays, and otherwise the song's stars on show stay, unless
        // Music has refused them, or a new song's start from none, since nothing else is
        // known of them.
        var userRating: Int?
        let ratingAnswer = MenuBarRatingControl.ifAnswered { () -> Int? in
            userRating = ratedTrack?.userRating
            return userRating ?? 0
        }
        let favoriteAnswer = MenuBarRatingControl.ifAnswered { () -> Bool? in
            playing?.favoriteTrack.isFavorited ?? false
        }
        show(rating: ratingAnswer, favorite: favoriteAnswer, for: playing?.persistentID,
             isSameSong: !isNewSong, otherwise: (0, false))
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
            // A read Music didn't answer is 0, which would ring the reminder for a rated
            // song, so then the stars on show stand for it, and the reminder reads the
            // rating again before it rings: a new song's stars on show are none
            let known = ratingAnswer == nil ? ratingControl.rating : userRating
            let snapshot = ratedTrack.flatMap { MenuBarRatingControl.readPlayerSnapshot(track: $0, userRating: known, isPlaying: isPlaying, trackID: playing?.persistentID) }
            reminderController?.playerDidUpdate(snapshot, ratingIsKnown: ratingAnswer != nil)
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
                self.writeFavorite(true, heldFor: playing.persistentID) {
                    added.updateFavorited(true)
                }
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

    /// `withShortTimeout`, or nil when any Apple Event the read sent failed. Scripting Bridge
    /// answers a failed read with nil, 0 or false rather than an error, which for a rating
    /// reads as "unrated". Main thread only, where the station counts its failures.
    static func withShortTimeoutIfAnswered<T>(_ read: (iTunesApplication) -> T) -> T? {
        return ifAnswered { withShortTimeout(read) }
    }

    /// `read`'s value, or nil when it has none or an Apple Event from the main thread failed
    /// while it ran. Main thread only, where the station counts its failures.
    static func ifAnswered<T>(_ read: () -> T?) -> T? {
        return ifAnswered(failures: { iTunesRadioStation.shared.failedEvents }, read)
    }

    /// `read`'s value, or nil when it has none or `failures`, a count of failed Apple Events,
    /// moved while it ran
    static func ifAnswered<T>(failures: () -> Int, _ read: () -> T?) -> T? {
        let before = failures()
        guard let value = read(), failures() == before else { return nil }
        return value
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
        guard shortcutCanRate() else { return }
        let ratingChange: Int = UserDefaults.standard.allowHalfStar ? 10 : 20
        ratingControl.update(rating: ratingControl.rating + ratingChange)
        choose(rating: ratingControl.rating)
    }

    @objc func iTunesRadioRequestTrackRatingDown(_ notification: Notification) {
        isPlaying = iTunesPlayer.shared.isPlaying
        defer { updateMenuBar() }
        guard playbackState.canInteract else {
            return
        }

        guard shortcutCanRate() else { return }
        let ratingChange: Int = UserDefaults.standard.allowHalfStar ? 10 : 20
        ratingControl.update(rating: ratingControl.rating - ratingChange)
        choose(rating: ratingControl.rating)
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

      guard shortcutCanRate() else { return }
      ratingControl.update(rating: stars * 20)
      choose(rating: ratingControl.rating)
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
