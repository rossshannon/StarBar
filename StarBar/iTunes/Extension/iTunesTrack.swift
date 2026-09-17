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
import ScriptingBridge

/// The four character codes Music uses for its track classes in Apple Events.
/// `iTunesTrack` is a protocol, so these can't live on it as static properties.
enum MusicTrackClass {
    /// `'cURT'`: a song streamed from the Apple Music catalog, not in the library
    static let urlTrack: FourCharCode = 0x63555254
    /// `'cFlT'`: a song in the library, whether local, purchased or added from Apple Music
    static let fileTrack: FourCharCode = 0x63466c54
}

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

    /// Music's own class for this track, as the four character code it uses in Apple Events.
    ///
    /// Don't reach for `is iTunesURLTrack` instead. `iTunes/Vendor/iTunes.swift` declares
    /// `SBObject` as conforming to the file, shared *and* URL track protocols, so every one of
    /// those casts succeeds for every track and tells us nothing.
    var scriptingClassCode: FourCharCode? {
        guard let descriptor = (self as AnyObject).value(forKey: "objectClass") as? NSAppleEventDescriptor else { return nil }
        return descriptor.typeCodeValue
    }

    /// A song playing straight from the Apple Music catalog that the user has not added to
    /// their library. Music calls this a "URL track".
    ///
    /// Ratings can't be stored on one: Music refuses the write with a permission error
    /// (OSStatus -54), which arrives through `SBApplicationDelegate.eventDidFail` after the
    /// fact, so the write looks like it worked. The favorite heart does save. Adding the song
    /// to the library turns it into a `file track`, and then ratings work normally.
    ///
    /// Being an Apple Music song is not the same thing: a song added to the library from Apple
    /// Music is a `file track` like any other, and rates normally whether or not it is
    /// downloaded. Library membership is what matters here, not where the audio comes from.
    var isCatalogStream: Bool {
        return scriptingClassCode == MusicTrackClass.urlTrack
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
