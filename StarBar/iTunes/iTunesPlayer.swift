//
//  iTunesPlayer.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-8-16.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation

extension Notification.Name {
    static let iTunesPlayerDidUpdated = Notification.Name("iTunesPlayerDidUpdated")
}

final class iTunesPlayer {
    
    // MARK: - Singleton
    public static let shared = iTunesPlayer()
    
    private var _currentTrack: iTunesTrack?

    var currentTrack: iTunesTrack? {
        get {
            return _currentTrack?.exists?() == true ? _currentTrack : nil
        }
    }

    private var _playing: PlayingTrack?

    /// The song playing and the track its rating belongs to, worked out once and shared.
    ///
    /// Read this rather than `currentTrack` for anything to do with ratings: a catalog track
    /// cannot hold one, and the user's own copy of the song may be somewhere else. See
    /// `PlayingTrack`.
    ///
    /// Nil once the track stops existing, on the same terms as `currentTrack`. The two have to
    /// agree: a record that outlived its track would have the menu bar offering stars for a
    /// song Music has already let go of.
    var playing: PlayingTrack? {
        return currentTrack == nil ? nil : _playing
    }
    
    var isPlaying: Bool {
        return iTunesRadioStation.shared.iTunes?.playerState == .playing
    }

    /// The songs Music announced last, for `previousSong(before:)`
    private var recentSongs = RecentSongs<PlayingTrack>()
    
    private init() {
        
    }
    
}

extension iTunesPlayer {
    
    func update(_ track: iTunesTrack? = iTunesRadioStation.shared.iTunes?.currentTrackCopy, broadcast: Bool = true) {
        // Use the passed-in track. The default argument already fetches a fresh copy.
        // Reading iTunesRadioStation.shared here deadlocks when called from its init.
        _currentTrack = track
        // Replaced rather than refreshed: a new record is what expires the old answers.
        // Nothing is read from Music here; `PlayingTrack` asks only when it is first asked,
        // which keeps this safe to call from `iTunesRadioStation`'s own init.
        _playing = track.map { PlayingTrack(track: $0) }
        
        if broadcast {
            NotificationCenter.default.post(name: .iTunesPlayerDidUpdated, object: nil)
        }
    }

    /// Music's notification named `identity` (`PlayInfo.songIdentity`) as the song playing.
    /// Called once the notification's own `update()` has run, so the record is the new one.
    func musicAnnounced(_ identity: String) {
        recentSongs.musicAnnounced(identity, playing: _playing)
    }

    /// Music quit, so the songs it played are gone with it, and a read of one would only
    /// open it again
    func forgetRecentSongs() {
        recentSongs.forget()
    }

    /// The record of the song Music played before `song`, a persistent ID, if StarBar heard of
    /// it. For catching Music answering for a catalog track with that song's cover: see
    /// `PlayingTrack.sleeve()`.
    func previousSong(before song: String) -> PlayingTrack? {
        return recentSongs.previous(before: song) { $0.persistentID }
    }

}

