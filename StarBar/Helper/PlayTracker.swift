//
//  PlayTracker.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation

/// Decides when a song one player is playing counts as played, for Last.fm.
///
/// Last.fm's rule: a song longer than 30 seconds is scrobbled once it has played for half its
/// length or for four minutes, whichever comes first, and the scrobble carries the time the
/// song started. "Played" is time spent playing, so a pause doesn't count and a seek neither
/// adds nor takes away.
///
/// Pure: a value type that is told what the player said and what time it is, and answers with
/// what to do (`Effect`). It reads no clock and sets no timer. Its owner (`LastfmScrobbler`)
/// keeps one tracker per player, passes on every update, and calls `timerFired` at
/// `nextDeadline`. Covered by `PlayTrackerTests`.
///
/// **Two clocks.** `now` is the wall clock, used only for the time a play started, which is
/// what Last.fm is sent. `uptime` (`ProcessInfo.systemUptime`) measures time played, because
/// it stops while the Mac sleeps and never jumps when the wall clock is set. An `uptime`
/// earlier than one already seen is taken as no time passing, so time played never goes
/// backwards and no stretch of playing is counted twice.
///
/// **A play** is one pass through one song. It begins when the player first says it is
/// playing a song the tracker isn't already tracking, with `played` at 0 and `startedAt` at
/// `now`, wherever in the song the player is: only time StarBar saw being played counts. It
/// is replaced when the player names another song, and it survives a pause and the bare
/// Stopped that Music sends between songs and, sometimes, a second into a streamed one.
///
/// **Every entry point first counts the time played since the last one** and emits whatever
/// fell due in it, in this order and for the play as it was before the call's own change, so
/// a late timer or a pause that arrives before the timer loses nothing:
/// - `.nowPlaying`, `rules.nowPlayingDelay` into each stretch of playing (so again after a
///   resume), which keeps a burst of skips from announcing every song skipped through
/// - `.scrobble`, once per play, when `played` reaches `threshold(for:rules:)`
/// - `.checkPosition`, for a tracker made with `checksPosition`, when the play has run
///   `rules.rolloverSlack` past the song's end (below)
/// Nothing is emitted for a song that isn't `isScrobblable` (it is still tracked, so that its
/// identity is known), no `.scrobble` or `.checkPosition` for one too short to count, and
/// nothing at all falls due while a play is paused. The one exception to "first" is
/// `positionRead`, which with no check waiting is ignored entirely.
///
/// **A song that starts again** is a new play, and neither player says when it happens:
/// Music posts nothing on Repeat One or Previous, and nor does Spotify. Three things catch it.
/// 1. A position that came with an update (Spotify's payload has one). Where the play should
///    be is `anchor.position + (played - anchor.played)`. A position more than
///    `rules.tolerance` behind that is a restart when it is within `rules.restartPosition` of
///    the start, or when the play should already be past the song's end and the position is
///    no further in than that overrun plus the tolerance; otherwise it is a seek back, which
///    only moves the anchor. A position ahead by more than the tolerance is a seek forward:
///    the anchor moves, `played` doesn't. A position within the tolerance moves the anchor
///    too, which removes drift.
/// 2. `.checkPosition`. When the song should have ended `rules.rolloverSlack` ago and no
///    other song has been announced, the owner reads the player once (`PositionReading`). A
///    different song there drops the play; a player that isn't playing pauses it; a position
///    behind where the play should be is a restart when it is within `rules.restartPosition`
///    of the start **or** no further in than the play has overrun the song's length plus the
///    tolerance, and otherwise a seek, which moves the anchor and sets the next check for when
///    the song should end from there, and no sooner than `rules.positionRetry` after this
///    one. No answer is asked again `rules.positionRetry` later. After `rules.positionTries`
///    reads in a row that settled nothing (no answer, or only a seek), the tracker stops
///    asking until the player's next update for the song, so a player stuck "playing" is
///    never polled. A reading that answers a position but not `isPlaying` or `isSameSong`
///    is trusted on the position.
/// 3. `songRestarted`, when something else noticed (the strip's restart watch).
/// A restart begins a new play at the position read: `startedAt` is `now` less the position,
/// `played` is the position, and it can scrobble again. A playing one emits `.nowPlaying` at
/// once, and `.scrobble` in the same call if the position already reaches the threshold; a
/// paused one emits nothing until it plays again.
///
/// Known limits, accepted: a restart part-way through a song is counted only if one of the
/// three catches it, so Music's Previous at 3:00 of a 4:00 song with the strip off is one
/// play, not two; and a Spotify song on repeat is one play unless Spotify posts when it loops
/// (not measured), since Spotify is never asked for its position.
struct PlayTracker {

    /// A song as one player names it
    struct Song: Equatable {
        /// Tells one song from another within this player: for Music the strip's identity
        /// (the persistent ID in hex, or `name|artist|album`), for Spotify the Track ID
        var identity: String
        var track: Scrobble.Track
        /// False for what is never sent: a podcast episode, an ad, a song with no title or
        /// no artist
        var isScrobblable: Bool
    }

    enum PlayerState: Equatable {
        case playing
        case paused
        /// An explicit stop, which may name no song
        case stopped
    }

    /// What the owner should do. Each carries the song it is about, because one call can
    /// answer for two: the play that just ended and the one that replaced it.
    enum Effect: Equatable {
        case nowPlaying(Song)
        case scrobble(Song, startedAt: Date)
        /// Read the player's position and state once, and whether it still has this song,
        /// and answer with `positionRead`
        case checkPosition(Song)
    }

    struct Rules: Equatable {
        /// A song this long or shorter is never scrobbled
        var minimumDuration: TimeInterval = 30
        /// The part of its length a song must play for
        var fraction: Double = 0.5
        /// However long the song, this much playing is enough. Also the whole rule for a
        /// song whose length the player didn't give.
        var longestWait: TimeInterval = 240
        var nowPlayingDelay: TimeInterval = 2
        /// How far past the song's end a play runs before the player is asked where it is
        var rolloverSlack: TimeInterval = 3
        /// How far a position may be from where the play should be before it is a seek
        var tolerance: TimeInterval = 5
        /// A position this near the start, reached by going backwards, is a restart
        var restartPosition: TimeInterval = 5
        /// The least time between two reads of the position for one play
        var positionRetry: TimeInterval = 30
        /// How many reads in a row may settle nothing before the tracker stops asking
        var positionTries: Int = 3

        static let lastfm = Rules()
    }

    /// One read of the player, in answer to `.checkPosition`. Nil is "didn't answer".
    struct PositionReading: Equatable {
        /// Seconds into the song
        var position: TimeInterval?
        var isPlaying: Bool?
        /// Whether the player still has the song being tracked
        var isSameSong: Bool?

        /// The player didn't answer at all
        static let unanswered = PositionReading(position: nil, isPlaying: nil, isSameSong: nil)
    }

    /// The last play scrobbled for this player before the app last quit, so that the same
    /// pass of the same song, still playing when StarBar opens again, isn't scrobbled twice
    struct Earlier: Equatable, Codable {
        var identity: String
        var startedAt: Date
        var duration: TimeInterval?
    }

    /// The play being tracked
    private struct Play {
        var song: Song
        var startedAt: Date
        /// Time played before the current stretch of playing
        var played: TimeInterval
        /// The `uptime` the current stretch of playing began, nil while paused
        var stretchStart: TimeInterval?
        var hasScrobbled: Bool
        /// The `uptime` at which `.nowPlaying` is due, nil once sent or while paused
        var nowPlayingDue: TimeInterval?
        /// A position in the song, and the played total it was known at, from which where
        /// the song should be now is worked out
        var anchorPosition: TimeInterval
        var anchorPlayed: TimeInterval
        /// A `.checkPosition` was emitted and its `positionRead` hasn't come
        var checkIsWaiting: Bool
        /// The `uptime` before which no check may be made, nil for no such limit
        var earliestCheck: TimeInterval?
        /// Reads in a row that settled nothing
        var unsettledReads: Int

        var isPlaying: Bool {
            return stretchStart != nil
        }

        func played(at uptime: TimeInterval) -> TimeInterval {
            guard let start = stretchStart else { return played }
            return played + max(0, uptime - start)
        }

        /// Where in the song the play should be at `uptime`
        func position(at uptime: TimeInterval) -> TimeInterval {
            return anchorPosition + (played(at: uptime) - anchorPlayed)
        }

        /// The `uptime` at which the time played reaches `total`, if it goes on playing.
        /// Nil while paused.
        func uptime(whenPlayedReaches total: TimeInterval) -> TimeInterval? {
            guard let start = stretchStart else { return nil }
            return start + (total - played)
        }
    }

    /// Absorbs rounding, so a timer fired at exactly `nextDeadline` always finds its effect
    /// due and the owner is never asked to fire again for the same deadline
    private static let rounding: TimeInterval = 1e-6

    let checksPosition: Bool
    let rules: Rules

    private var play: Play?
    /// Consulted by the first play only, then forgotten
    private var earlier: Earlier?
    /// The latest `uptime` seen, so time never runs backwards
    private var latestUptime: TimeInterval?

    /// - Parameters:
    ///   - checksPosition: whether to emit `.checkPosition`. True for Music, which answers
    ///     one read; false for Spotify, which is never asked.
    ///   - earlier: checked against the first play only, then forgotten. That play counts as
    ///     already scrobbled when it is the same song and begins before `earlier` could have
    ///     ended: `earlier.startedAt` plus its duration (`rules.longestWait` twice over when
    ///     it had none, or a duration of zero or less) plus `rules.rolloverSlack`.
    init(checksPosition: Bool, rules: Rules = .lastfm, earlier: Earlier? = nil) {
        self.checksPosition = checksPosition
        self.rules = rules
        self.earlier = earlier
    }

    /// The player said something. `song` is nil when it named none (Music's bare Stopped);
    /// `position` is where the player said it is, when it said (Spotify), else nil.
    ///
    /// - `.playing` with a song that isn't being tracked: a new play, playing.
    /// - `.playing` with the song being tracked: resumes it if it was paused; otherwise
    ///   nothing changes, since players repeat themselves and StarBar re-reads them. A newer
    ///   `track` for the same song is kept, since a player can fill in a duration later.
    /// - `.playing` with no song: the play pauses and is kept, since whatever is playing
    ///   isn't known to be it (a Spotify ad with no Track ID).
    /// - `.paused` or `.stopped` with the song being tracked, or with no song: the play
    ///   pauses and is kept.
    /// - `.paused` or `.stopped` with another song: the play is dropped. That song isn't
    ///   tracked until it plays (Music announces a song paused at 0.0 before it plays it).
    /// Any update for the song being tracked lets a tracker that had stopped asking for the
    /// position ask again, and a `position` for it is judged (restart, seek or drift) before
    /// the play pauses or resumes.
    mutating func playerDidUpdate(state: PlayerState, song: Song?, position: TimeInterval? = nil, uptime: TimeInterval, now: Date) -> [Effect] {
        let uptime = catchUp(to: uptime)
        var effects = collectDue(at: uptime)

        var isTracked = false
        if let song = song, var current = play, current.song.identity == song.identity {
            isTracked = true
            current.song = song
            current.unsettledReads = 0
            play = current
            if let position = position {
                judge(position: position, uptime: uptime, now: now)
            }
        }

        switch state {
        case .playing:
            if let song = song {
                if isTracked {
                    resume(at: uptime)
                } else {
                    begin(song, position: position, uptime: uptime, now: now)
                }
            } else {
                pause(at: uptime)
            }
        case .paused, .stopped:
            if song == nil || isTracked {
                pause(at: uptime)
            } else {
                play = nil
            }
        }

        effects += collectDue(at: uptime)
        return effects
    }

    /// The owner's timer for `nextDeadline` fired, or it wants time brought up to date
    mutating func timerFired(uptime: TimeInterval, now: Date) -> [Effect] {
        let uptime = catchUp(to: uptime)
        return collectDue(at: uptime)
    }

    /// The answer to `.checkPosition`. Ignored when no check is waiting on one: it changes
    /// nothing and emits nothing, not even what has fallen due, which the next timer collects.
    mutating func positionRead(_ reading: PositionReading, uptime: TimeInterval, now: Date) -> [Effect] {
        guard play?.checkIsWaiting == true else { return [] }
        let uptime = catchUp(to: uptime)
        var effects = collectDue(at: uptime)
        guard var current = play else { return effects }
        current.checkIsWaiting = false
        play = current

        if reading.isSameSong == false {
            play = nil
            return effects
        }
        if reading.isPlaying == false {
            pause(at: uptime)
            return effects
        }
        guard let position = reading.position else {
            noteUnsettledRead(at: uptime)
            return effects
        }

        let expected = current.position(at: uptime)
        if isRestart(position: position, expected: expected, duration: current.song.track.duration) {
            restart(at: position, uptime: uptime, now: now)
        } else {
            // A seek: the next check follows from the new anchor, and no sooner than the retry
            current.anchorPosition = position
            current.anchorPlayed = current.played(at: uptime)
            play = current
            noteUnsettledRead(at: uptime)
        }
        effects += collectDue(at: uptime)
        return effects
    }

    /// Something else saw the song being tracked go back to its start. `position` is where
    /// it is now, if known. Nothing happens when no play is being tracked, or when its song
    /// isn't scrobblable.
    mutating func songRestarted(position: TimeInterval? = nil, uptime: TimeInterval, now: Date) -> [Effect] {
        let uptime = catchUp(to: uptime)
        var effects = collectDue(at: uptime)
        guard let current = play, current.song.isScrobblable else { return effects }
        restart(at: position, uptime: uptime, now: now)
        effects += collectDue(at: uptime)
        return effects
    }

    /// Forget the play: the player quit, or scrobbling was paused or switched off. A song
    /// still playing afterwards is a new play at its next update. `earlier` is kept only if
    /// no play has consulted it yet.
    mutating func reset() {
        play = nil
    }

    /// The `uptime` at which `timerFired` is next wanted, or nil when nothing is due: while
    /// paused, for a song that isn't scrobblable, or once a play has scrobbled and has no
    /// check left to make. It can be in the past, when something fell due since the last
    /// call; the owner then fires at once.
    var nextDeadline: TimeInterval? {
        guard let current = play, current.song.isScrobblable, current.isPlaying else { return nil }
        let candidates = [current.nowPlayingDue, scrobbleTime(for: current), checkTime(for: current)]
        return candidates.compactMap { $0 }.min()
    }

    /// The song being tracked, playing or paused
    var song: Song? {
        return play?.song
    }

    /// When the play being tracked began
    var startedAt: Date? {
        return play?.startedAt
    }

    /// True once the play being tracked has emitted its `.scrobble`, or counted as `earlier`
    var hasScrobbled: Bool {
        return play?.hasScrobbled ?? false
    }

    /// How long a song of `duration` must play before it is scrobbled: half its length, or
    /// `rules.longestWait` if that is less, and `rules.longestWait` for a song with no length
    /// (nil, zero or negative). Nil for a song of `rules.minimumDuration` or less, which is
    /// never scrobbled.
    static func threshold(for duration: TimeInterval?, rules: Rules = .lastfm) -> TimeInterval? {
        guard let duration = duration, duration > 0 else { return rules.longestWait }
        guard duration > rules.minimumDuration else { return nil }
        return min(duration * rules.fraction, rules.longestWait)
    }

    // MARK: - Time

    /// `uptime`, or the latest one seen if it is earlier, which is then the latest
    private mutating func catchUp(to uptime: TimeInterval) -> TimeInterval {
        let time = max(uptime, latestUptime ?? uptime)
        latestUptime = time
        return time
    }

    /// Emits what fell due by `uptime` for the play as it is, and notes it emitted
    private mutating func collectDue(at uptime: TimeInterval) -> [Effect] {
        guard var current = play, current.song.isScrobblable, current.isPlaying else { return [] }
        var effects: [Effect] = []
        if let due = current.nowPlayingDue, uptime >= due - PlayTracker.rounding {
            effects.append(.nowPlaying(current.song))
            current.nowPlayingDue = nil
        }
        if let due = scrobbleTime(for: current), uptime >= due - PlayTracker.rounding {
            effects.append(.scrobble(current.song, startedAt: current.startedAt))
            current.hasScrobbled = true
        }
        if let due = checkTime(for: current), uptime >= due - PlayTracker.rounding {
            effects.append(.checkPosition(current.song))
            current.checkIsWaiting = true
        }
        play = current
        return effects
    }

    /// When the play reaches its threshold, if it is playing and has yet to scrobble
    private func scrobbleTime(for play: Play) -> TimeInterval? {
        guard !play.hasScrobbled,
              let threshold = PlayTracker.threshold(for: play.song.track.duration, rules: rules) else { return nil }
        return play.uptime(whenPlayedReaches: threshold)
    }

    /// When a check of the position falls due: once the play should be `rolloverSlack` past
    /// the song's end, and no earlier than `earliestCheck`. Nil when no check can be made.
    private func checkTime(for play: Play) -> TimeInterval? {
        guard checksPosition,
              !play.checkIsWaiting,
              play.unsettledReads < rules.positionTries,
              PlayTracker.threshold(for: play.song.track.duration, rules: rules) != nil,
              let duration = play.song.track.duration, duration > 0,
              let natural = play.uptime(whenPlayedReaches: play.anchorPlayed + (duration + rules.rolloverSlack - play.anchorPosition))
        else { return nil }
        return max(natural, play.earliestCheck ?? natural)
    }

    // MARK: - Changes

    private mutating func begin(_ song: Song, position: TimeInterval?, uptime: TimeInterval, now: Date) {
        var counted = false
        if let earlier = earlier {
            let length: TimeInterval
            if let duration = earlier.duration, duration > 0 {
                length = duration
            } else {
                length = 2 * rules.longestWait
            }
            counted = earlier.identity == song.identity
                && now < earlier.startedAt.addingTimeInterval(length + rules.rolloverSlack)
            self.earlier = nil
        }
        play = Play(
            song: song,
            startedAt: now,
            played: 0,
            stretchStart: uptime,
            hasScrobbled: counted,
            nowPlayingDue: uptime + rules.nowPlayingDelay,
            anchorPosition: position ?? 0,
            anchorPlayed: 0,
            checkIsWaiting: false,
            earliestCheck: nil,
            unsettledReads: 0
        )
    }

    private mutating func pause(at uptime: TimeInterval) {
        guard var current = play, let start = current.stretchStart else { return }
        current.played += max(0, uptime - start)
        current.stretchStart = nil
        current.nowPlayingDue = nil
        play = current
    }

    private mutating func resume(at uptime: TimeInterval) {
        guard var current = play, current.stretchStart == nil else { return }
        current.stretchStart = uptime
        current.nowPlayingDue = uptime + rules.nowPlayingDelay
        play = current
    }

    /// A position the player gave with an update for the song being tracked
    private mutating func judge(position: TimeInterval, uptime: TimeInterval, now: Date) {
        guard var current = play else { return }
        let expected = current.position(at: uptime)
        if position < expected - rules.tolerance,
           isRestart(position: position, expected: expected, duration: current.song.track.duration) {
            restart(at: position, uptime: uptime, now: now)
            return
        }
        // A seek either way, or drift within the tolerance: only where the song is moves
        current.anchorPosition = position
        current.anchorPlayed = current.played(at: uptime)
        play = current
    }

    /// Whether `position`, behind where the play should be, means the song began again:
    /// near the start, or no further in than the play has overrun the song's end
    private func isRestart(position: TimeInterval, expected: TimeInterval, duration: TimeInterval?) -> Bool {
        if position <= rules.restartPosition {
            return true
        }
        if let duration = duration, duration > 0, expected > duration,
           position <= (expected - duration) + rules.tolerance {
            return true
        }
        return false
    }

    /// A new play of the same song at `position`, playing or paused as the old one was. A
    /// playing one has `.nowPlaying` due at once, which the caller's `collectDue` emits.
    private mutating func restart(at position: TimeInterval?, uptime: TimeInterval, now: Date) {
        guard var current = play else { return }
        let position = max(0, position ?? 0)
        current.startedAt = now.addingTimeInterval(-position)
        current.played = position
        current.anchorPosition = position
        current.anchorPlayed = position
        current.hasScrobbled = false
        current.checkIsWaiting = false
        current.earliestCheck = nil
        current.unsettledReads = 0
        if current.isPlaying {
            current.stretchStart = uptime
            current.nowPlayingDue = uptime
        } else {
            current.nowPlayingDue = nil
        }
        play = current
    }

    /// A read that settled nothing: ask again no sooner than `positionRetry` from now, and
    /// not at all after `positionTries` of them in a row
    private mutating func noteUnsettledRead(at uptime: TimeInterval) {
        guard var current = play else { return }
        current.unsettledReads += 1
        current.earliestCheck = uptime + rules.positionRetry
        play = current
    }

}
