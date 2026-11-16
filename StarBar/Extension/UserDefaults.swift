//
//  UserDefaults.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-10-26.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation

enum ApplicationKey: String {
    case isFirstLaunch
    case allowHalfStar
    case remindToRateUnrated
    case announceNewTracks
    case announcementStyle
    case announcementAlbumTint
    case spotifyClientID
}

extension UserDefaults {

    subscript<T: RawRepresentable>(key: String) -> T? {
        get {
            if let rawValue = value(forKey: key) as? T.RawValue {
                return T(rawValue: rawValue)
            }
            return nil
        }
        set { set(newValue?.rawValue, forKey: key) }
    }

    subscript<T>(key: String) -> T? {
        get { return value(forKey: key) as? T }
        set { set(newValue, forKey: key) }
    }

}

extension UserDefaults {

    @objc dynamic var allowHalfStar: Bool {
        get {
            return bool(forKey: ApplicationKey.allowHalfStar.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.allowHalfStar.rawValue)
        }
    }

    /// Play a bell and sweep a star across the dots when an unrated track nears its end
    @objc dynamic var remindToRateUnrated: Bool {
        get {
            return bool(forKey: ApplicationKey.remindToRateUnrated.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.remindToRateUnrated.rawValue)
        }
    }

    /// Slide a Growl-style Music Video strip up from the bottom of the screen when a new
    /// song starts
    @objc dynamic var announceNewTracks: Bool {
        get {
            return bool(forKey: ApplicationKey.announceNewTracks.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.announceNewTracks.rawValue)
        }
    }

    /// The strip's background: a `TrackAnnouncementStyle` raw value
    @objc dynamic var announcementStyle: String {
        get {
            return string(forKey: ApplicationKey.announcementStyle.rawValue) ?? TrackAnnouncementStyle.default.rawValue
        }
        set {
            set(newValue, forKey: ApplicationKey.announcementStyle.rawValue)
        }
    }

    /// Tint the strip's background with the colour of the song's cover, off by default
    @objc dynamic var announcementAlbumTint: Bool {
        get {
            return bool(forKey: ApplicationKey.announcementAlbumTint.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.announcementAlbumTint.rawValue)
        }
    }

    /// Hidden: the client ID of someone's own app on Spotify's developer dashboard, used for
    /// liking songs in place of StarBar's built-in one. Empty means the built-in one.
    @objc dynamic var spotifyClientID: String {
        get {
            return string(forKey: ApplicationKey.spotifyClientID.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: ApplicationKey.spotifyClientID.rawValue)
        }
    }

}
