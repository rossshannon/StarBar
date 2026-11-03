//
//  SleeveHistory.swift
//  StarBar
//
//  Catching Music answering a catalog track's artwork read with the cover of the song played
//  before it. The rule and the fingerprints are pure: see `SleeveHistoryTests`.
//

import AppKit

/// The covers StarBar showed for the last few songs, and the rule that uses them.
///
/// Music can answer the artwork read for a song streamed from Apple Music with **the previous
/// song's cover**. On 2026-09-18 "Strawberry Blonde" came back with the sleeve of *Another
/// Green World*, played before it, for minutes on end; on 2026-11-02 Tom Rogerson and Brian
/// Eno's "Chain Home" came back with *The Bends*, straight after "Fake Plastic Trees", and the
/// strip and the popover both showed it until the song was added to the library. Nothing on
/// an image says which song it belongs to, but a cover that is the previous song's, for a song
/// from another album, is not this song's own. `PlayingTrack.sleeve()` shows none instead,
/// and the strip and popover draw their placeholder.
///
/// Only Music's answer for a catalog track the user doesn't have is checked. A library
/// track's artwork has never been seen wrong, and two library songs from different albums can
/// share a cover (a single and its album), so refusing those would only cost.
final class SleeveHistory {

    static let shared = SleeveHistory()

    /// A cover, and the album of the song it was shown for
    struct Sleeve: Equatable {
        let fingerprint: SleeveFingerprint
        /// Nil when Music didn't say
        let album: String?
    }

    /// How many songs' covers are kept. Only the song before the current one is ever asked
    /// for; the rest are slack for a song whose notifications arrive out of turn.
    let capacity = 4

    /// Oldest first, one per song
    private var sleeves: [(song: String, sleeve: Sleeve)] = []

    /// The cover last shown for `song`, a persistent ID
    func sleeve(for song: String) -> Sleeve? {
        return sleeves.last(where: { $0.song == song })?.sleeve
    }

    /// `fingerprint` was shown for `song`. `album` is asked only for a song not already kept
    /// with one, since each ask is an Apple Event.
    func record(_ fingerprint: SleeveFingerprint, for song: String, album: () -> String?) {
        let knownAlbum = sleeve(for: song)?.album ?? album()
        sleeves.removeAll(where: { $0.song == song })
        sleeves.append((song: song, sleeve: Sleeve(fingerprint: fingerprint, album: knownAlbum)))
        if sleeves.count > capacity {
            sleeves.removeFirst(sleeves.count - capacity)
        }
    }

    /// Whether `fingerprint`, Music's cover for a song the user doesn't have, on `album`, is
    /// `previous` left over: the same cover, for a song from a different album.
    ///
    /// `album` is asked only when the covers match, because each ask is an Apple Event.
    static func isLeftOver(_ fingerprint: SleeveFingerprint, onAlbum album: () -> String?, from previous: Sleeve) -> Bool {
        guard fingerprint.isSameCover(as: previous.fingerprint) else { return false }
        return !mayShareCover(album(), previous.album)
    }

    /// Whether songs on these two albums could have the same cover: the same album, or one
    /// StarBar can't name. Two tracks of one album played in turn share a cover, so a match
    /// there says nothing; nor does one against an album Music didn't name. Folded as releases
    /// (`SongName.releaseName`), so a deluxe edition and the album count as one: calling them
    /// one by mistake only lets a left-over cover through, as before this check.
    static func mayShareCover(_ album: String?, _ otherAlbum: String?) -> Bool {
        let one = album.map(SongName.releaseName) ?? ""
        let other = otherAlbum.map(SongName.releaseName) ?? ""
        guard !one.isEmpty, !other.isEmpty else { return true }
        return one == other
    }

}

/// A cover shrunk to a 16 by 16 grid of colours, for telling whether two images are one cover.
///
/// The bytes can't be compared. Music holds the same album at different sizes (800 pixels on
/// a catalog track, 600 on the library copy, measured 2026-09-18) and a cover can be
/// re-encoded on its way, so two copies of one cover agree only once both are shrunk to the
/// same few cells. Two different covers almost never do.
struct SleeveFingerprint: Equatable {

    /// Cells along each side
    static let side = 16

    /// The largest mean difference between two fingerprints, from 0 to 1, at which they are
    /// taken for one cover. **A guess, not a measurement**: a cover against itself at another
    /// size or JPEG quality differs by under 0.02 in the tests, and different covers by
    /// tenths. Two near-plain covers of the same colour can come closer than this, at the cost
    /// of a placeholder for a catalog song that follows one. `PlayingTrack.sleeve()` logs every
    /// difference it measures, so the log is where to look before moving it.
    static let sameCoverTolerance = 0.05

    /// Red, green and blue of each cell, row by row, 0 to 255
    let samples: [UInt8]

    init?(image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(cgImage: cgImage)
    }

    init?(cgImage: CGImage) {
        // Drawn at four cells a side and then averaged, so that every pixel of the original
        // counts: drawn straight at 16 pixels, it would be sampled rather than averaged, and
        // two sizes of one cover sampled at different points.
        let side = SleeveFingerprint.side
        let block = 4
        let drawnSide = side * block
        var pixels = [UInt8](repeating: 0, count: drawnSide * drawnSide * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: drawnSide, height: drawnSide,
                                          bitsPerComponent: 8, bytesPerRow: drawnSide * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: drawnSide, height: drawnSide))
            return true
        }
        guard didDraw else { return nil }

        var samples = [UInt8](repeating: 0, count: side * side * 3)
        for row in 0..<side {
            for column in 0..<side {
                for channel in 0..<3 {
                    var total = 0
                    for y in 0..<block {
                        for x in 0..<block {
                            let pixel = (row * block + y) * drawnSide + column * block + x
                            total += Int(pixels[pixel * 4 + channel])
                        }
                    }
                    samples[(row * side + column) * 3 + channel] = UInt8(total / (block * block))
                }
            }
        }
        self.samples = samples
    }

    /// The mean difference between the two, from 0 (identical) to 1
    func difference(from other: SleeveFingerprint) -> Double {
        guard samples.count == other.samples.count, !samples.isEmpty else { return 1 }
        var total = 0
        for index in samples.indices {
            total += abs(Int(samples[index]) - Int(other.samples[index]))
        }
        return Double(total) / Double(samples.count * 255)
    }

    func isSameCover(as other: SleeveFingerprint) -> Bool {
        return difference(from: other) <= SleeveFingerprint.sameCoverTolerance
    }

}

/// The songs Music announced last, each kept as the player's record from its first
/// notification, so that the song before the current one can be found.
///
/// Kept by notification rather than by record: the record is replaced on every update,
/// several times a song, and telling whether two records are one song would cost an Apple
/// Event each time. The notification's identity costs nothing, and the record's persistent
/// ID is read only when the previous song is asked for, by which time the menu bar has
/// usually read it already.
struct RecentSongs<Record: AnyObject> {

    /// The current song, the one before it, and one more in case Music names a song two ways
    /// (it sends a persistent ID for some catalog tracks and not others)
    let capacity = 3

    /// Oldest first
    private(set) var songs: [(identity: String, record: Record)] = []

    /// Music announced `identity` (`PlayInfo.songIdentity`) with `record` playing. Nothing
    /// changes for another notification about the same song, nor for one with no record,
    /// whose song's next notification will bring one.
    mutating func musicAnnounced(_ identity: String, playing record: Record?) {
        guard songs.last?.identity != identity, let record = record else { return }
        songs.append((identity: identity, record: record))
        if songs.count > capacity {
            songs.removeFirst(songs.count - capacity)
        }
    }

    /// The most recently announced song whose ID, as `id` reads it, is known and isn't `song`
    func previous(before song: String, id: (Record) -> String?) -> Record? {
        for entry in songs.reversed() {
            if let other = id(entry.record), other != song {
                return entry.record
            }
        }
        return nil
    }

    /// `record` was playing when StarBar started. Music announces nothing at launch, so
    /// without this the first song after a launch had no song before it and its cover went
    /// unchecked: on 2026-11-03 "I Am Sky" showed *Insen*, the cover of "Aurora", which was
    /// playing when StarBar started. Nothing changes when nothing was playing.
    mutating func playingAtLaunch(_ record: Record?) {
        musicAnnounced(RecentSongs.launchIdentity, playing: record)
    }

    /// What the song playing at launch goes by. No notification names a song this way, so
    /// the first one about that song adds it again, which `previous(before:id:)` passes over.
    static var launchIdentity: String {
        return "(playing when StarBar started)"
    }

    mutating func forget() {
        songs.removeAll()
    }

}
