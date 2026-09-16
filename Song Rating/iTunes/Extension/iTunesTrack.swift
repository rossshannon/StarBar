//
//  iTunesTrack.swift
//  Song Rating
//
//  Created by Cirno MainasuK on 2019-8-17.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation

extension iTunesTrack {
    
    var userRating: Int? {
        return ratingKind == .user ? rating : nil
    }
    
    /// Toggle the loved status of this track
    func toggleLoved() {
        let currentStatus = loved ?? false
        NSLog("Toggling loved status for track \(name ?? "unknown") from \(currentStatus) to \(!currentStatus)")
        setLoved?(!currentStatus)
        // Force-retrieve the value again to verify it was set
        NSLog("After toggle, loved status is now: \(loved ?? false)")
    }
    
}
