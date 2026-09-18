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

    /// The song playing and the track its rating belongs to, worked out once and shared.
    ///
    /// Read this rather than `currentTrack` for anything to do with ratings: a catalog track
    /// cannot hold one, and the user's own copy of the song may be somewhere else. See
    /// `PlayingTrack`.
    private(set) var playing: PlayingTrack?
    
    var isPlaying: Bool {
        return iTunesRadioStation.shared.iTunes?.playerState == .playing
    }
    
    let history = iTunesPlayerHistory()
    
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
        playing = track.map { PlayingTrack(track: $0) }
        _currentTrack.flatMap { history.insert($0) }
        
        if broadcast {
            NotificationCenter.default.post(name: .iTunesPlayerDidUpdated, object: nil)
        }
    }
    
}

