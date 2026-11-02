//
//  AppleMusicArtworkLoader.swift
//  StarBar
//
//  An Apple Music song's cover, from Apple's public iTunes Search service, for when Music hands
//  back the previous song's cover instead, or none at all. The search's answer is read by pure
//  rules: see `AppleMusicArtworkLoaderTests`.
//

import Cocoa
import os

extension Notification.Name {
    /// An album's cover arrived from Apple. `userInfo` holds the image under
    /// `AppleMusicArtworkLoader.imageKey` and the identities of the song it was asked for, in
    /// both of the strip's shapes, under `AppleMusicArtworkLoader.identitiesKey`.
    static let appleMusicCoverDidLoad = Notification.Name("StarBarAppleMusicCoverDidLoad")
}

/// Finds a song's cover on Apple's iTunes Search service and downloads it.
///
/// Asked only for a catalog track the user doesn't have, so there is no copy to read instead,
/// when Music answered its artwork read with the previous song's cover or with none at all
/// (`PlayingTrack.sleeve()`). It sends the song's artist and title to `itunes.apple.com`,
/// which belongs to the company streaming the song, and nothing else about the user. Only
/// `https` on `itunes.apple.com` is asked and only `https` on `mzstatic.com`, Apple's image
/// host, is downloaded; each answer is capped, and the image is decoded off the main thread.
/// Answers on the main thread.
///
/// **It searches for the song, not the album.** Apple's album search doesn't know every
/// edition by the name Music gives it: measured 2026-11-02, "Radiohead OK Computer OKNOTOK
/// 1997 2017" found only the plain *OK Computer*, whose cover is another, while the song
/// search for "Exit Music (For a Film)" found the track on OKNOTOK with its own cover.
///
/// The title goes as Music gives it, and when that finds nothing, again without its bracketed
/// parts: measured the same day, "David Bowie Life On Mars? (Original Ending Version)" found no
/// Bowie song at all, while "David Bowie Life On Mars?" found the album at the 17th result.
///
/// A result is taken only when its album is the song's, letter for letter once case, accents
/// and punctuation are folded, and its artist or album artist is the song's
/// (`cover(in:artists:album:)`). **An edition is another album**: the search for "Obsidian"
/// answered with *Mixing Colours (Expanded)* and the plain *Mixing Colours*, whose covers
/// differ, and only the first was the song's. A wrong cover is worse than the placeholder,
/// which is what the strip and popover show when nothing matches. A song the searches
/// answered with no match isn't asked again this session, so the popover's reads on every
/// update don't search over and over. A cover found is kept for its album, since every track
/// of it has that one.
final class AppleMusicArtworkLoader {

    /// Fetches the bytes at a URL. `URLSession` in the app; a fake in tests, and nothing at all
    /// for `shared` under tests, which must not reach the network.
    typealias Fetch = (_ url: URL, _ completion: @escaping (Data?) -> Void) -> Void

    static let shared: AppleMusicArtworkLoader = {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let noNetwork: Fetch = { _, completion in completion(nil) }
        return AppleMusicArtworkLoader(fetch: isTesting ? noNetwork : SpotifyArtworkLoader.urlSessionFetch)
    }()

    static let imageKey = "image"
    static let identitiesKey = "identities"

    static let maximumSearchBytes = 1024 * 1024
    static let maximumImageBytes = 4 * 1024 * 1024
    static let cacheSize = 8
    /// The side of the cover asked for, in pixels: the catalog's own covers measured 800, a
    /// library copy's 600, and the strip draws at most 160 points, so 600 is plenty
    static let coverSide = 600

    private let fetch: Fetch
    private let country: String?
    private var cache: [(album: String, image: NSImage)] = []
    /// Songs, by album key and folded title, the search answered without a match
    private var notFound: Set<String> = []
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]

    /// `country` picks the store searched, the Mac's region by default, since an album can be
    /// in one country's catalog and not another's
    init(fetch: @escaping Fetch, country: String? = AppleMusicArtworkLoader.currentCountry) {
        self.fetch = fetch
        self.country = country
    }

    static var currentCountry: String? {
        return Locale.current.region?.identifier
    }

    /// The album's key: its name and its first artist, folded, or nil when either is missing.
    /// `artists` is the track's artist first, then the album artist.
    static func key(artists: [String], album: String) -> String? {
        let name = albumName(album)
        guard !name.isEmpty, let artist = artists.map(SongName.fold).first(where: { !$0.isEmpty }) else { return nil }
        return artist + "|" + name
    }

    /// An album's name as this compares it: letters and digits, folded, so that only case,
    /// accents and punctuation are let go. Not `SongName.releaseName`, which would take an
    /// edition for the album and so give it the album's cover.
    static func albumName(_ album: String) -> String {
        return SongName.squash(SongName.fold(album))
    }

    /// True while nothing has been downloaded, so a caller can skip the Apple Events it would
    /// take to name the album
    var isEmpty: Bool {
        return cache.isEmpty
    }

    /// A cover already downloaded for the album, or nil. No network.
    func cachedCover(artists: [String], album: String) -> NSImage? {
        guard let key = AppleMusicArtworkLoader.key(artists: artists, album: album) else { return nil }
        return cache.last(where: { $0.album == key })?.image
    }

    /// The cover of the song `title` on `album`, from the cache or from Apple. `artists` is the
    /// track's artist first, then the album artist. `completion` runs on the main thread, with
    /// nil when there's no match or the network failed.
    func load(title: String, artists: [String], album: String, completion: @escaping (NSImage?) -> Void) {
        let artist = artists.first(where: { !$0.isEmpty }) ?? ""
        let searches = AppleMusicArtworkLoader.searchTitles(title).compactMap {
            AppleMusicArtworkLoader.searchURL(artist: artist, title: $0, country: country)
        }
        guard let key = AppleMusicArtworkLoader.key(artists: artists, album: album), !searches.isEmpty else {
            completion(nil)
            return
        }
        if let image = cachedCover(artists: artists, album: album) {
            completion(image)
            return
        }
        let song = key + "|" + SongName.fold(title)
        guard !notFound.contains(song) else {
            completion(nil)
            return
        }
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            return
        }
        inFlight[key] = [completion]
        os_log("%{public}s[%{public}ld], %{public}s: asking Apple for the cover of %{public}s by %{public}s on %{public}s", ((#file as NSString).lastPathComponent), #line, #function, title, artists.first ?? "nil", album)

        find(searches[...], artists: artists, album: album) { [weak self] found, allAnswered in
            guard let cover = found else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if allAnswered {
                        // Apple answered, and none of it was this album
                        self.notFound.insert(song)
                    }
                    os_log("%{public}s[%{public}ld], %{public}s: Apple has no cover for %{public}s by %{public}s on %{public}s%{public}s", ((#file as NSString).lastPathComponent), #line, #function, title, artists.first ?? "nil", album, allAnswered ? "" : " (a search failed)")
                    self.finish(key, with: nil)
                }
                return
            }
            self?.fetch(cover) { [weak self] data in
                // Decode where the bytes arrived, off the main thread
                let image = data.flatMap { $0.count <= AppleMusicArtworkLoader.maximumImageBytes ? NSImage(data: $0) : nil }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let image = image {
                        os_log("%{public}s[%{public}ld], %{public}s: the cover of %{public}s by %{public}s came from %{public}s", ((#file as NSString).lastPathComponent), #line, #function, album, artists.first ?? "nil", cover.absoluteString)
                        self.cache.removeAll(where: { $0.album == key })
                        self.cache.append((album: key, image: image))
                        if self.cache.count > AppleMusicArtworkLoader.cacheSize {
                            self.cache.removeFirst(self.cache.count - AppleMusicArtworkLoader.cacheSize)
                        }
                    } else {
                        os_log("%{public}s[%{public}ld], %{public}s: no image at %{public}s", ((#file as NSString).lastPathComponent), #line, #function, cover.absoluteString)
                    }
                    self.finish(key, with: image)
                }
            }
        }
    }

    /// Runs each search in turn until one finds the album, and answers with its cover, or nil
    /// and whether every search was answered. Off the main thread.
    private func find(_ searches: ArraySlice<URL>, artists: [String], album: String, allAnswered: Bool = true,
                      completion: @escaping (_ cover: URL?, _ allAnswered: Bool) -> Void) {
        guard let search = searches.first else {
            completion(nil, allAnswered)
            return
        }
        fetch(search) { [weak self] data in
            let found = data
                .flatMap { $0.count <= AppleMusicArtworkLoader.maximumSearchBytes ? $0 : nil }
                .flatMap { AppleMusicArtworkLoader.cover(in: $0, artists: artists, album: album) }
            if let found = found {
                completion(found, true)
            } else if let self = self {
                self.find(searches.dropFirst(), artists: artists, album: album, allAnswered: allAnswered && data != nil, completion: completion)
            } else {
                completion(nil, false)
            }
        }
    }

    private func finish(_ key: String, with image: NSImage?) {
        let waiting = inFlight.removeValue(forKey: key) ?? []
        waiting.forEach { $0(image) }
    }

    // MARK: - The search, pure

    /// The titles to search for, in turn: the title as Music gives it, then, when it has any,
    /// without its bracketed parts and anything after " - ". Apple's search can find nothing
    /// for a name it holds in full ("Life On Mars? (Original Ending Version)").
    static func searchTitles(_ title: String) -> [String] {
        let full = title.trimmingCharacters(in: .whitespaces)
        guard !full.isEmpty else { return [] }
        var core = full.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
        if let dash = core.range(of: " - ") {
            core = String(core[..<dash.lowerBound])
        }
        core = core.trimmingCharacters(in: .whitespaces)
        return core.isEmpty || core == full ? [full] : [full, core]
    }

    /// The search for a song: Apple's `search` endpoint, for songs, by artist and title as
    /// Music gives them. Twenty-five results, because one song can be on many releases (the
    /// album, its editions, singles, compilations, live albums) and only one is the album
    /// being looked for.
    static func searchURL(artist: String, title: String, country: String?) -> URL? {
        guard !artist.isEmpty, !title.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        var items = [
            ("term", artist + " " + title),
            ("media", "music"),
            ("entity", "song"),
            ("limit", "25"),
        ]
        if let country = country, country.count == 2 {
            items.append(("country", country.lowercased()))
        }
        // Encoded by hand: `queryItems` leaves "+" alone, which the service reads as a space,
        // and names such as "Florence + The Machine" and "Simon & Garfunkel" have them
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#/"))
        components?.percentEncodedQueryItems = items.map { name, value in
            URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: allowed))
        }
        return components?.url
    }

    /// The cover of the first result in a search's answer whose album is `album` (`albumName`)
    /// and whose artist or album artist is one of `artists`, at `coverSide` pixels, or nil
    static func cover(in data: Data, artists: [String], album: String) -> URL? {
        guard let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = answer["results"] as? [[String: Any]] else { return nil }
        let wanted = albumName(album)
        let wantedArtists = Set(artists.map(SongName.fold).filter { !$0.isEmpty })
        guard !wanted.isEmpty, !wantedArtists.isEmpty else { return nil }
        for result in results {
            let resultArtists = ["artistName", "collectionArtistName"].compactMap { result[$0] as? String }.map(SongName.fold)
            guard let name = result["collectionName"] as? String, albumName(name) == wanted,
                  resultArtists.contains(where: wantedArtists.contains),
                  let small = result["artworkUrl100"] as? String else { continue }
            let size = "\(coverSide)x\(coverSide)bb"
            guard let url = URL(string: small.replacingOccurrences(of: "100x100bb", with: size)),
                  isAllowedCover(url) else { continue }
            return url
        }
        return nil
    }

    /// True for a cover this loader will download: https, on `mzstatic.com` or a subdomain
    static func isAllowedCover(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "mzstatic.com" || host.hasSuffix(".mzstatic.com")
    }

}
