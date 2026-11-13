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
    case spotifyClientID
    case lastfmScrobbleSpotify
    case lastfmLoveSync
    case lastfmPaused
    case lastfmDryRun
    case lastfmAPIKey
    case lastfmSharedSecret
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

    /// Scrobble songs played in Spotify to Last.fm as well as Music's. Off by default:
    /// Last.fm's own Spotify link already scrobbles Spotify, and both together double them.
    @objc dynamic var lastfmScrobbleSpotify: Bool {
        get {
            return bool(forKey: ApplicationKey.lastfmScrobbleSpotify.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.lastfmScrobbleSpotify.rawValue)
        }
    }

    /// Love a song on Last.fm when its heart is set in StarBar, unlove it when the heart is
    /// cleared, and love a song already favourited as it scrobbles. On by default
    /// (registered in `AppDelegate.setupUserDefaults`).
    @objc dynamic var lastfmLoveSync: Bool {
        get {
            return bool(forKey: ApplicationKey.lastfmLoveSync.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.lastfmLoveSync.rawValue)
        }
    }

    /// "Pause Scrobbling": nothing played is kept or sent to Last.fm until it is switched
    /// off again. Kept between launches, so an update doesn't quietly resume it.
    @objc dynamic var lastfmPaused: Bool {
        get {
            return bool(forKey: ApplicationKey.lastfmPaused.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.lastfmPaused.rawValue)
        }
    }

    /// Hidden: log what would be sent to Last.fm and send nothing. Needs no sign-in.
    @objc dynamic var lastfmDryRun: Bool {
        get {
            return bool(forKey: ApplicationKey.lastfmDryRun.rawValue)
        }
        set {
            set(newValue, forKey: ApplicationKey.lastfmDryRun.rawValue)
        }
    }

    /// Hidden: the API key of someone's own Last.fm API account, used with
    /// `lastfmSharedSecret` in place of StarBar's built-in ones. Empty means the built-in.
    @objc dynamic var lastfmAPIKey: String {
        get {
            return string(forKey: ApplicationKey.lastfmAPIKey.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: ApplicationKey.lastfmAPIKey.rawValue)
        }
    }

    /// Hidden: the shared secret that goes with `lastfmAPIKey`, or, on its own, one for a
    /// build made without the built-in secret
    @objc dynamic var lastfmSharedSecret: String {
        get {
            return string(forKey: ApplicationKey.lastfmSharedSecret.rawValue) ?? ""
        }
        set {
            set(newValue, forKey: ApplicationKey.lastfmSharedSecret.rawValue)
        }
    }

}
