//
//  SpotifyArtworkLoader.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-10-21.
//

import Cocoa
import os

/// Downloads a Spotify song's sleeve from the `artwork url` Spotify's AppleScript reports.
///
/// The only network request StarBar makes. The URL comes from another app's Apple Event
/// reply, so only `https` on Spotify's image host is fetched, the download is capped, and the
/// image is decoded off the main thread. Answers on the main thread. A few sleeves are kept,
/// keyed by URL, so an album played through costs one download.
final class SpotifyArtworkLoader {

    /// Fetches the bytes at a URL. `URLSession` in the app; a fake in tests.
    typealias Fetch = (_ url: URL, _ completion: @escaping (Data?) -> Void) -> Void

    static let maximumBytes = 4 * 1024 * 1024
    static let cacheSize = 8
    static let timeout: TimeInterval = 10

    private let fetch: Fetch
    private var cache: [(url: URL, image: NSImage)] = []
    private var inFlight: [URL: [(NSImage?) -> Void]] = [:]

    init(fetch: @escaping Fetch = SpotifyArtworkLoader.urlSessionFetch) {
        self.fetch = fetch
    }

    /// True for a URL this loader will fetch: https, on `scdn.co` or a subdomain of it
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co")
    }

    /// A sleeve already downloaded, or nil. No network.
    func cachedImage(for url: URL) -> NSImage? {
        return cache.first { $0.url == url }?.image
    }

    /// The sleeve at `url`, from the cache or the network. `completion` runs on the main
    /// thread, with nil when the URL isn't allowed or the download failed.
    func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let image = cachedImage(for: url) {
            completion(image)
            return
        }
        guard SpotifyArtworkLoader.isAllowed(url) else {
            os_log("%{public}s[%{public}ld], %{public}s: not fetching artwork from %{public}s", ((#file as NSString).lastPathComponent), #line, #function, url.absoluteString)
            completion(nil)
            return
        }
        if inFlight[url] != nil {
            inFlight[url]?.append(completion)
            return
        }
        inFlight[url] = [completion]
        fetch(url) { [weak self] data in
            // Decode where the bytes arrived, off the main thread
            let image = data.flatMap { $0.count <= SpotifyArtworkLoader.maximumBytes ? NSImage(data: $0) : nil }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let image = image {
                    self.cache.removeAll { $0.url == url }
                    self.cache.append((url, image))
                    if self.cache.count > SpotifyArtworkLoader.cacheSize {
                        self.cache.removeFirst(self.cache.count - SpotifyArtworkLoader.cacheSize)
                    }
                } else {
                    os_log("%{public}s[%{public}ld], %{public}s: no artwork from %{public}s", ((#file as NSString).lastPathComponent), #line, #function, url.absoluteString)
                }
                let waiting = self.inFlight.removeValue(forKey: url) ?? []
                waiting.forEach { $0(image) }
            }
        }
    }

    static func urlSessionFetch(_ url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = SpotifyArtworkLoader.timeout
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }

}
