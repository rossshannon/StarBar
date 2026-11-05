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

    /// Which announcements are offered to `LastMusicSongStore`: each song once while it plays
    private var lastSongOffers = LastMusicSongOffers()
    
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

    /// Music announced `playInfo`, and the record is the new one: remember a song it is
    /// playing from the library, for the popover's play button to start when Music has nothing
    /// loaded (`LastMusicSong`).
    ///
    /// Costs nothing for a song in the library, whose persistent ID the menu bar has already
    /// read from this record. For an Apple Music catalog track it is the user's copy that is
    /// kept, which takes one read of the copy's persistent ID under the short timeout, once per
    /// song unless Music doesn't answer it (`LastMusicSongOffers`).
    func rememberPlayedSong(_ playInfo: PlayInfo, in store: LastMusicSongStore = .shared) {
        guard playInfo.playerState == .playing, let identity = playInfo.songIdentity,
              lastSongOffers.shouldOffer(identity, storeHolds: store.song),
              rememberPlaying(name: playInfo.name, artist: playInfo.artist, in: store) else { return }
        lastSongOffers.kept(identity, storeHolds: store.song)
    }

    /// Remember the song Music was playing when StarBar started, which Music never announces:
    /// without it, a song played from before the launch until the user stopped it was never
    /// kept, and Play then offered an older one (found in review, 2026-11-05).
    ///
    /// `isPlaying` is asked only when Music has a song, so a Music with nothing loaded costs
    /// nothing beyond the launch's own read of the current track. `AppDelegate` calls it under
    /// the short timeout once the status item is up, since it runs on the main thread and
    /// Music can be slow to answer just after StarBar starts (found in review, 2026-11-05).
    func rememberSongPlayingAtLaunch(isPlaying: () -> Bool, in store: LastMusicSongStore = .shared) {
        guard let playing = _playing, isPlaying() else { return }
        rememberPlaying(name: playing.name, artist: playing.artist, in: store)
    }

    /// Keep the song on the record as the last one played, if it is in the library or the user
    /// has a copy of it. False when nothing was kept: no copy, or Music didn't answer for it.
    @discardableResult
    private func rememberPlaying(name: String?, artist: String?, in store: LastMusicSongStore) -> Bool {
        guard let playing = _playing else { return false }
        let libraryID: String?
        if playing.isCatalogStream {
            // Already found by the menu bar, which reads it for the stars
            let copy = playing.ratingTrack
            libraryID = copy.flatMap { copy in
                MenuBarRatingControl.withShortTimeoutIfAnswered { _ in copy.persistentID }.flatMap { $0 }
            }
        } else {
            libraryID = playing.persistentID
        }
        guard let song = LastMusicSong.remembering(isPlaying: true, libraryPersistentID: libraryID,
                                                   name: name, artist: artist) else { return false }
        store.remember(song)
        return true
    }

    /// The record read at launch is the song playing then, which Music never announces, so
    /// that the first song after it has a song before it to be checked against
    func musicWasPlayingAtLaunch() {
        recentSongs.playingAtLaunch(_playing)
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

