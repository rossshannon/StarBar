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
    
    /// Favorite status in Music.
    ///
    /// Music renamed the scripting property "loved" to "favorited" (same code, pLov).
    /// Scripting Bridge resolves properties by name, so try the new name first and fall back
    /// to "loved" for older Music and iTunes versions.
    var isFavorited: Bool {
        return favorited ?? loved ?? false
    }

    func updateFavorited(_ value: Bool) {
        // An unimplemented optional method returns nil, so fall back to the old name
        if setFavorited?(value) == nil {
            setLoved?(value)
        }
    }
    
}
