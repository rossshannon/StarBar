//
//  iTunesTrack.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-8-17.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation
import Cocoa
import os

extension iTunesTrack {

    /// The track's first artwork as an image, or nil when it has none or Music can't say.
    /// Scripting Bridge raises Objective-C exceptions on artwork access, so the reads are
    /// caught. Each read is an Apple Event.
    func firstArtworkImage() -> NSImage? {
        do {
            return try ExceptionCatcher.catchException {
                guard let artwork = self.artworks?().firstObject as? iTunesArtwork else { return nil }
                if let descriptor = (artwork.data as Any) as? NSAppleEventDescriptor {
                    return NSImage(data: descriptor.data)
                }
                if let image = (artwork.data as Any) as? NSImage {
                    return image
                }
                if let data = artwork.rawData, let image = NSImage(data: data) {
                    return image
                }
                return nil
            } as? NSImage ?? nil
        } catch {
            os_log("%{public}s[%{public}ld], %{public}s: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            return nil
        }
    }

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
