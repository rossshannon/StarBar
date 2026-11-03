//
//  PlayingTrack.swift
//  StarBar
//
//  One answer to "what is playing, and where does its rating go?"
//

import AppKit
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

    /// The track the artwork is read from, by the announcement strip and the player popover
    /// alike: the user's own copy when they have one, the playing track otherwise.
    ///
    /// **Preferring the copy is the settled part.** A catalog track can answer the artwork
    /// read with `artworks = 0` and raise, which is why a song the user owned showed the
    /// placeholder while its library copy returned the sleeve perfectly well.
    ///
    /// **The fallback is a measured risk, not an oversight.** Music can answer a catalog
    /// track's artwork read with a *different song's* cover: on 2026-09-18, while naming its
    /// own current track "Strawberry Blonde", it returned the sleeve of the Brian Eno album
    /// played before it, and went on doing so for minutes. Nothing on an artwork says which
    /// song it belongs to, so that cannot be detected here.
    ///
    /// Refusing to read a catalog track's artwork at all was tried the same day and reverted
    /// within minutes: two other catalog tracks measured right after returned their own
    /// covers correctly, so the rule blanked the artwork for every Apple Music song to avoid
    /// an occasional wrong one. Don't reinstate it without evidence that being wrong is the
    /// common case rather than the exception. Read the cover through `sleeve()`, which
    /// refuses the one wrong answer that can be caught: the previous song's cover.
    var artworkTrack: iTunesTrack? {
        return ratingTrack ?? track
    }

    /// The playing track's album, read once
    private(set) lazy var album: String? = track.album

    /// The playing track's name and artist, each read once. Only for finding a catalog track's
    /// cover on Apple's service, which the popover can ask for on every update.
    private(set) lazy var name: String? = track.name
    private(set) lazy var artist: String? = track.artist

    /// The playing track's artist and album artist, in that order, without the empty ones,
    /// each read once
    private(set) lazy var artists: [String] = [artist, track.albumArtist].compactMap { $0 }.filter { !$0.isEmpty }

    /// The cover Music gives for the playing track, as a fingerprint, read once. Asked only of
    /// the record of the song before a catalog track whose cover is being checked: see
    /// `sleeve(history:previousSong:covers:)`. One artwork read, 44 ms on 2026-11-02.
    private(set) lazy var playedSleeve: SleeveHistory.Sleeve? = {
        guard let image = track.firstArtworkImage(), let fingerprint = SleeveFingerprint(image: image) else { return nil }
        return SleeveHistory.Sleeve(fingerprint: fingerprint, album: album)
    }()

    /// The cover to show for this song, for the strip and the popover alike: the artwork of
    /// `artworkTrack`, or nil, for the placeholder, when there is none or **it is the previous
    /// song's cover left over**, until Apple sends the right one.
    ///
    /// Music can answer for a catalog track with the cover of the song played before it (see
    /// `SleeveHistory`), and that is the only answer checked: the one for a catalog track the
    /// user doesn't have, where `artworkTrack` has nothing better to read. It is compared with
    /// the cover StarBar last showed for the previous song and with the one Music gives for
    /// that song now (`playedSleeve`, read once per song), always both, since they can differ:
    /// StarBar may have shown the user's copy's cover or Apple's, where what Music leaves over
    /// is its own answer for that track, and with the strip off and the popover first opened
    /// on the new song StarBar showed nothing at all.
    ///
    /// A cover refused is asked of Apple (`AppleMusicArtworkLoader`), and so is one Music has
    /// none of for such a track, which happens too: measured 2026-11-02, Music gave no artwork
    /// at all for "Exit Music (For a Film)" on *OK Computer OKNOTOK 1997 2017*, for minutes.
    /// When the cover arrives `.appleMusicCoverDidLoad` says so: the strip attaches it, the
    /// popover reads again, and this answers with it, ahead of Music's, for any catalog track
    /// of that album the user doesn't have. Until then, and when Apple has no match, the
    /// answer is nil.
    ///
    /// Each call reads the artwork afresh, so a cover Music puts right later shows the next
    /// time the popover reads it. A cover shown is kept in `history`, and one refused is not.
    func sleeve(history: SleeveHistory = .shared,
                previousSong: (String) -> PlayingTrack? = { iTunesPlayer.shared.previousSong(before: $0) },
                covers: AppleMusicArtworkLoader = .shared) -> NSImage? {
        // No copy of the song to read from, so this is Music's answer for the catalog track
        let isMusicsOwnAnswer = ratingTrack == nil
        if isMusicsOwnAnswer, !covers.isEmpty, let cover = covers.cachedCover(artists: artists, album: album ?? "") {
            if let song = persistentID, let fingerprint = SleeveFingerprint(image: cover) {
                history.record(fingerprint, for: song, album: { self.album })
            }
            return cover
        }

        guard let image = artworkTrack?.firstArtworkImage() else {
            if isMusicsOwnAnswer, let song = persistentID {
                os_log("%{public}s[%{public}ld], %{public}s: Music gave no cover for %{public}s on %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song, album ?? "nil")
                askAppleForTheCover(covers, song: song)
            }
            return nil
        }
        guard let song = persistentID, let fingerprint = SleeveFingerprint(image: image) else { return image }

        if isMusicsOwnAnswer, let previous = previousSong(song), let previousID = previous.persistentID {
            let earlier: [(source: String, read: () -> SleeveHistory.Sleeve?)] = [
                ("shown", { history.sleeve(for: previousID) }),
                ("in Music", { previous.playedSleeve }),
            ]
            for (source, read) in earlier {
                guard let before = read() else { continue }
                let isLeftOver = SleeveHistory.isLeftOver(fingerprint, onAlbum: { self.album }, from: before)
                os_log("%{public}s[%{public}ld], %{public}s: the cover Music gave for %{public}s differs by %.3f from the one %{public}s for the song before it, %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song, fingerprint.difference(from: before.fingerprint), source, previousID)
                if isLeftOver {
                    os_log("%{public}s[%{public}ld], %{public}s: %{public}s on %{public}s came with the cover of %{public}s on %{public}s; showing none rather than the wrong one", ((#file as NSString).lastPathComponent), #line, #function, song, album ?? "nil", previousID, before.album ?? "nil")
                    askAppleForTheCover(covers, song: song)
                    return nil
                }
            }
        }
        history.record(fingerprint, for: song, album: { self.album })
        return image
    }

    /// Ask Apple for the song's cover, and say when it has come, with the song's identity in
    /// both of the strip's shapes: its persistent ID, and `name|artist|album`, which is what
    /// the strip goes by when Music's notification carried no ID
    private func askAppleForTheCover(_ covers: AppleMusicArtworkLoader, song: String) {
        guard let album = album, !album.isEmpty, !artists.isEmpty, let title = name, !title.isEmpty else {
            os_log("%{public}s[%{public}ld], %{public}s: can't ask Apple for the cover of %{public}s: Music named no album, artist or title (%{public}s, %{public}ld artists, %{public}s)", ((#file as NSString).lastPathComponent), #line, #function, song, album ?? "nil", artists.count, name ?? "nil")
            return
        }
        let identities = [
            song.uppercased(),
            TrackAnnouncementController.PlayerSnapshot.identity(name: title, artist: artist, album: album),
        ].compactMap { $0 }
        covers.load(title: title, artists: artists, album: album) { image in
            guard let image = image else { return }
            NotificationCenter.default.post(name: .appleMusicCoverDidLoad, object: nil, userInfo: [
                AppleMusicArtworkLoader.imageKey: image,
                AppleMusicArtworkLoader.identitiesKey: identities,
            ])
        }
    }

    /// The song has just been added to the library, so that copy now carries its rating.
    ///
    /// The playing track stays a catalog track for the rest of the song -- it never becomes
    /// the library copy -- so this has to be told, it cannot be noticed.
    func didAddToLibrary(_ libraryTrack: iTunesTrack) {
        ratingTrack = libraryTrack
    }

}
