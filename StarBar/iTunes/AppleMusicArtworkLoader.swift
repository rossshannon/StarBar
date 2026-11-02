//
//  AppleMusicArtworkLoader.swift
//  StarBar
//
//  An Apple Music album's cover, from Apple's public iTunes Search service, for when Music
//  hands back the previous song's cover instead. The search's answer is read by pure rules:
//  see `AppleMusicArtworkLoaderTests`.
//

import Cocoa
import os

extension Notification.Name {
    /// An album's cover arrived from Apple. `userInfo` holds the image under
    /// `AppleMusicArtworkLoader.imageKey` and the identities of the song it was asked for, in
    /// both of the strip's shapes, under `AppleMusicArtworkLoader.identitiesKey`.
    static let appleMusicCoverDidLoad = Notification.Name("StarBarAppleMusicCoverDidLoad")
}

/// Finds an album's cover on Apple's iTunes Search service and downloads it.
///
/// Asked only when Music answered a catalog track's artwork read with the previous song's
/// cover (`PlayingTrack.sleeve()`), for a song the user doesn't have, so there is no copy to
/// read instead. It sends the album's artist and name to `itunes.apple.com`, which belongs to
/// the company streaming the song, and nothing else about the user. Only `https` on
/// `itunes.apple.com` is asked and only `https` on `mzstatic.com`, Apple's image host, is
/// downloaded; each answer is capped, and the image is decoded off the main thread. Answers
/// on the main thread.
///
/// A result is taken only when its album and artist are the song's, folded as releases and
/// names (`cover(in:artists:album:)`): a wrong cover is worse than the placeholder, which is
/// what the strip and popover show when nothing matches. An album the search answered with no
/// match isn't asked again this session, so the popover's reads on every update don't search
/// over and over.
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

    /// The album's key: its release name and its first artist, folded, or nil when either is
    /// missing. `artists` is the album artist first, then the track's artist.
    static func key(artists: [String], album: String) -> String? {
        let name = SongName.releaseName(album)
        guard !name.isEmpty, let artist = artists.map(SongName.fold).first(where: { !$0.isEmpty }) else { return nil }
        return artist + "|" + name
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

    /// The album's cover, from the cache or from Apple. `completion` runs on the main thread,
    /// with nil when there's no match or the network failed.
    func load(artists: [String], album: String, completion: @escaping (NSImage?) -> Void) {
        guard let key = AppleMusicArtworkLoader.key(artists: artists, album: album),
              let search = AppleMusicArtworkLoader.searchURL(artist: artists.first(where: { !$0.isEmpty }) ?? "", album: album, country: country) else {
            completion(nil)
            return
        }
        if let image = cachedCover(artists: artists, album: album) {
            completion(image)
            return
        }
        guard !notFound.contains(key) else {
            completion(nil)
            return
        }
        if inFlight[key] != nil {
            inFlight[key]?.append(completion)
            return
        }
        inFlight[key] = [completion]
        os_log("%{public}s[%{public}ld], %{public}s: asking Apple for the cover of %{public}s by %{public}s", ((#file as NSString).lastPathComponent), #line, #function, album, artists.first ?? "nil")

        fetch(search) { [weak self] data in
            let found = data
                .flatMap { $0.count <= AppleMusicArtworkLoader.maximumSearchBytes ? $0 : nil }
                .flatMap { AppleMusicArtworkLoader.cover(in: $0, artists: artists, album: album) }
            guard let cover = found else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if data != nil {
                        // Apple answered, and none of it was this album
                        self.notFound.insert(key)
                    }
                    os_log("%{public}s[%{public}ld], %{public}s: Apple has no cover for %{public}s by %{public}s%{public}s", ((#file as NSString).lastPathComponent), #line, #function, album, artists.first ?? "nil", data == nil ? " (the search failed)" : "")
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

    private func finish(_ key: String, with image: NSImage?) {
        let waiting = inFlight.removeValue(forKey: key) ?? []
        waiting.forEach { $0(image) }
    }

    // MARK: - The search, pure

    /// The search for an album: Apple's `search` endpoint, for albums, by artist and name
    static func searchURL(artist: String, album: String, country: String?) -> URL? {
        let term = [artist, album].filter { !$0.isEmpty }.joined(separator: " ")
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        var items = [
            ("term", term),
            ("media", "music"),
            ("entity", "album"),
            ("limit", "10"),
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

    /// The cover of the first album in a search's answer whose name is `album` as a release
    /// and whose artist is one of `artists`, at `coverSide` pixels, or nil
    static func cover(in data: Data, artists: [String], album: String) -> URL? {
        guard let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = answer["results"] as? [[String: Any]] else { return nil }
        let wanted = SongName.releaseName(album)
        let wantedArtists = Set(artists.map(SongName.fold).filter { !$0.isEmpty })
        guard !wanted.isEmpty, !wantedArtists.isEmpty else { return nil }
        for result in results {
            guard let name = result["collectionName"] as? String, SongName.releaseName(name) == wanted,
                  let artist = result["artistName"] as? String, wantedArtists.contains(SongName.fold(artist)),
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
