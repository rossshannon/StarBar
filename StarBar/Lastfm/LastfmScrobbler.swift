//
//  LastfmScrobbler.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Cocoa
import Network
import os

extension Notification.Name {
    /// How much is waiting to be sent to Last.fm changed, or scrobbling was paused or
    /// resumed. For Preferences. Main thread.
    static let lastfmScrobblerDidChange = Notification.Name("StarBarLastfmScrobblerDidChange")
    /// Posted by whatever notices that the song Music is playing went back to its start
    /// (the strip's restart watch), which Music itself never announces. Main thread.
    static let musicSongDidRestart = Notification.Name("StarBarMusicSongDidRestart")
}

/// Sends what is played to Last.fm.
///
/// It follows both players at once, not the one the menu bar follows (`NowPlayingArbiter`):
/// a song that plays for long enough counts wherever it played. Each player has a
/// `PlayTracker`, which says when a play counts; this class passes it what the player said,
/// runs its timer, and does what it answers:
/// - `.nowPlaying` is sent at once and never kept or retried.
/// - `.scrobble` goes into the user's `ScrobbleQueue`, on disk, and the queue is sent.
///   A song whose heart is already set is loved as it scrobbles, when the setting is on
///   (`Settings.lovesFavorites`), once per song each launch.
/// - `.checkPosition` reads Music once (`Environment.readPosition`) and passes the answer
///   back. This is the only read of a player's position the scrobbler makes, at most a few
///   per play; it never polls. The read waits while something is moving on screen
///   (`Environment.isMoving`), looked at every `motionCheckInterval` for at most
///   `motionWaitLimit`, as the station's own re-reads do.
///
/// **Sending.** One request at a time: scrobbles first, oldest first, in batches of
/// `LastfmAPI.maxBatch`, then hearts, oldest first. Nothing leaves the queue until Last.fm
/// has answered for it. What a failure does:
/// - `.network`, `.temporary`: wait and try again, after `retryDelays` in turn (the last one
///   repeats). The next scrobble, a wake from sleep, the network coming back, a new sign-in
///   and a launch each try at once. A success starts the delays from the first again.
/// - `.sessionInvalid`: `account.sessionWasRejected()`. The queue stays on disk for when the
///   same user connects again.
/// - `.credentialsRejected`: nothing more is sent until the app is opened again or the
///   account changes. The queue stays.
/// - `.refused`, `.tokenNotAuthorized`: Last.fm will never take it, so it is dropped, with
///   an error in the log, and sending carries on.
/// Every failure also goes to `account.note(_:)` and every success to `account.noteSuccess()`,
/// for Preferences. Sending needs a sender but not `isActive`: while paused, what is waiting
/// is still sent.
///
/// **When it runs.** It tracks and sends only while a user is signed in, or in a dry run,
/// and not while paused. Becoming inactive forgets the plays being tracked; becoming active
/// reads both players (`Environment.observe`) so a song already playing is picked up from
/// that moment. At launch that first read waits `adoptDelay`, because before Music's first
/// notification it costs a few Apple Events on the main thread, and the stars are rolling in
/// just then. The initialiser loads the queue but reads no player and sends nothing, so that
/// merely touching `shared` costs nothing; `start()` does both. Spotify is tracked only when
/// `Settings.scrobblesSpotify` is on. While paused nothing is tracked and no heart is kept,
/// but what was already waiting is still sent.
///
/// **A dry run** (`Settings.isDryRun`, the hidden `lastfmDryRun` default) needs no sign-in
/// and no key: everything goes to `DryRunLastfmSender`, which logs what would have been sent
/// and answers as Last.fm would, under the user name `dryRunUser`.
///
/// Main thread only. Never starts under tests or UI tests; `LastfmScrobblerTests` builds its
/// own with a fake `Environment`.
final class LastfmScrobbler {

    struct Settings: Equatable {
        /// "Scrobble songs played in Spotify". Off by default: Last.fm's own Spotify link
        /// already scrobbles Spotify on its servers, and both together would double them.
        var scrobblesSpotify: Bool
        /// "Love songs on Last.fm when I favourite them"
        var lovesFavorites: Bool
        var isDryRun: Bool
        /// "Pause Scrobbling", kept between launches
        var isPaused: Bool
    }

    /// Everything the scrobbler reads from the rest of the app, so tests can stand in for it
    struct Environment {
        var account: LastfmAccountProviding
        var queueStore: ScrobbleQueueStore
        var clock: RatingReminderClock
        /// `ProcessInfo.systemUptime`: seconds that don't count while the Mac sleeps
        var uptime: () -> TimeInterval
        var settings: () -> Settings
        /// What a player is doing now (`LastfmSources.music()` and `.spotify()`)
        var observe: (PlayerKind) -> PlayerReport
        /// One read of Music's position, state and song, for `.checkPosition`
        var readPosition: (_ identity: String) -> PlayTracker.PositionReading
        /// True while the strip slides or the menu bar draws a transition
        /// (`iTunesRadioStation.shared.somethingIsMoving`): a read of Music on the main
        /// thread then would cost the motion a frame or two
        var isMoving: () -> Bool
        /// Whether a song's heart is set (`LastfmSources.isFavorited`)
        var isFavorited: (PlayerKind, _ identity: String) -> Bool?

        /// The app's own: `LastfmAccount.shared`, `FileScrobbleQueueStore`, `RunLoopClock`,
        /// `UserDefaults.standard` and `LastfmSources`
        static var live: Environment {
            return Environment(
                account: LastfmAccount.shared,
                queueStore: FileScrobbleQueueStore(),
                clock: RunLoopClock(),
                uptime: { ProcessInfo.processInfo.systemUptime },
                settings: {
                    let defaults = UserDefaults.standard
                    // No dry run in a test run: its host shares the app's defaults, so one
                    // left on would have the tests' hearts kept in the real dry-run queue
                    return Settings(scrobblesSpotify: defaults.lastfmScrobbleSpotify,
                                    lovesFavorites: defaults.lastfmLoveSync,
                                    isDryRun: defaults.lastfmDryRun && !LastfmScrobbler.isUnderTest,
                                    isPaused: defaults.lastfmPaused)
                },
                observe: { kind in
                    switch kind {
                    case .music:
                        return LastfmSources.music()
                    case .spotify:
                        return LastfmSources.spotify()
                    }
                },
                readPosition: { identity in
                    return LastfmSources.musicPosition(matching: identity)
                },
                isMoving: {
                    return iTunesRadioStation.shared.somethingIsMoving()
                },
                isFavorited: { kind, identity in
                    return LastfmSources.isFavorited(kind, identity: identity)
                })
        }
    }

    static let shared = LastfmScrobbler(environment: .live)

    /// The user name a dry run's queue is kept under
    static let dryRunUser = "dry-run"
    /// How long to wait before trying again after Last.fm couldn't be reached: each in turn,
    /// the last one from then on
    static let retryDelays: [TimeInterval] = [60, 5 * 60, 15 * 60, 60 * 60]
    /// How many songs are remembered as loved this launch, so a favourite played again isn't
    /// loved again
    static let lovedCacheSize = 256
    /// How long after `start()` the players are first read
    static let adoptDelay: TimeInterval = 3
    static let motionCheckInterval: TimeInterval = 0.1
    static let motionWaitLimit: TimeInterval = 2
    /// A tracker deadline this close is taken as passed, so a timer that fires a hair early
    /// (or a deadline that doesn't survive the trip from uptime to a delay and back exactly)
    /// doesn't re-arm itself for no time at all, over and over
    private static let deadlineSlack: TimeInterval = 0.001

    private static let playerKinds: [PlayerKind] = [.music, .spotify]
    /// The same test as `LastfmAccount`'s: a test run, or UI tests, must never scrobble
    private static let isUnderTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || MenuBarRatingControl.isUITesting

    private let environment: Environment

    /// The current user's queue, or nil when nobody is signed in and there is no dry run
    private var queue: ScrobbleQueue?
    private var trackers: [PlayerKind: PlayTracker] = [:]
    /// Players that have had a tracker made since `queue` was loaded: only the first is
    /// given the queue's `lastScrobbled`
    private var trackersMadeForQueue: Set<PlayerKind> = []
    private var trackerTimer: RatingReminderTimer?

    /// A `.checkPosition` waiting for the screen to be still
    private struct PositionWait {
        var kind: PlayerKind
        var identity: String
        var since: TimeInterval
    }
    private var positionWait: PositionWait?
    private var positionTimer: RatingReminderTimer?

    private var isSending = false
    private var retryTimer: RatingReminderTimer?
    private var retryStep = 0
    /// Last.fm refused the app's key or signature: nothing is sent until the user changes
    private var sendingBlocked = false

    /// Songs loved this launch, as "artist\ntitle" lowercased, oldest first
    private var lovedOrder: [String] = []
    private var lovedKeys: Set<String> = []

    private lazy var dryRunSender = DryRunLastfmSender()

    /// What `refresh()` saw last time, so it can tell what changed
    private var lastSettings: Settings?
    private var wasActive = false
    private var hadSender = false
    /// What Preferences was last told
    private var postedWaitingCount = 0
    private var postedActive = false

    /// True from `start()` until its first read of the players, `adoptDelay` later
    private var awaitingAdopt = false
    private var adoptTimer: RatingReminderTimer?
    private var hasStarted = false
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    /// Nil until the path monitor's first answer
    private var networkSatisfied: Bool?

    init(environment: Environment) {
        self.environment = environment
        refresh(initial: true)
    }

    /// Start following the players, the account, the settings, wake from sleep and the
    /// network coming back, and send what is waiting. Observes `.iTunesPlayerDidUpdated`,
    /// `.spotifyPlayerDidUpdate`, `.lastfmAccountDidChange`, `.musicSongDidRestart`,
    /// `UserDefaults.didChangeNotification` and `NSWorkspace.didWakeNotification`. Never
    /// under tests or UI tests.
    func start() {
        guard !LastfmScrobbler.isUnderTest, !hasStarted else { return }
        hasStarted = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: nil) { [weak self] _ in
            self?.onMain { $0.playerDidUpdate(.music) }
        })
        observers.append(center.addObserver(forName: .spotifyPlayerDidUpdate, object: nil, queue: nil) { [weak self] _ in
            self?.onMain { $0.playerDidUpdate(.spotify) }
        })
        observers.append(center.addObserver(forName: .lastfmAccountDidChange, object: nil, queue: nil) { [weak self] notification in
            let disconnected = notification.userInfo?[LastfmAccount.disconnectedUserKey] as? String
            self?.onMain { $0.accountDidChange(disconnected: disconnected) }
        })
        observers.append(center.addObserver(forName: .musicSongDidRestart, object: nil, queue: nil) { [weak self] _ in
            self?.onMain { $0.songRestarted(.music) }
        })
        // Fires for every default anywhere in the app, often off the main thread
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.onMain { $0.settingsDidChange() }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemDidWake()
        })

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async {
                self?.networkPathChanged(satisfied: satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.rossshannon.starbar.lastfm-network", qos: .utility))
        pathMonitor = monitor

        // Music's first read waits for the menu bar's own launch work
        awaitingAdopt = true
        adoptTimer = environment.clock.schedule(after: LastfmScrobbler.adoptDelay, repeats: false) { [weak self] in
            self?.adoptPlayers()
        }

        os_log("%{public}s[%{public}ld], %{public}s: Last.fm scrobbler started, %{public}s", ((#file as NSString).lastPathComponent), #line, #function, isActive ? "active" : "inactive")
        refresh()
        flush()
    }

    /// A player said something, or quit: read it (`Environment.observe`) and pass it to its
    /// tracker. `.gone` forgets its play; `.nothingNew` only brings its time up to date.
    func playerDidUpdate(_ kind: PlayerKind) {
        guard !awaitingAdopt else { return }
        let settings = environment.settings()
        guard tracksPlays(settings) else { return }
        guard kind != .spotify || settings.scrobblesSpotify else { return }
        apply(environment.observe(kind), to: kind)
    }

    /// The song `kind` is playing went back to its start
    func songRestarted(_ kind: PlayerKind) {
        guard isActive, var tracker = trackers[kind] else { return }
        let effects = tracker.songRestarted(position: nil, uptime: environment.uptime(), now: environment.clock.now())
        trackers[kind] = tracker
        handle(effects, from: kind)
        rearm()
    }

    /// The sign-in changed. `disconnected` names a user who pressed Disconnect, whose queue
    /// is deleted; a session Last.fm rejected names nobody, and its queue is kept.
    func accountDidChange(disconnected user: String? = nil) {
        if let user = user {
            if let queue = queue, queue.user.caseInsensitiveCompare(user) == .orderedSame {
                queue.deleteAll()
            }
            environment.queueStore.delete(user: user)
            os_log("%{public}s[%{public}ld], %{public}s: Last.fm user %{public}s disconnected, their waiting scrobbles deleted", ((#file as NSString).lastPathComponent), #line, #function, user)
        }
        refresh()
    }

    /// A setting may have changed: read them again, and start or stop tracking to match
    func settingsDidChange() {
        refresh()
    }

    /// The user set or cleared a heart in StarBar, for the song with this title and artist.
    /// Kept and sent as a love or an unlove when active and `Settings.lovesFavorites` is on;
    /// otherwise nothing. A song with no title or no artist is ignored.
    func userDidSetHeart(_ isFavorited: Bool, title: String?, artist: String?) {
        let settings = environment.settings()
        guard tracksPlays(settings), settings.lovesFavorites, let queue = queue else { return }
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return }
        queue.add(ScrobbleQueue.LoveChange(title: title, artist: artist, loved: isFavorited))
        if isFavorited {
            rememberLoved(title: title, artist: artist)
        } else {
            forgetLoved(title: title, artist: artist)
        }
        os_log("%{public}s[%{public}ld], %{public}s: queued a Last.fm %{public}s: %{public}s, %{public}s, %{public}ld waiting", ((#file as NSString).lastPathComponent), #line, #function, isFavorited ? "love" : "unlove", artist, title, waitingCount)
        postIfChanged()
        flush()
    }

    /// True while plays are tracked: signed in or a dry run, and not paused
    var isActive: Bool {
        return tracksPlays(environment.settings())
    }

    /// How many scrobbles and hearts are waiting to be sent
    var waitingCount: Int {
        guard let queue = queue else { return 0 }
        return queue.contents.scrobbles.count + queue.contents.loves.count
    }

    /// Send what is waiting now, if anything is, nothing is being sent already and Last.fm
    /// hasn't refused the app's key. Forgets any wait for a retry.
    func flush() {
        retryTimer?.invalidate()
        retryTimer = nil
        retryStep = 0
        sendNext()
    }

    /// The app is quitting: make sure what is waiting is on disk. Sends nothing.
    func prepareToQuit() {
        environment.queueStore.synchronize()
    }

    // MARK: - Who, and whether

    private func user(_ settings: Settings) -> String? {
        if settings.isDryRun {
            return LastfmScrobbler.dryRunUser
        }
        return environment.account.username
    }

    private func sender(_ settings: Settings) -> LastfmSending? {
        if settings.isDryRun {
            return dryRunSender
        }
        return environment.account.sender
    }

    private func tracksPlays(_ settings: Settings) -> Bool {
        return user(settings) != nil && sender(settings) != nil && !settings.isPaused
    }

    /// Brings everything in line with the account and the settings. Cheap when nothing
    /// changed, which is most of the time: every default the app writes comes through here.
    /// The first, from `init`, loads the queue but reads no player and sends nothing.
    private func refresh(initial: Bool = false) {
        let settings = environment.settings()
        let user = self.user(settings)
        let hasSender = sender(settings) != nil
        let active = tracksPlays(settings)
        // Taken and replaced before acting, so that a refresh set off from inside this one
        // (an account that posts its change at once) compares against what is now true
        let previousSettings = lastSettings
        let previouslyActive = wasActive
        let previouslyHadSender = hadSender
        lastSettings = settings
        wasActive = active
        hadSender = hasSender

        let userChanged = user != queue?.user
        if userChanged {
            switchQueue(to: user)
        }

        if initial {
            postedWaitingCount = waitingCount
            postedActive = active
            return
        }

        if active != previouslyActive || (userChanged && active) {
            if active {
                if !awaitingAdopt {
                    readPlayers(settings)
                }
            } else {
                stopTracking()
            }
        } else if active, let previous = previousSettings, previous.scrobblesSpotify != settings.scrobblesSpotify {
            if settings.scrobblesSpotify {
                if !awaitingAdopt {
                    apply(environment.observe(.spotify), to: .spotify)
                }
            } else {
                trackers[.spotify]?.reset()
                rearm()
            }
        }

        if user != nil && (userChanged || (hasSender && !previouslyHadSender)) {
            flush()
        }
        postIfChanged()
    }

    /// A different user, or nobody: the old queue object goes (its file stays) and so does
    /// everything that belonged to it
    private func switchQueue(to user: String?) {
        let clock = environment.clock
        queue = user.map { ScrobbleQueue(user: $0, store: environment.queueStore, now: { clock.now() }) }
        trackers = [:]
        trackersMadeForQueue = []
        trackerTimer?.invalidate()
        trackerTimer = nil
        cancelPositionWait()
        retryTimer?.invalidate()
        retryTimer = nil
        retryStep = 0
        // A request still out for the old queue is ignored when it answers
        isSending = false
        sendingBlocked = false
        lovedOrder = []
        lovedKeys = []
        os_log("%{public}s[%{public}ld], %{public}s: Last.fm queue now for %{public}s, %{public}ld waiting", ((#file as NSString).lastPathComponent), #line, #function, user ?? "nobody", waitingCount)
    }

    private func stopTracking() {
        for kind in LastfmScrobbler.playerKinds {
            trackers[kind]?.reset()
        }
        trackerTimer?.invalidate()
        trackerTimer = nil
        cancelPositionWait()
    }

    private func adoptPlayers() {
        adoptTimer = nil
        awaitingAdopt = false
        let settings = environment.settings()
        guard tracksPlays(settings) else { return }
        readPlayers(settings)
    }

    private func readPlayers(_ settings: Settings) {
        apply(environment.observe(.music), to: .music)
        if settings.scrobblesSpotify {
            apply(environment.observe(.spotify), to: .spotify)
        }
    }

    private func postIfChanged() {
        let count = waitingCount
        let active = isActive
        guard count != postedWaitingCount || active != postedActive else { return }
        postedWaitingCount = count
        postedActive = active
        NotificationCenter.default.post(name: .lastfmScrobblerDidChange, object: nil)
    }

    private func onMain(_ work: @escaping (LastfmScrobbler) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                work(self)
            }
        }
    }

    private func systemDidWake() {
        if isActive {
            let uptime = environment.uptime()
            let now = environment.clock.now()
            for kind in LastfmScrobbler.playerKinds {
                guard var tracker = trackers[kind] else { continue }
                let effects = tracker.timerFired(uptime: uptime, now: now)
                trackers[kind] = tracker
                handle(effects, from: kind)
            }
            rearm()
        }
        flush()
    }

    private func networkPathChanged(satisfied: Bool) {
        let was = networkSatisfied
        networkSatisfied = satisfied
        if satisfied && was == false {
            os_log("%{public}s[%{public}ld], %{public}s: network back, sending what is waiting for Last.fm", ((#file as NSString).lastPathComponent), #line, #function)
            flush()
        }
    }

    // MARK: - Trackers

    private func tracker(for kind: PlayerKind) -> PlayTracker {
        if let tracker = trackers[kind] {
            return tracker
        }
        var earlier: PlayTracker.Earlier?
        if !trackersMadeForQueue.contains(kind) {
            earlier = queue?.lastScrobbled(player: kind.rawValue)
            trackersMadeForQueue.insert(kind)
        }
        return PlayTracker(checksPosition: kind == .music, earlier: earlier)
    }

    private func apply(_ report: PlayerReport, to kind: PlayerKind) {
        let uptime = environment.uptime()
        let now = environment.clock.now()
        var effects: [PlayTracker.Effect] = []
        switch report {
        case .gone:
            trackers[kind]?.reset()
        case .nothingNew:
            if var tracker = trackers[kind] {
                effects = tracker.timerFired(uptime: uptime, now: now)
                trackers[kind] = tracker
            }
        case .observed(let observation):
            var tracker = self.tracker(for: kind)
            effects = tracker.playerDidUpdate(state: observation.state, song: observation.song, position: observation.position, uptime: uptime, now: now)
            trackers[kind] = tracker
        }
        handle(effects, from: kind)
        rearm()
    }

    /// One timer for both trackers, for whichever deadline comes first
    private func rearm() {
        trackerTimer?.invalidate()
        trackerTimer = nil
        guard let earliest = trackers.values.compactMap({ $0.nextDeadline }).min() else { return }
        let delay = max(0, earliest - environment.uptime())
        trackerTimer = environment.clock.schedule(after: delay, repeats: false) { [weak self] in
            self?.trackerTimerFired()
        }
    }

    private func trackerTimerFired() {
        trackerTimer = nil
        let uptime = environment.uptime()
        let now = environment.clock.now()
        for kind in LastfmScrobbler.playerKinds {
            guard var tracker = trackers[kind], let deadline = tracker.nextDeadline,
                  deadline <= uptime + LastfmScrobbler.deadlineSlack else { continue }
            let effects = tracker.timerFired(uptime: uptime, now: now)
            trackers[kind] = tracker
            handle(effects, from: kind)
        }
        rearm()
    }

    private func handle(_ effects: [PlayTracker.Effect], from kind: PlayerKind) {
        for effect in effects {
            switch effect {
            case .nowPlaying(let song):
                sendNowPlaying(song.track)
            case .scrobble(let song, let startedAt):
                queueScrobble(song, startedAt: startedAt, from: kind)
            case .checkPosition(let song):
                checkPosition(of: song, in: kind)
            }
        }
    }

    private func queueScrobble(_ song: PlayTracker.Song, startedAt: Date, from kind: PlayerKind) {
        guard let queue = queue else { return }
        queue.add(Scrobble(track: song.track, startedAt: startedAt, source: kind.rawValue))
        queue.noteScrobbled(PlayTracker.Earlier(identity: song.identity, startedAt: startedAt, duration: song.track.duration), player: kind.rawValue)
        os_log("%{public}s[%{public}ld], %{public}s: queued a scrobble: %{public}s, %{public}s, from %{public}s, %{public}ld waiting", ((#file as NSString).lastPathComponent), #line, #function, song.track.artist, song.track.title, kind.rawValue, waitingCount)

        if environment.settings().lovesFavorites,
           !isLoved(title: song.track.title, artist: song.track.artist),
           environment.isFavorited(kind, song.identity) == true {
            queue.add(ScrobbleQueue.LoveChange(title: song.track.title, artist: song.track.artist, loved: true))
            rememberLoved(title: song.track.title, artist: song.track.artist)
            os_log("%{public}s[%{public}ld], %{public}s: queued a Last.fm love for a favourite as it scrobbled: %{public}s, %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song.track.artist, song.track.title)
        }
        postIfChanged()
        flush()
    }

    /// Reads the player for `.checkPosition`, at once or once the screen is still
    private func checkPosition(of song: PlayTracker.Song, in kind: PlayerKind) {
        guard positionWait == nil else { return }
        if environment.isMoving() {
            positionWait = PositionWait(kind: kind, identity: song.identity, since: environment.uptime())
            schedulePositionCheck()
        } else {
            readPosition(kind: kind, identity: song.identity)
        }
    }

    private func schedulePositionCheck() {
        positionTimer = environment.clock.schedule(after: LastfmScrobbler.motionCheckInterval, repeats: false) { [weak self] in
            self?.positionCheckFired()
        }
    }

    private func positionCheckFired() {
        positionTimer = nil
        guard let wait = positionWait else { return }
        if environment.isMoving() && environment.uptime() - wait.since < LastfmScrobbler.motionWaitLimit {
            schedulePositionCheck()
            return
        }
        positionWait = nil
        readPosition(kind: wait.kind, identity: wait.identity)
    }

    private func cancelPositionWait() {
        positionTimer?.invalidate()
        positionTimer = nil
        positionWait = nil
    }

    /// Nothing is read for a play that has gone meanwhile (another song, or tracking
    /// stopped): the tracker would ignore the answer, and the read costs Apple Events
    private func readPosition(kind: PlayerKind, identity: String) {
        guard isActive, var tracker = trackers[kind], tracker.song?.identity == identity else { return }
        let reading = environment.readPosition(identity)
        let effects = tracker.positionRead(reading, uptime: environment.uptime(), now: environment.clock.now())
        trackers[kind] = tracker
        handle(effects, from: kind)
        rearm()
    }

    // MARK: - Loved this launch

    private func lovedKey(title: String, artist: String) -> String {
        return artist.lowercased() + "\n" + title.lowercased()
    }

    private func isLoved(title: String, artist: String) -> Bool {
        return lovedKeys.contains(lovedKey(title: title, artist: artist))
    }

    private func rememberLoved(title: String, artist: String) {
        let key = lovedKey(title: title, artist: artist)
        guard lovedKeys.insert(key).inserted else { return }
        lovedOrder.append(key)
        while lovedOrder.count > LastfmScrobbler.lovedCacheSize {
            lovedKeys.remove(lovedOrder.removeFirst())
        }
    }

    private func forgetLoved(title: String, artist: String) {
        let key = lovedKey(title: title, artist: artist)
        guard lovedKeys.remove(key) != nil else { return }
        lovedOrder.removeAll { $0 == key }
    }

    // MARK: - Sending

    private func sendNowPlaying(_ track: Scrobble.Track) {
        guard !sendingBlocked, let sender = sender(environment.settings()) else { return }
        let sentFor = queue
        sender.updateNowPlaying(track) { [weak self] result in
            guard let self = self, sentFor === self.queue, case .failure(let failure) = result else { return }
            switch failure {
            case .sessionInvalid:
                os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm rejected the session setting now playing", ((#file as NSString).lastPathComponent), #line, #function)
                self.environment.account.sessionWasRejected()
            case .credentialsRejected:
                self.blockSending(failure)
            default:
                os_log("%{public}s[%{public}ld], %{public}s: Last.fm now playing not set: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: failure))
            }
        }
    }

    /// The next request, if one may go: scrobbles first, then hearts
    private func sendNext() {
        guard !isSending, !sendingBlocked, let queue = queue else { return }
        let settings = environment.settings()
        // A sender for someone other than the queue's user would send their plays as another's
        guard let sender = sender(settings), user(settings) == queue.user else { return }

        let batch = queue.nextBatch()
        if !batch.isEmpty {
            isSending = true
            sender.scrobble(batch) { [weak self] result in
                self?.batchAnswered(result, batch: batch, sentFor: queue)
            }
            return
        }
        if let change = queue.nextLove {
            isSending = true
            sender.setLoved(change.loved, title: change.title, artist: change.artist) { [weak self] result in
                self?.loveAnswered(result, change: change, sentFor: queue)
            }
        }
        // `nextBatch` drops plays too old for Last.fm, which changes the count
        postIfChanged()
    }

    private func batchAnswered(_ result: Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>, batch: [Scrobble], sentFor: ScrobbleQueue) {
        guard sentFor === queue else { return }
        isSending = false
        switch result {
        case .success(let summary):
            sentFor.finished(batch)
            retryStep = 0
            environment.account.noteSuccess()
            os_log("%{public}s[%{public}ld], %{public}s: Last.fm answered for %{public}ld scrobbles: %{public}ld accepted, %{public}ld ignored %{public}s, %{public}ld waiting", ((#file as NSString).lastPathComponent), #line, #function, batch.count, summary.accepted, summary.ignored, summary.ignoredCodes.map { String($0) }.joined(separator: ","), waitingCount)
            postIfChanged()
            sendNext()
        case .failure(let failure):
            failed(failure, what: "\(batch.count) scrobbles", count: batch.count) {
                sentFor.finished(batch)
            }
        }
    }

    private func loveAnswered(_ result: Result<Void, LastfmAPI.Failure>, change: ScrobbleQueue.LoveChange, sentFor: ScrobbleQueue) {
        guard sentFor === queue else { return }
        isSending = false
        switch result {
        case .success:
            sentFor.finished(change)
            retryStep = 0
            environment.account.noteSuccess()
            os_log("%{public}s[%{public}ld], %{public}s: Last.fm %{public}s: %{public}s, %{public}s, %{public}ld waiting", ((#file as NSString).lastPathComponent), #line, #function, change.loved ? "loved" : "unloved", change.artist, change.title, waitingCount)
            postIfChanged()
            sendNext()
        case .failure(let failure):
            failed(failure, what: change.loved ? "a love" : "an unlove", count: 1) {
                sentFor.finished(change)
            }
        }
    }

    /// What a failed scrobble or heart does next. `drop` removes what was sent.
    private func failed(_ failure: LastfmAPI.Failure, what: String, count: Int, drop: () -> Void) {
        switch failure {
        case .network, .temporary:
            environment.account.note(failure)
            scheduleRetry(after: failure)
        case .sessionInvalid:
            // The account posts its change, and `refresh()` then finds nobody signed in
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm rejected the session sending %{public}s; kept for when the user connects again", ((#file as NSString).lastPathComponent), #line, #function, what)
            environment.account.sessionWasRejected()
        case .credentialsRejected:
            blockSending(failure)
        case .refused(let code):
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm refused %{public}s with error %{public}ld; %{public}ld dropped", ((#file as NSString).lastPathComponent), #line, #function, what, code, count)
            drop()
            environment.account.note(failure)
            postIfChanged()
            sendNext()
        case .tokenNotAuthorized:
            os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm answered %{public}s with error 14 (token not authorised); %{public}ld dropped", ((#file as NSString).lastPathComponent), #line, #function, what, count)
            drop()
            environment.account.note(failure)
            postIfChanged()
            sendNext()
        }
    }

    private func scheduleRetry(after failure: LastfmAPI.Failure) {
        let delays = LastfmScrobbler.retryDelays
        let delay = delays[min(retryStep, delays.count - 1)]
        retryStep = min(retryStep + 1, delays.count - 1)
        retryTimer?.invalidate()
        retryTimer = environment.clock.schedule(after: delay, repeats: false) { [weak self] in
            guard let self = self else { return }
            self.retryTimer = nil
            self.sendNext()
        }
        os_log("%{public}s[%{public}ld], %{public}s: Last.fm couldn't be reached (%{public}s); trying again in %{public}ld s, %{public}ld waiting", ((#file as NSString).lastPathComponent), #line, #function, String(describing: failure), Int(delay), waitingCount)
    }

    private func blockSending(_ failure: LastfmAPI.Failure) {
        sendingBlocked = true
        retryTimer?.invalidate()
        retryTimer = nil
        environment.account.note(failure)
        os_log(.error, "%{public}s[%{public}ld], %{public}s: Last.fm refused the app's key (%{public}s); nothing more is sent until the account changes or the app opens again", ((#file as NSString).lastPathComponent), #line, #function, String(describing: failure))
    }

}

/// Stands in for Last.fm in a dry run: logs what would have been sent, one line each
/// ("Last.fm dry run: would scrobble ..."), and succeeds, on the next turn of the main run
/// loop as a real answer would arrive later.
final class DryRunLastfmSender: LastfmSending {

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    func updateNowPlaying(_ track: Scrobble.Track, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void) {
        os_log("%{public}s[%{public}ld], %{public}s: Last.fm dry run: would set now playing %{public}s, %{public}s", ((#file as NSString).lastPathComponent), #line, #function, track.artist, track.title)
        DispatchQueue.main.async {
            completion(.success(()))
        }
    }

    func scrobble(_ scrobbles: [Scrobble], completion: @escaping (Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>) -> Void) {
        for scrobble in scrobbles {
            let started = DryRunLastfmSender.timeFormatter.string(from: scrobble.startedAt)
            os_log("%{public}s[%{public}ld], %{public}s: Last.fm dry run: would scrobble %{public}s, %{public}s (started %{public}s)", ((#file as NSString).lastPathComponent), #line, #function, scrobble.track.artist, scrobble.track.title, started)
        }
        let summary = LastfmAPI.ScrobbleSummary(accepted: scrobbles.count, ignored: 0, ignoredCodes: [])
        DispatchQueue.main.async {
            completion(.success(summary))
        }
    }

    func setLoved(_ loved: Bool, title: String, artist: String, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void) {
        os_log("%{public}s[%{public}ld], %{public}s: Last.fm dry run: would %{public}s %{public}s, %{public}s", ((#file as NSString).lastPathComponent), #line, #function, loved ? "love" : "unlove", artist, title)
        DispatchQueue.main.async {
            completion(.success(()))
        }
    }

}
