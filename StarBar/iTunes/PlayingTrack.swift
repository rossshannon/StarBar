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
    /// common case rather than the exception. Read the cover through `sleeve()`, which takes
    /// Apple's cover over Music's for a catalog track the user doesn't have, whenever Apple's
    /// search finds the song's album.
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

    /// The cover to show for this song, for the strip and the popover alike, or nil for the
    /// placeholder.
    ///
    /// The user's copy, or a library track, answers with its own artwork as it is.
    ///
    /// **A catalog track the user doesn't have answers with Apple's cover** whenever Apple's
    /// search finds the song on its album (`AppleMusicArtworkLoader`), because Music's own
    /// answer can be another song's cover and nothing on an image says whose it is. Measured:
    /// Music answered with the previous song's cover on 2026-09-18 and 2026-11-02 ("Strawberry
    /// Blonde" with *Another Green World*, "Chain Home" with *The Bends*), and on 2026-11-03
    /// with *Coda* for Nils Frahm's "Some", 45 minutes and twelve songs after the *Coda* song,
    /// for which Music had had no cover at all. It can also have none ("Exit Music (For a
    /// Film)" on *OK Computer OKNOTOK 1997 2017*, 2026-11-02, for minutes).
    ///
    /// So the first read for such a song's album answers nil and asks Apple (a read after a
    /// failed ask answers with Music's cover while it asks again). When the cover
    /// comes, `.appleMusicCoverDidLoad` says so: the strip attaches it and the popover reads
    /// again, each fading it in from the placeholder, and from then on this answers with it at
    /// once, for every catalog track of the album the user doesn't have. When Apple has no
    /// match, or can't be reached, Music's own cover is posted the same way and stands
    /// (`AppleMusicArtworkLoader.hasAnswered`), so long as it isn't the previous song's
    /// (`musicsOwnCover`).
    ///
    /// Each call reads Music's artwork afresh, so a cover Music puts right later shows the next
    /// time the popover reads it. A cover shown is kept in `history`, and one refused is not.
    func sleeve(history: SleeveHistory = .shared,
                previousSong: (String) -> PlayingTrack? = { iTunesPlayer.shared.previousSong(before: $0) },
                covers: AppleMusicArtworkLoader = .shared) -> NSImage? {
        // With a copy of the song to read from, or no ID to keep a cover under, the artwork
        // read is the answer
        guard ratingTrack == nil, let song = persistentID else {
            let image = artworkTrack?.firstArtworkImage()
            if let image = image, let song = persistentID {
                history.record(image, for: song, album: { self.album })
            }
            return image
        }

        let title = name ?? "", album = self.album ?? ""
        if let cover = covers.cachedCover(artists: artists, album: album) {
            history.record(cover, for: song, album: { album })
            return cover
        }
        // An earlier read of this song asked already, and that ask says when the cover comes:
        // the popover reads on every update, and each read once read Music's cover and waited
        // on the ask again, so the cover arrived once for every read made meanwhile
        guard !covers.isAsking(title: title, artists: artists, album: album) else { return nil }
        let musics = musicsOwnCover(for: song, history: history, previousSong: previousSong)
        guard !covers.hasAnswered(title: title, artists: artists, album: album) else {
            if title.isEmpty || album.isEmpty || artists.isEmpty {
                os_log("%{public}s[%{public}ld], %{public}s: can't ask Apple for the cover of %{public}s: Music named no album, artist or title (%{public}s, %{public}ld artists, %{public}s)", ((#file as NSString).lastPathComponent), #line, #function, song, album, artists.count, title)
            }
            if let musics = musics {
                history.record(musics, for: song, album: { album })
            }
            return musics
        }
        // Asking again after a failure, Music's cover stays on show meanwhile: with the
        // network down, the placeholder would otherwise flash up once every `retryAfter`
        let isRetry = covers.hasFailedBefore(title: title, artists: artists, album: album)
        askAppleForTheCover(covers, song: song, title: title, album: album, otherwise: musics, history: history)
        return isRetry ? musics : nil
    }

    /// Music's cover for this catalog track, or nil when it gave none or **gave the previous
    /// song's cover**, which is what both wrong covers seen before 2026-11-03 were. Compared
    /// with the cover StarBar showed for the previous song and with what Music gives for that
    /// song now (`playedSleeve`), always both, since they can differ: StarBar may have shown
    /// Apple's cover, where what Music leaves over is its own answer for that track, and with
    /// the strip off and the popover first opened on the new song StarBar showed nothing.
    private func musicsOwnCover(for song: String, history: SleeveHistory, previousSong: (String) -> PlayingTrack?) -> NSImage? {
        guard let image = track.firstArtworkImage() else {
            os_log("%{public}s[%{public}ld], %{public}s: Music gave no cover for %{public}s on %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song, album ?? "nil")
            return nil
        }
        guard let fingerprint = SleeveFingerprint(image: image),
              let previous = previousSong(song), let previousID = previous.persistentID else { return image }
        let earlier: [(source: String, read: () -> SleeveHistory.Sleeve?)] = [
            ("shown", { history.sleeve(for: previousID) }),
            ("in Music", { previous.playedSleeve }),
        ]
        for (source, read) in earlier {
            guard let before = read() else { continue }
            let isLeftOver = SleeveHistory.isLeftOver(fingerprint, onAlbum: { self.album }, from: before)
            os_log("%{public}s[%{public}ld], %{public}s: the cover Music gave for %{public}s differs by %.3f from the one %{public}s for the song before it, %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song, fingerprint.difference(from: before.fingerprint), source, previousID)
            if isLeftOver {
                os_log("%{public}s[%{public}ld], %{public}s: %{public}s on %{public}s came with the cover of %{public}s on %{public}s; refusing it", ((#file as NSString).lastPathComponent), #line, #function, song, album ?? "nil", previousID, before.album ?? "nil")
                return nil
            }
        }
        return image
    }

    /// Ask Apple for the song's cover, and say when a cover has come, Apple's or, when Apple
    /// has none, `otherwise`, Music's own, with the song's identity in both of the strip's
    /// shapes: its persistent ID, and `name|artist|album`, which is what the strip goes by
    /// when Music's notification carried no ID
    private func askAppleForTheCover(_ covers: AppleMusicArtworkLoader, song: String, title: String, album: String,
                                     otherwise: NSImage?, history: SleeveHistory) {
        let identities = [
            song.uppercased(),
            TrackAnnouncementController.PlayerSnapshot.identity(name: title, artist: artist, album: album),
        ].compactMap { $0 }
        covers.load(title: title, artists: artists, album: album) { image in
            if image == nil {
                os_log("%{public}s[%{public}ld], %{public}s: Apple has no cover for %{public}s, so Music's own stands: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, song, otherwise == nil ? "none" : "a cover")
            }
            guard let cover = image ?? otherwise else { return }
            history.record(cover, for: song, album: { album })
            NotificationCenter.default.post(name: .appleMusicCoverDidLoad, object: nil, userInfo: [
                AppleMusicArtworkLoader.imageKey: cover,
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
