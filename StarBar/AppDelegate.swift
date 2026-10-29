//
//  AppDelegate.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-6-28.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa
import os
import MASShortcut

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var menuBarRatingControl: MenuBarRatingControl?

    /// The Music Video strip and the controller that shows it
    private var trackAnnouncementPanel: TrackAnnouncementPanel?
    private(set) var trackAnnouncementController: TrackAnnouncementController?
    private var announceNewTracksObservation: NSKeyValueObservation?
    private var announcementStyleObservation: NSKeyValueObservation?
    /// The Spotify song whose Music copy the strip is waiting to hear about. A new song is
    /// held back until the answer comes, for at most `MenuBarRatingControl.libraryMatchWait`,
    /// as the menu bar is, rather than shown as a Spotify song and redrawn with stars a
    /// moment later.
    private var stripAwaitingMatch: String?
    private var stripMatchWaitTimer: Timer?
    
    @IBAction func openAboutWindow(_ sender: NSMenuItem) {
        WindowManager.shared.open(.about)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // setup shortcut validator
        if let validator = MASShortcutValidator.shared() {
            validator.allowAnyShortcutWithOptionModifier = true
        } else {
            os_log("%{public}s[%{public}ld], %{public}s: WARNING - Failed to initialize MASShortcutValidator", 
                   ((#file as NSString).lastPathComponent), #line, #function)
        }
        
        setupUserDefaults()
        // UI tests run without Music: don't connect to it (Music notifications, the current
        // track and the rating shortcuts) or ask for permission to control it
        if !MenuBarRatingControl.isUITesting {
            LaunchAtLogin.migrateLegacyHelperItem()
            _ = iTunesRadioStation.shared
            // Before anything that follows the player: the arbiter decides which player the
            // menu bar and the strip follow, and passes each update on to them
            NowPlayingArbiter.shared.start()
            setupAppleEvent()
        }

        // setup menu bar
        // Create synchronously: the control only refreshes on .nowPlayingDidUpdate, and the
        // async update in setupAppleEvent() must find it already observing. A delayed control
        // misses that update and shows the stopped icon until the next track change.
        menuBarRatingControl = MenuBarRatingControl()
        WindowManager.shared.menuBarRatingControl = menuBarRatingControl

        // After the Music connection, so the track already playing is recorded rather than
        // announced, and after the status item, so the seed's Apple Event reads don't delay
        // the menu bar. Still in this run loop turn, so no player update can arrive first,
        // and the menus are built lazily, so they find the controller when they open.
        setupTrackAnnouncement()

        // Show first-launch window if needed
        if UserDefaults.standard.bool(forKey: ApplicationKey.isFirstLaunch.rawValue) {
            UserDefaults.standard.set(false, forKey: ApplicationKey.isFirstLaunch.rawValue)
            WindowManager.shared.open(.preferences)
        }
        
        #if DEBUG
        // WindowManager.shared.open(.preferences)
        #endif
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        os_log("%{public}s[%{public}ld], %{public}s: Application will terminate", ((#file as NSString).lastPathComponent), #line, #function)
        // A rating chosen in the last two seconds may still be waiting for its window. Under
        // the short timeout: a hung Music must not hold the quit until macOS kills the app.
        // When Music isn't running there is nothing to write to.
        if !MenuBarRatingControl.isUITesting {
            let flushed: Void? = MenuBarRatingControl.withShortTimeout { _ in
                iTunesRadioStation.shared.flushHeldRatingWrite()
            }
            if flushed == nil {
                os_log("%{public}s[%{public}ld], %{public}s: Music isn't running, so no held rating could be flushed", ((#file as NSString).lastPathComponent), #line, #function)
            }
        }
    }

}

// MARK: - Track announcement

extension AppDelegate {

    /// Create the Music Video strip and its controller, seed it with the track already
    /// playing, and connect it to player updates, the setting, the shortcut and the menus.
    private func setupTrackAnnouncement() {
        let panel = TrackAnnouncementPanel()
        // Each read goes to whichever player the arbiter follows; Music when it follows
        // neither, which answers nil when Music isn't running either
        let controller = TrackAnnouncementController(
            readPlayer: {
                switch NowPlayingArbiter.shared.active {
                case .spotify: return AppDelegate.readSpotifySnapshot()
                case .music, nil: return AppDelegate.readAnnouncementSnapshot()
                }
            },
            loadLiveTrack: { identity, wantsArtwork in
                switch NowPlayingArbiter.shared.active {
                case .spotify: return AppDelegate.loadSpotifyLiveTrack(for: identity)
                case .music, nil: return AppDelegate.loadAnnouncementLiveTrack(for: identity, wantsArtwork: wantsArtwork)
                }
            },
            readCurrentIdentity: { announced in
                switch NowPlayingArbiter.shared.active {
                case .spotify: return SpotifyPlayer.shared.latest?.trackID
                case .music, nil: return AppDelegate.readCurrentTrackIdentity(matching: announced)
                }
            },
            readPosition: {
                guard !MenuBarRatingControl.isUITesting, NowPlayingArbiter.shared.active != .spotify else { return nil }
                return MenuBarRatingControl.withShortTimeout { iTunes in iTunes.playerPosition } ?? nil
            },
            isBusy: { [weak self] in self?.menuBarRatingControl?.isDragging ?? false },
            presenter: panel,
            isRunning: { kind in
                switch kind {
                case .music: return iTunesRadioStation.shared.iTunes != nil
                case .spotify: return SpotifyPlayer.shared.isRunning
                }
            },
            isEnabled: UserDefaults.standard.announceNewTracks
        )
        trackAnnouncementPanel = panel
        trackAnnouncementController = controller
        TrackAnnouncementController.shared = controller

        // Music sends no notification at launch, so record the current track now (one short
        // Apple Event read) rather than announce it on the next rating change
        controller.playerDidUpdate(seedOnly: true)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.playerDidUpdateForAnnouncement(_:)), name: .nowPlayingDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.spotifyArtworkDidLoad(_:)), name: .spotifyArtworkDidLoad, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.spotifyLikeDidChange(_:)), name: .spotifyLikeDidChange, object: SpotifyAccount.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.spotifyLikeDidChange(_:)), name: .spotifyAccountDidChange, object: SpotifyAccount.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.libraryMatchDidChange(_:)), name: .libraryMatchDidChange, object: LibraryMatchFinder.shared)
        // Spotify sends nothing at launch either. Its song is read in the background, and
        // only with permission already granted; it is recorded as seen when it arrives.
        if !MenuBarRatingControl.isUITesting {
            SpotifyPlayer.shared.didSeed = { [weak controller] info in
                controller?.recordSeen(info.snapshot)
            }
            SpotifyPlayer.shared.start()
            // Read lazily, the first time a Spotify song is looked for in the library
            MusicLibraryIndex.shared.start()
            // After the player, so a restored sign-in can ask about the song already playing
            SpotifyAccount.shared.start()
        }

        announceNewTracksObservation = UserDefaults.standard.observe(\.announceNewTracks, options: [.new]) { [weak controller] defaults, _ in
            controller?.setEnabled(defaults.announceNewTracks)
        }
        announcementStyleObservation = UserDefaults.standard.observe(\.announcementStyle, options: [.initial, .new]) { [weak panel] defaults, _ in
            panel?.style = TrackAnnouncementStyle(storedValue: defaults.announcementStyle)
        }
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: PreferencesViewController.ShortcutKey.showCurrentTrack.rawValue, toAction: { [weak controller] in
            controller?.showCurrentTrack()
        })
    }

    @objc private func playerDidUpdateForAnnouncement(_ notification: Notification) {
        // Music's notifications arrive on the main thread; the strip is AppKit, so be sure
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.playerDidUpdateForAnnouncement(notification) }
            return
        }
        // A Spotify song the user may have in Music waits for the answer. The wait is here
        // because the controller doesn't wait for anything.
        guard NowPlayingArbiter.shared.active == .spotify, let info = SpotifyPlayer.shared.latest,
              let identity = info.trackID, info.songQuery != nil else {
            cancelStripMatchWait()
            TrackAnnouncementController.shared?.playerDidUpdate()
            return
        }
        // The answer will bring the strip up to date with whatever Spotify says by then
        guard stripAwaitingMatch != identity else { return }
        cancelStripMatchWait()
        var answered = false
        LibraryMatchFinder.shared.match(for: info) { [weak self] _ in
            answered = true
            guard let self = self, self.stripAwaitingMatch == identity else { return }
            self.cancelStripMatchWait()
            TrackAnnouncementController.shared?.playerDidUpdate()
        }
        // Known already, or no copy by name, which needs no Apple Events
        guard !answered else {
            TrackAnnouncementController.shared?.playerDidUpdate()
            return
        }
        stripAwaitingMatch = identity
        let timer = Timer(timeInterval: MenuBarRatingControl.libraryMatchWaitNow, repeats: false) { [weak self] _ in
            guard let self = self, self.stripAwaitingMatch == identity else { return }
            os_log("%{public}s[%{public}ld], %{public}s: still looking for %{public}s in the library; announcing it meanwhile", ((#file as NSString).lastPathComponent), #line, #function, identity)
            self.cancelStripMatchWait()
            TrackAnnouncementController.shared?.playerDidUpdate()
        }
        RunLoop.main.add(timer, forMode: .common)
        stripMatchWaitTimer = timer
    }

    private func cancelStripMatchWait() {
        stripMatchWaitTimer?.invalidate()
        stripMatchWaitTimer = nil
        stripAwaitingMatch = nil
    }

    @objc private func spotifyArtworkDidLoad(_ notification: Notification) {
        guard let identity = notification.userInfo?[SpotifyPlayer.identityKey] as? String,
              let artwork = SpotifyPlayer.shared.artwork(for: identity) else { return }
        TrackAnnouncementController.shared?.attachArtwork(artwork, identity: identity)
    }

    @objc private func spotifyLikeDidChange(_ notification: Notification) {
        TrackAnnouncementController.shared?.spotifyLikeDidChange(AppDelegate.spotifyHeart(for:))
    }

    @objc private func libraryMatchDidChange(_ notification: Notification) {
        guard let identity = notification.userInfo?[SpotifyPlayer.identityKey] as? String else { return }
        TrackAnnouncementController.shared?.libraryMatchDidChange(identity: identity)
    }

    /// What the strip's Spotify heart shows for a song: nothing without a sign-in; signed in,
    /// filled when Spotify has said the song is liked and outlined otherwise, as the menu bar
    static func spotifyHeart(for identity: String) -> (showsHeart: Bool, isLiked: Bool) {
        let account = SpotifyAccount.shared
        guard account.isConnected, SpotifyLibrary.canLike(identity) else { return (false, false) }
        return (true, account.isLiked(identity) ?? false)
    }

    /// What Spotify is doing, from its last notification. No Apple Events. Nil when Spotify
    /// isn't running or has said nothing yet.
    static func readSpotifySnapshot() -> TrackAnnouncementController.PlayerSnapshot? {
        guard SpotifyPlayer.shared.isRunning else { return nil }
        return SpotifyPlayer.shared.latest?.snapshot
    }

    /// A Spotify song's artwork, if it has already arrived, and its like as far as StarBar
    /// knows it, or, for a song the user has in Music, that copy's rating and heart. No
    /// network, and no Apple Events for a song they don't have or a copy just found, whose
    /// rating and heart come with it; artwork that comes later reaches the strip through
    /// `attachArtwork`, and a copy found later through `libraryMatchDidChange`.
    static func loadSpotifyLiveTrack(for identity: String) -> TrackAnnouncementController.LiveTrackLoad {
        if let playing = SpotifyPlayer.shared.latest?.trackID, playing != identity {
            return .trackChanged
        }
        var live = TrackAnnouncementController.LiveTrack()
        live.artwork = SpotifyPlayer.shared.artwork(for: identity)
        // Without Music there is no copy to rate, as in the menu bar
        if iTunesRadioStation.shared.iTunes != nil, let match = LibraryMatchFinder.shared.knownMatch(for: identity) {
            // The same copy the menu bar shows and rates. A new match brings what was read
            // with it; after that it is read live, as a Music song's is, and when Music
            // doesn't answer, what the strip shows stands, or for a new strip what was last
            // read of the copy, rather than "unrated".
            live.canRate = true
            if let read = match.shown
                ?? MenuBarRatingControl.withShortTimeoutIfAnswered({ _ in LibraryMatch.Shown(reading: match.track) }) {
                live.rating = read.rating
                live.isFavorited = read.isFavorited
            } else {
                let last = LibraryMatch.Shown(song: match.song)
                live.lastKnownRating = last.rating
                live.lastKnownFavorite = last.isFavorited
            }
            live.showsSpotifyHeart = false
            return .loaded(live)
        }
        live.canRate = false
        // What StarBar already knows; a like that arrives later redraws through
        // spotifyLikeDidChange
        let heart = spotifyHeart(for: identity)
        live.showsSpotifyHeart = heart.showsHeart
        live.isFavorited = heart.isLiked
        return .loaded(live)
    }

    /// What the player is doing, from Music's last notification. Before the first
    /// notification (the launch gap) it reads the current track once instead. Nil when Music
    /// isn't running, and always nil in UI-test mode, which never touches Music.
    static func readAnnouncementSnapshot() -> TrackAnnouncementController.PlayerSnapshot? {
        guard !MenuBarRatingControl.isUITesting, iTunesRadioStation.shared.iTunes != nil else { return nil }
        if let playInfo = iTunesRadioStation.shared.latestPlayInfo {
            return TrackAnnouncementController.PlayerSnapshot(playInfo: playInfo)
        }
        return MenuBarRatingControl.withShortTimeout { iTunes -> TrackAnnouncementController.PlayerSnapshot? in
            guard let track = iTunesPlayer.shared.currentTrack else { return nil }
            do {
                return try ExceptionCatcher.catchException {
                    TrackAnnouncementController.PlayerSnapshot(track: track, playerState: iTunes.playerState)
                } as? TrackAnnouncementController.PlayerSnapshot
            } catch {
                os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
                return nil
            }
        } ?? nil
    }

    /// Which track Music has now, as an announcement identity, in the same shape as
    /// `announced` so the two can be compared.
    ///
    /// An announcement built from a notification that carried no persistent ID -- which is
    /// what Apple Music catalog tracks send -- is identified by name, artist and album. A live
    /// persistent ID could never equal that, and answering with one made a rating chosen in
    /// the menu bar look like it belonged to a different song, so the strip never showed it.
    ///
    /// Nil when Music isn't running, the read timed out, or the track can't be identified.
    static func readCurrentTrackIdentity(matching announced: String) -> String? {
        guard !MenuBarRatingControl.isUITesting else { return nil }
        return MenuBarRatingControl.withShortTimeout { _ -> String? in
            guard let track = iTunesPlayer.shared.currentTrack else { return nil }
            guard TrackAnnouncementController.PlayerSnapshot.isPersistentID(announced) else {
                return TrackAnnouncementController.PlayerSnapshot.identity(
                    name: track.name, artist: track.artist, album: track.album
                )
            }
            guard let id = track.persistentID, !id.isEmpty else { return nil }
            return id.uppercased()
        } ?? nil
    }

    /// The current track's rating, favourite flag and (when asked) artwork, if the current
    /// track is still the one being announced. The announcement's text comes from a queued
    /// notification while these come from the live track, so during rapid skips they can
    /// disagree; then a newer notification is on its way and this announcement is dropped.
    static func loadAnnouncementLiveTrack(for identity: String, wantsArtwork: Bool) -> TrackAnnouncementController.LiveTrackLoad {
        guard !MenuBarRatingControl.isUITesting else { return .loaded(.init()) }
        return MenuBarRatingControl.withShortTimeout { _ -> TrackAnnouncementController.LiveTrackLoad in
            guard let track = iTunesPlayer.shared.currentTrack else { return .loaded(.init()) }
            let liveID = track.persistentID
            let match = TrackAnnouncementController.PlayerSnapshot.liveTrackMatch(
                identity: identity,
                livePersistentID: liveID,
                liveName: TrackAnnouncementController.PlayerSnapshot.isPersistentID(identity) ? nil : track.name,
                liveArtist: TrackAnnouncementController.PlayerSnapshot.isPersistentID(identity) ? nil : track.artist,
                liveAlbum: TrackAnnouncementController.PlayerSnapshot.isPersistentID(identity) ? nil : track.album
            )
            switch match {
            case .same:
                var live = TrackAnnouncementController.LiveTrack()
                // A catalog track carries neither the rating nor the heart of its own: both
                // belong to the user's own copy, and both have to read the same track the
                // menu bar reads or the strip and the stars disagree on screen. The heart was
                // read from the playing track until 2026-09-18, on the belief that it was
                // written there; Music answered `favorited` false on a catalog track whose
                // library copy answered true.
                let playing = iTunesPlayer.shared.playing
                live.rating = playing?.ratingTrack?.userRating
                live.isFavorited = playing.map { $0.favoriteTrack.isFavorited } ?? track.isFavorited
                live.canRate = playing?.canRate ?? true
                if wantsArtwork {
                    // The user's own copy first: a catalog track's artwork read can come back
                    // empty and raise even when the same song sits in the library with its
                    // sleeve intact. See `PlayingTrack.artworkTrack` for why it still falls
                    // back to the playing track rather than refusing.
                    live.artwork = (playing?.artworkTrack ?? track).firstArtworkImage()
                }
                return .loaded(live)
            case .changed:
                os_log(.debug, "%{public}s[%{public}ld], %{public}s: live track %{public}s is not the announced %{public}s", ((#file as NSString).lastPathComponent), #line, #function, liveID ?? "nil", identity)
                return .trackChanged
            case .unknown:
                return .loaded(.init())
            }
        } ?? .loaded(.init())
    }

}

extension AppDelegate {

    // Request AppleEvent permission
    func setupAppleEvent() {
        DispatchQueue.global().async {
            // Check if Music/iTunes is running
            let isRunning = NSWorkspace.shared.runningApplications.contains { 
                $0.bundleIdentifier == OSVersionHelper.bundleIdentifier 
            }
            
            if !isRunning {
                os_log("%{public}s[%{public}ld], %{public}s: iTunes/Music is not currently running", ((#file as NSString).lastPathComponent), #line, #function)
                return
            }
            
            let target = NSAppleEventDescriptor(bundleIdentifier: OSVersionHelper.bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
            
            DispatchQueue.main.async {
                switch status {
                case noErr:
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: noErr", ((#file as NSString).lastPathComponent), #line, #function)
                    iTunesPlayer.shared.update()
                    
                case OSStatus(procNotFound):
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: iTunes/Music not running", ((#file as NSString).lastPathComponent), #line, #function)
                    
                case OSStatus(errAEEventNotPermitted):
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: not permitted", ((#file as NSString).lastPathComponent), #line, #function)
                    
                    // Explain once; after that, only log, so a denied permission doesn't nag at every login
                    let shownKey = "hasShownAutomationPermissionAlert"
                    guard !UserDefaults.standard.bool(forKey: shownKey) else { break }
                    UserDefaults.standard.set(true, forKey: shownKey)

                    let alert = NSAlert()
                    alert.messageText = "Permission Required"
                    alert.informativeText = "StarBar needs permission to control Music. Turn it on in System Settings → Privacy & Security → Automation."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open System Settings")
                    alert.addButton(withTitle: "Later")

                    // Menu bar apps have no Dock icon, so bring the alert to the front
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn,
                       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                    
                default:
                    os_log("%{public}s[%{public}ld], %{public}s: AppleEvent permission status: %s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: status))
                }
            }
        }   // end DispatchQueue.global().async
    }
    
    func setupUserDefaults() {
        // register shortcut
        do {
            let ratingDownShortcut = MASShortcut(keyCode: kVK_ANSI_Comma, modifierFlags: [.option, .control])
            let ratingUpShortcut = MASShortcut(keyCode: kVK_ANSI_Period, modifierFlags: [.option, .control])
            let showOrClosePopoverShortcut = MASShortcut(keyCode: kVK_ANSI_Slash, modifierFlags: [.option, .control])
            let rating5Shortcut = MASShortcut(keyCode: kVK_ANSI_5, modifierFlags: [.option, .control])
            let rating4Shortcut = MASShortcut(keyCode: kVK_ANSI_4, modifierFlags: [.option, .control])
            let rating3Shortcut = MASShortcut(keyCode: kVK_ANSI_3, modifierFlags: [.option, .control])
            let rating2Shortcut = MASShortcut(keyCode: kVK_ANSI_2, modifierFlags: [.option, .control])
            let rating1Shortcut = MASShortcut(keyCode: kVK_ANSI_1, modifierFlags: [.option, .control])
            let rating0Shortcut = MASShortcut(keyCode: kVK_ANSI_Grave, modifierFlags: [.option, .control])
            let showCurrentTrackShortcut = MASShortcut(keyCode: kVK_ANSI_N, modifierFlags: [.option, .control])

            let ratingDownShortcutData = try NSKeyedArchiver.archivedData(withRootObject: ratingDownShortcut as Any, requiringSecureCoding: false)
            let ratingUpShortcutData = try NSKeyedArchiver.archivedData(withRootObject: ratingUpShortcut as Any, requiringSecureCoding: false)
            let showOrClosePopoverShortcutData = try NSKeyedArchiver.archivedData(withRootObject: showOrClosePopoverShortcut as Any, requiringSecureCoding: false)
            let rating5ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating5Shortcut as Any, requiringSecureCoding: false)
            let rating4ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating4Shortcut as Any, requiringSecureCoding: false)
            let rating3ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating3Shortcut as Any, requiringSecureCoding: false)
            let rating2ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating2Shortcut as Any, requiringSecureCoding: false)
            let rating1ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating1Shortcut as Any, requiringSecureCoding: false)
            let rating0ShortcutData = try NSKeyedArchiver.archivedData(withRootObject: rating0Shortcut as Any, requiringSecureCoding: false)
            let showCurrentTrackShortcutData = try NSKeyedArchiver.archivedData(withRootObject: showCurrentTrackShortcut as Any, requiringSecureCoding: false)

            UserDefaults.standard.register(defaults: [
                PreferencesViewController.ShortcutKey.ratingDown.rawValue : ratingDownShortcutData,
                PreferencesViewController.ShortcutKey.ratingUp.rawValue : ratingUpShortcutData,
                PreferencesViewController.ShortcutKey.showOrClosePopover.rawValue : showOrClosePopoverShortcutData,
                PreferencesViewController.ShortcutKey.rating5.rawValue: rating5ShortcutData,
                PreferencesViewController.ShortcutKey.rating4.rawValue: rating4ShortcutData,
                PreferencesViewController.ShortcutKey.rating3.rawValue: rating3ShortcutData,
                PreferencesViewController.ShortcutKey.rating2.rawValue: rating2ShortcutData,
                PreferencesViewController.ShortcutKey.rating1.rawValue: rating1ShortcutData,
                PreferencesViewController.ShortcutKey.rating0.rawValue: rating0ShortcutData,
                PreferencesViewController.ShortcutKey.showCurrentTrack.rawValue: showCurrentTrackShortcutData,
            ])
        } catch {
            os_log("%{public}s[%{public}ld], %{public}s: Default shortcut set fail", ((#file as NSString).lastPathComponent), #line, #function)
        }
        
        // register application default behavior
        UserDefaults.standard.register(defaults: [
            ApplicationKey.isFirstLaunch.rawValue : true,
            ApplicationKey.allowHalfStar.rawValue : false,
            ApplicationKey.remindToRateUnrated.rawValue : true,
            ApplicationKey.announceNewTracks.rawValue : false,
            ApplicationKey.announcementStyle.rawValue : TrackAnnouncementStyle.default.rawValue
        ])
    }
}
