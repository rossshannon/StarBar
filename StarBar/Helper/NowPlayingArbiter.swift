//
//  NowPlayingArbiter.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-10-21.
//

import Cocoa
import os

/// The players StarBar follows
enum PlayerKind: String {
    case music
    case spotify

    /// Whether the strip may poll this player's position to notice a song restarting.
    /// Only Music: a Spotify poll was not agreed, and may not be needed if Spotify sends
    /// its own notification when a song goes back to the start (to be measured).
    var watchesRestarts: Bool {
        return self == .music
    }
}

extension Notification.Name {
    /// Posted on the main thread after Music or Spotify sends an update, once the active
    /// player has been chosen. `userInfo[NowPlayingArbiter.sourceKey]` is the raw value of
    /// the `PlayerKind` that sent it. Posted with `object: nil`, like `.iTunesPlayerDidUpdated`.
    static let nowPlayingDidUpdate = Notification.Name("StarBarNowPlayingDidUpdate")
}

/// Decides which player the strip and the menu bar follow when Music and Spotify are both
/// open.
///
/// A player that is playing beats one that isn't. Between two that are both playing, the one
/// that most recently started playing wins. With neither playing, the active one stays as
/// long as it is running, so a pause or the bare Stopped both players send between songs
/// never hands over. Only when it quits does the other one take over.
///
/// "Most recent new song wins" was the first rule, and left the user stranded: pause Spotify,
/// press play on a song already loaded in Music, and Music posts no new song, so the menu bar
/// would have kept Spotify's heart while Music played.
///
/// Main thread only.
final class NowPlayingArbiter {

    static let sourceKey = "source"

    /// What the arbiter knows about one player
    struct SourceState: Equatable {
        var isRunning: Bool
        var isPlaying: Bool
        /// When it last started playing: from paused or stopped, or a new song
        var startedPlayingAt: Date?
    }

    /// The one arbiter, started by `AppDelegate`
    static let shared = NowPlayingArbiter()

    /// The player the strip and the menu bar follow, or nil when neither is running
    private(set) var active: PlayerKind?
    private var states: [PlayerKind: SourceState] = [:]
    /// The song each player was last seen playing, to notice a new one starting while it plays
    private var playingIdentity: [PlayerKind: String] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// The rule on its own, for the tests
    static func choose(current: PlayerKind?, states: [PlayerKind: SourceState]) -> PlayerKind? {
        // Music first when nothing else separates them, which is what StarBar always followed
        let order: [PlayerKind] = [.music, .spotify]
        let playing = order.filter { states[$0]?.isRunning == true && states[$0]?.isPlaying == true }
        if playing.count == 1 {
            return playing[0]
        }
        if playing.count > 1 {
            let latest = playing.map { states[$0]?.startedPlayingAt ?? .distantPast }.max() ?? .distantPast
            let newest = playing.filter { (states[$0]?.startedPlayingAt ?? .distantPast) == latest }
            if let current = current, newest.contains(current) {
                return current
            }
            return newest.first
        }
        if let current = current, states[current]?.isRunning == true {
            return current
        }
        return order.first { states[$0]?.isRunning == true }
    }

    /// A player sent an update.
    ///
    /// - Parameters:
    ///   - identity: the song it is playing, in that player's own terms, or nil when it
    ///     can't say; only compared with its own earlier values
    /// - Returns: true when the active player changed
    @discardableResult
    func update(_ kind: PlayerKind, isRunning: Bool, isPlaying: Bool, identity: String?) -> Bool {
        var state = states[kind] ?? SourceState(isRunning: false, isPlaying: false, startedPlayingAt: nil)
        let playing = isRunning && isPlaying
        if playing && (!state.isPlaying || identity != playingIdentity[kind]) {
            state.startedPlayingAt = now()
        }
        state.isRunning = isRunning
        state.isPlaying = playing
        playingIdentity[kind] = playing ? identity : nil
        states[kind] = state

        let chosen = NowPlayingArbiter.choose(current: active, states: states)
        guard chosen != active else { return false }
        os_log("%{public}s[%{public}ld], %{public}s: now following %{public}s, was %{public}s", ((#file as NSString).lastPathComponent), #line, #function, chosen?.rawValue ?? "nothing", active?.rawValue ?? "nothing")
        active = chosen
        return true
    }

}

// MARK: - Wiring

extension NowPlayingArbiter {

    /// Listen to both players and pass each update on as `.nowPlayingDidUpdate`
    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(NowPlayingArbiter.musicDidUpdate(_:)), name: .iTunesPlayerDidUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(NowPlayingArbiter.spotifyDidUpdate(_:)), name: .spotifyPlayerDidUpdate, object: nil)
    }

    @objc private func musicDidUpdate(_ notification: Notification) {
        let station = iTunesRadioStation.shared
        let isRunning = station.iTunes != nil
        // The notification's state when there is one; before Music's first notification (the
        // launch gap) the player record decides, as it does for the menu bar
        let isPlaying: Bool
        if let playInfo = station.latestPlayInfo {
            isPlaying = playInfo.playerState == .playing
        } else {
            isPlaying = isRunning && iTunesPlayer.shared.playing != nil && iTunesPlayer.shared.isPlaying
        }
        update(.music, isRunning: isRunning, isPlaying: isPlaying, identity: station.latestPlayInfo?.songIdentity)
        post(from: .music)
    }

    @objc private func spotifyDidUpdate(_ notification: Notification) {
        let spotify = SpotifyPlayer.shared
        update(.spotify, isRunning: spotify.isRunning, isPlaying: spotify.latest?.state == .playing, identity: spotify.latest?.trackID)
        post(from: .spotify)
    }

    private func post(from source: PlayerKind) {
        let post = {
            NotificationCenter.default.post(name: .nowPlayingDidUpdate, object: nil, userInfo: [NowPlayingArbiter.sourceKey: source.rawValue])
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    /// Which player sent a `.nowPlayingDidUpdate`
    static func source(of notification: Notification) -> PlayerKind? {
        return (notification.userInfo?[NowPlayingArbiter.sourceKey] as? String).flatMap(PlayerKind.init(rawValue:))
    }

}
