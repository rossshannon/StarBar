//
//  PlayingTrack.swift
//  StarBar
//
//  One answer to "what is playing, and where does its rating go?"
//

import Foundation
import os

/// The song Music is playing, and the track that carries its rating.
///
/// Those are not always the same object. Opening an album in Apple Music plays a **catalog
/// track**, which has its own ID and a rating that cannot be written, even when the user has
/// the song in their library. The rating belongs to their own copy.
///
/// Everything that shows or writes a rating reads this one record: the menu bar stars, the
/// rating shortcuts and the track announcement. When they each worked it out for themselves
/// they disagreed on screen -- the menu bar showing three stars for a song the announcement
/// showed as unrated -- and each had to be fixed separately.
///
/// Each answer costs an Apple Event, so each is read at most once and then remembered. The
/// record is replaced when the song changes, which is what expires it.
final class PlayingTrack {

    /// The track Music is playing. May be an Apple Music catalog track.
    let track: iTunesTrack

    init(track: iTunesTrack) {
        self.track = track
    }

    /// Music's persistent ID for the playing track.
    ///
    /// Not the one in its `playerInfo` notification: that is missing for some Apple Music
    /// tracks, so comparing it could not tell that the song had changed.
    private(set) lazy var persistentID: String? = {
        let id = track.persistentID
        return (id?.isEmpty ?? true) ? nil : id
    }()

    /// True when the playing track is streamed from the Apple Music catalog, so it cannot
    /// itself hold a rating. See `iTunesTrack.isCatalogStream`.
    private(set) lazy var isCatalogStream: Bool = track.isCatalogStream

    /// The track a rating should be written to and read from: the playing track itself when
    /// it is in the library, or the user's own copy when a catalog track is playing.
    ///
    /// Nil when a catalog track is playing and the user does not have the song: then there is
    /// nowhere to put a rating, and the menu bar offers to add it instead.
    private(set) lazy var ratingTrack: iTunesTrack? = {
        guard isCatalogStream else { return track }

        let copy = iTunesRadioStation.shared.libraryCopy(of: track)
        if copy != nil {
            os_log("%{public}s[%{public}ld], %{public}s: %{public}s is playing from Apple Music but is in the library; its own copy carries the rating", ((#file as NSString).lastPathComponent), #line, #function, track.name ?? "nil")
        }
        return copy
    }()

    /// Whether this song can be rated at all
    var canRate: Bool {
        return ratingTrack != nil
    }

    /// The track the favourite heart is read from and written to.
    ///
    /// The user's own copy whenever they have one. Music answers `favorited` separately on
    /// the two objects: measured on 2026-09-18, a library copy read `true` while the catalog
    /// track playing that same song read `false`, so a heart set through the playing track
    /// never came back. A catalog track's database ID is ephemeral in any case -- two reads
    /// of one playing track gave different numbers -- so nothing the user chooses can live
    /// on it.
    ///
    /// Falls back to the playing track, because a catalog track the user does not have does
    /// accept the heart where it refuses a rating. Only the write on that path has been
    /// measured, never the read back, so it is the one assumption left here.
    ///
    /// This resolves `ratingTrack`, which costs a library search the first time. Every caller
    /// today has already resolved it; don't reach for this from a cold click handler.
    var favoriteTrack: iTunesTrack {
        return ratingTrack ?? track
    }

    /// The song has just been added to the library, so that copy now carries its rating.
    ///
    /// The playing track stays a catalog track for the rest of the song -- it never becomes
    /// the library copy -- so this has to be told, it cannot be noticed.
    func didAddToLibrary(_ libraryTrack: iTunesTrack) {
        ratingTrack = libraryTrack
    }

}
