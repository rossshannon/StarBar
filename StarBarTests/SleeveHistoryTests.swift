//
//  SleeveHistoryTests.swift
//  StarBarTests
//
//  Catching the previous song's cover left over on a catalog track: the fingerprints, the
//  rule and the record of which song came before. Pure, so it runs anywhere.
//

import XCTest
@testable import StarBar

final class SleeveHistoryTests: XCTestCase {

    // MARK: - Covers drawn for the tests

    /// A cover drawn `side` pixels square by `draw`, which works in 0 to 1 coordinates so one
    /// cover can be drawn at any size
    private func cover(side: Int, _ draw: (CGContext) -> Void) -> NSImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(side), y: CGFloat(side))
        draw(context)
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
    }

    /// Dark, with a red band and two pale circles, after a cover played before
    private func bends(side: Int) -> NSImage {
        return cover(side: side) { context in
            context.setFillColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.setFillColor(red: 0.85, green: 0.65, blue: 0.55, alpha: 1)
            context.fill(CGRect(x: 0.2, y: 0, width: 0.6, height: 0.9))
            context.setFillColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
            context.fill(CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.12))
            context.setFillColor(red: 0.95, green: 0.95, blue: 0.9, alpha: 1)
            context.fillEllipse(in: CGRect(x: 0.2, y: 0.12, width: 0.1, height: 0.1))
            context.fillEllipse(in: CGRect(x: 0.7, y: 0.08, width: 0.12, height: 0.12))
        }
    }

    /// Pale grey-blue with a dark horizon, the cover of the song that came next
    private func shore(side: Int) -> NSImage {
        return cover(side: side) { context in
            context.setFillColor(red: 0.74, green: 0.78, blue: 0.82, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.setFillColor(red: 0.2, green: 0.22, blue: 0.25, alpha: 1)
            context.fill(CGRect(x: 0, y: 0.3, width: 1, height: 0.04))
            context.setFillColor(red: 0.9, green: 0.9, blue: 0.88, alpha: 1)
            context.fill(CGRect(x: 0.1, y: 0.75, width: 0.5, height: 0.06))
        }
    }

    private func recompressed(_ image: NSImage, quality: Double) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])!
        return NSImage(data: data)!
    }

    private func fingerprint(_ image: NSImage) -> SleeveFingerprint {
        return SleeveFingerprint(image: image)!
    }

    // MARK: - Fingerprints

    func testOneCoverAtTwoSizesIsOneCover() {
        // Measured 2026-09-18: Music holds one album at 800 pixels on a catalog track and
        // 600 on the library copy
        let large = fingerprint(bends(side: 800)), small = fingerprint(bends(side: 600))
        XCTAssertLessThan(large.difference(from: small), 0.02)
        XCTAssertTrue(large.isSameCover(as: small))
    }

    func testOneCoverReencodedIsOneCover() {
        let original = bends(side: 600)
        let jpeg = fingerprint(recompressed(original, quality: 0.4))
        XCTAssertTrue(fingerprint(original).isSameCover(as: jpeg),
                      "differs by \(fingerprint(original).difference(from: jpeg))")
        XCTAssertTrue(fingerprint(bends(side: 800)).isSameCover(as: jpeg))
    }

    func testDifferentCoversAreToldApart() {
        let one = fingerprint(bends(side: 600)), other = fingerprint(shore(side: 600))
        XCTAssertGreaterThan(one.difference(from: other), 0.2)
        XCTAssertFalse(one.isSameCover(as: other))
    }

    func testAFingerprintIsTheSameEachTime() {
        XCTAssertEqual(fingerprint(shore(side: 640)), fingerprint(shore(side: 640)))
        XCTAssertEqual(fingerprint(shore(side: 640)).samples.count, SleeveFingerprint.side * SleeveFingerprint.side * 3)
        XCTAssertEqual(fingerprint(shore(side: 640)).difference(from: fingerprint(shore(side: 640))), 0)
    }

    // MARK: - The rule

    private lazy var theBends = SleeveHistory.Sleeve(fingerprint: fingerprint(bends(side: 600)), album: "The Bends")

    func testThePreviousSongsCoverForASongOnAnotherAlbumIsLeftOver() {
        // 2026-11-02: "Chain Home", on Finding Shore, came back with The Bends, the album
        // "Fake Plastic Trees" had just played from
        let given = fingerprint(bends(side: 800))
        XCTAssertTrue(SleeveHistory.isLeftOver(given, onAlbum: { "Finding Shore" }, from: theBends))
    }

    func testASongsOwnCoverIsNotLeftOver() {
        let given = fingerprint(shore(side: 800))
        XCTAssertFalse(SleeveHistory.isLeftOver(given, onAlbum: { "Finding Shore" }, from: theBends))
    }

    func testTheNextTrackOfOneAlbumMayShareItsCover() {
        // An Apple Music album played in order: every track has the album's cover
        let given = fingerprint(bends(side: 800))
        XCTAssertFalse(SleeveHistory.isLeftOver(given, onAlbum: { "The Bends" }, from: theBends))
        XCTAssertFalse(SleeveHistory.isLeftOver(given, onAlbum: { "The Bends (Deluxe Edition)" }, from: theBends),
                       "an edition of the album is the same release")
        XCTAssertFalse(SleeveHistory.isLeftOver(given, onAlbum: { "the bends" }, from: theBends))
    }

    func testAnAlbumMusicDidntNameIsNoEvidence() {
        let given = fingerprint(bends(side: 800))
        XCTAssertFalse(SleeveHistory.isLeftOver(given, onAlbum: { nil }, from: theBends))
        XCTAssertFalse(SleeveHistory.isLeftOver(given, onAlbum: { "" }, from: theBends))
        let unnamed = SleeveHistory.Sleeve(fingerprint: theBends.fingerprint, album: nil)
        XCTAssertFalse(SleeveHistory.isLeftOver(given, onAlbum: { "Finding Shore" }, from: unnamed))
    }

    func testTheAlbumIsAskedOnlyWhenTheCoversMatch() {
        // Each ask is an Apple Event
        var asks = 0
        _ = SleeveHistory.isLeftOver(fingerprint(shore(side: 600)), onAlbum: { asks += 1; return "Finding Shore" }, from: theBends)
        XCTAssertEqual(asks, 0)
        _ = SleeveHistory.isLeftOver(fingerprint(bends(side: 600)), onAlbum: { asks += 1; return "Finding Shore" }, from: theBends)
        XCTAssertEqual(asks, 1)
    }

    // MARK: - What was shown

    func testAShownCoverIsKeptBySong() {
        let history = SleeveHistory()
        let bendsPrint = fingerprint(bends(side: 600)), shorePrint = fingerprint(shore(side: 600))
        history.record(bendsPrint, for: "A", album: { "The Bends" })
        history.record(shorePrint, for: "B", album: { "Finding Shore" })
        XCTAssertEqual(history.sleeve(for: "A"), SleeveHistory.Sleeve(fingerprint: bendsPrint, album: "The Bends"))
        XCTAssertEqual(history.sleeve(for: "B")?.album, "Finding Shore")
        XCTAssertNil(history.sleeve(for: "C"))
    }

    func testASongShownAgainIsNotAskedForItsAlbumAgain() {
        // The popover reads the cover on every update while it is open
        let history = SleeveHistory()
        var asks = 0
        let album: () -> String? = { asks += 1; return "The Bends" }
        history.record(fingerprint(bends(side: 600)), for: "A", album: album)
        history.record(fingerprint(bends(side: 600)), for: "A", album: album)
        XCTAssertEqual(asks, 1)
        // A cover Music put right replaces the one kept
        history.record(fingerprint(shore(side: 600)), for: "A", album: album)
        XCTAssertEqual(asks, 1)
        XCTAssertEqual(history.sleeve(for: "A")?.fingerprint, fingerprint(shore(side: 600)))
    }

    func testOnlyTheLastFewSongsAreKept() {
        let history = SleeveHistory()
        let sleeve = fingerprint(shore(side: 100))
        for song in 0..<(history.capacity + 2) {
            history.record(sleeve, for: "\(song)", album: { "Album" })
        }
        XCTAssertNil(history.sleeve(for: "0"))
        XCTAssertNil(history.sleeve(for: "1"))
        XCTAssertNotNil(history.sleeve(for: "2"))
        XCTAssertNotNil(history.sleeve(for: "\(history.capacity + 1)"))
    }

    // MARK: - Which song came before

    /// A player record with the persistent ID a read of it would give
    private final class Record {
        let id: String?
        init(_ id: String?) { self.id = id }
    }

    private func previous(_ songs: RecentSongs<Record>, before song: String) -> Record? {
        return songs.previous(before: song) { $0.id }
    }

    func testThePreviousSongIsTheOneAnnouncedBefore() {
        var songs = RecentSongs<Record>()
        let plasticTrees = Record("FPT"), chainHome = Record("CH")
        songs.musicAnnounced("1234", playing: plasticTrees)
        // The strip reads the cover inside the update, before the new song is announced
        XCTAssertTrue(previous(songs, before: "CH") === plasticTrees)
        songs.musicAnnounced("Chain Home|Tom Rogerson & Brian Eno|Finding Shore", playing: chainHome)
        XCTAssertTrue(previous(songs, before: "CH") === plasticTrees)
    }

    func testMoreNotificationsForOneSongKeepItsFirstRecord() {
        var songs = RecentSongs<Record>()
        let first = Record("FPT"), later = Record("FPT")
        songs.musicAnnounced("1234", playing: first)
        songs.musicAnnounced("1234", playing: later)
        songs.musicAnnounced("1234", playing: later)
        XCTAssertEqual(songs.songs.count, 1)
        XCTAssertTrue(previous(songs, before: "CH") === first)
    }

    func testANotificationWithNoRecordWaitsForTheNext() {
        var songs = RecentSongs<Record>()
        let plasticTrees = Record("FPT"), chainHome = Record("CH")
        songs.musicAnnounced("1234", playing: plasticTrees)
        songs.musicAnnounced("5678", playing: nil)
        songs.musicAnnounced("5678", playing: chainHome)
        XCTAssertEqual(songs.songs.map { $0.identity }, ["1234", "5678"])
        XCTAssertTrue(previous(songs, before: "CH") === plasticTrees)
    }

    func testOneSongNamedTwoWaysIsStillOneSong() {
        // Music sends a persistent ID for some catalog tracks and not others
        var songs = RecentSongs<Record>()
        let plasticTrees = Record("FPT")
        songs.musicAnnounced("1234", playing: plasticTrees)
        songs.musicAnnounced("Chain Home|Tom Rogerson & Brian Eno|Finding Shore", playing: Record("CH"))
        songs.musicAnnounced("5678", playing: Record("CH"))
        XCTAssertTrue(previous(songs, before: "CH") === plasticTrees)
    }

    func testARecordWhoseIDWontReadIsPassedOver() {
        var songs = RecentSongs<Record>()
        let plasticTrees = Record("FPT")
        songs.musicAnnounced("1234", playing: plasticTrees)
        songs.musicAnnounced("Gone|Artist|Album", playing: Record(nil))
        XCTAssertTrue(previous(songs, before: "CH") === plasticTrees)
    }

    func testNoSongBeforeTheFirst() {
        var songs = RecentSongs<Record>()
        XCTAssertNil(previous(songs, before: "CH"))
        songs.musicAnnounced("5678", playing: Record("CH"))
        XCTAssertNil(previous(songs, before: "CH"))
        songs.forget()
        XCTAssertTrue(songs.songs.isEmpty)
    }

    func testTheSongPlayingAtLaunchIsTheOneBeforeTheFirstAnnounced() {
        // Music announces nothing at launch: on 2026-11-03 "I Am Sky" showed the cover of
        // "Aurora", playing when StarBar started, and nothing checked it
        var songs = RecentSongs<Record>()
        let aurora = Record("AUR"), iAmSky = Record("SKY")
        songs.playingAtLaunch(aurora)
        XCTAssertTrue(previous(songs, before: "SKY") === aurora)
        songs.musicAnnounced("5678", playing: iAmSky)
        XCTAssertTrue(previous(songs, before: "SKY") === aurora)
    }

    func testTheLaunchSongAnnouncedLaterIsStillTheSongBefore() {
        // Paused and played again, it is announced under its own ID, a second entry for it
        var songs = RecentSongs<Record>()
        songs.playingAtLaunch(Record("AUR"))
        songs.musicAnnounced("1234", playing: Record("AUR"))
        songs.musicAnnounced("5678", playing: Record("SKY"))
        XCTAssertEqual(previous(songs, before: "SKY")?.id, "AUR")
    }

    func testNothingPlayingAtLaunchIsNoSong() {
        var songs = RecentSongs<Record>()
        songs.playingAtLaunch(nil)
        XCTAssertTrue(songs.songs.isEmpty)
        songs.musicAnnounced("5678", playing: Record("SKY"))
        XCTAssertNil(previous(songs, before: "SKY"))
    }

    func testOnlyTheLastFewSongsAreRemembered() {
        var songs = RecentSongs<Record>()
        for song in 0..<(songs.capacity + 3) {
            songs.musicAnnounced("\(song)", playing: Record("\(song)"))
        }
        XCTAssertEqual(songs.songs.count, songs.capacity)
        XCTAssertEqual(songs.songs.first?.identity, "3")
    }

}
