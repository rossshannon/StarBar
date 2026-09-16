//
//  iTunesPlayer.swift
//  Song Rating
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
        _currentTrack.flatMap { history.insert($0) }
        
        // Debug logging
        if let track = _currentTrack {
            NSLog("Updated current track: \(track.name ?? "unknown") - Rating: \(track.rating ?? 0), Loved: \(track.loved ?? false)")
        }
        
        if broadcast {
            NotificationCenter.default.post(name: .iTunesPlayerDidUpdated, object: nil)
        }
    }
    
}

