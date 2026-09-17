//
//  TrackAnnouncementLayoutTests.swift
//  StarBarTests
//
//  The announcement strip's geometry: Growl's Music Video numbers, scaling with the screen,
//  panel placement and the reduce-motion choice. Pure functions, so these run on any Mac
//  without Music.
//

import XCTest
@testable import StarBar

final class TrackAnnouncementLayoutTests: XCTestCase {

    private let normal = CGSize(width: 1440, height: 96)

    // MARK: - Frames

    func testArtworkMatchesGrowlAtScaleOne() {
        let frames = TrackAnnouncementLayout.frames(in: normal)

        XCTAssertEqual(frames.artwork, CGRect(x: 8, y: 8, width: 80, height: 80))
    }

    func testTextStartsAfterTheArtworkAndItsGap() {
        let frames = TrackAnnouncementLayout.frames(in: normal)

        XCTAssertEqual(frames.title.minX, 8 + 80 + 16)
        XCTAssertEqual(frames.title.width, 1440 - 104 - 16)
        XCTAssertEqual(frames.title.height, 20)
    }

    func testTextBlockIsCentredVertically() {
        let frames = TrackAnnouncementLayout.frames(in: normal)
        let album = try! XCTUnwrap(frames.album)

        let topMargin = normal.height - frames.title.maxY
        let bottomMargin = album.minY
        XCTAssertEqual(topMargin, bottomMargin, accuracy: 0.5)
        XCTAssertGreaterThan(bottomMargin, 12, "the text must not hug the bottom edge")
    }

    func testDetailLinesSitBelowTheTitleWithoutOverlapping() {
        let frames = TrackAnnouncementLayout.frames(in: normal)
        let artist = try! XCTUnwrap(frames.artist)
        let album = try! XCTUnwrap(frames.album)

        XCTAssertLessThanOrEqual(artist.maxY, frames.title.minY)
        XCTAssertLessThanOrEqual(album.maxY, artist.minY)
        XCTAssertGreaterThanOrEqual(album.minY, 0)
        XCTAssertEqual(artist.width, frames.title.width)
    }

    func testMissingAlbumKeepsTheTwoLinesCentred() {
        let frames = TrackAnnouncementLayout.frames(in: normal, hasArtist: true, hasAlbum: false)
        let artist = try! XCTUnwrap(frames.artist)

        XCTAssertNil(frames.album)
        XCTAssertEqual(normal.height - frames.title.maxY, artist.minY, accuracy: 0.5)
    }

    func testMissingArtistPutsTheAlbumOnTheSecondLine() {
        let both = TrackAnnouncementLayout.frames(in: normal)
        let noArtist = TrackAnnouncementLayout.frames(in: normal, hasArtist: false, hasAlbum: true)

        XCTAssertNil(noArtist.artist)
        XCTAssertEqual(noArtist.album?.height, both.artist?.height)
        XCTAssertLessThan(noArtist.album!.maxY, noArtist.title.minY)
    }

    func testTitleAloneIsCentredWhenBothDetailsAreMissing() {
        let frames = TrackAnnouncementLayout.frames(in: normal, hasArtist: false, hasAlbum: false)

        XCTAssertNil(frames.artist)
        XCTAssertNil(frames.album)
        XCTAssertEqual(frames.title.midY, normal.height / 2, accuracy: 0.5)
    }

    func testFramesScaleWithWidthOnly() {
        let narrow = TrackAnnouncementLayout.frames(in: normal)
        let wide = TrackAnnouncementLayout.frames(in: CGSize(width: 2560, height: 96))

        XCTAssertEqual(wide.title.width, narrow.title.width + 1120)
        XCTAssertEqual(wide.title.minY, narrow.title.minY)
        XCTAssertEqual(wide.artist?.minY, narrow.artist?.minY)
        XCTAssertEqual(wide.album?.minY, narrow.album?.minY)
        XCTAssertEqual(wide.artwork, narrow.artwork)
    }

    func testContentKeepsClearOfASideDock() {
        let frames = TrackAnnouncementLayout.frames(in: normal, leadingInset: 70, trailingInset: 30)

        XCTAssertEqual(frames.artwork.minX, 70 + 8)
        XCTAssertEqual(frames.title.minX, 70 + 8 + 80 + 16)
        XCTAssertEqual(frames.title.maxX, 1440 - 30 - 16)
    }

    // MARK: - Scaling with the screen

    func testScaleIsOneUpToTheReferenceHeightAndCapped() {
        XCTAssertEqual(TrackAnnouncementLayout.scale(forScreenHeight: 800), 1)
        XCTAssertEqual(TrackAnnouncementLayout.scale(forScreenHeight: 1000), 1)
        XCTAssertEqual(TrackAnnouncementLayout.scale(forScreenHeight: 1440), 1.44, accuracy: 0.001)
        XCTAssertEqual(TrackAnnouncementLayout.scale(forScreenHeight: 5000), 2)
    }

    func testEverythingGrowsWithTheScale() {
        let scaled = TrackAnnouncementLayout.frames(in: CGSize(width: 2160, height: 144), scale: 1.5)

        XCTAssertEqual(scaled.artwork, CGRect(x: 12, y: 12, width: 120, height: 120))
        XCTAssertEqual(scaled.title.minX, 12 + 120 + 24)
        XCTAssertEqual(scaled.title.height, 30)
        XCTAssertEqual(scaled.artist?.height, 24)
        XCTAssertEqual(scaled.title.width, 2160 - 156 - 24)
        let album = try! XCTUnwrap(scaled.album)
        XCTAssertEqual(144 - scaled.title.maxY, album.minY, accuracy: 0.5)
    }

    // MARK: - Artwork scaling

    func testSquareArtworkFillsTheSlot() {
        let slot = CGRect(x: 8, y: 8, width: 80, height: 80)
        let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: CGSize(width: 600, height: 600), in: slot)

        XCTAssertEqual(rect, slot)
    }

    func testWideArtworkIsLetterboxedAndCentred() {
        let slot = CGRect(x: 8, y: 8, width: 80, height: 80)
        let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: CGSize(width: 600, height: 300), in: slot)

        XCTAssertEqual(rect.width, 80)
        XCTAssertEqual(rect.height, 40)
        XCTAssertEqual(rect.midY, slot.midY)
        XCTAssertEqual(rect.minX, slot.minX)
    }

    func testSmallArtworkIsNeverScaledUp() {
        let slot = CGRect(x: 8, y: 8, width: 80, height: 80)
        let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: CGSize(width: 40, height: 40), in: slot)

        XCTAssertEqual(rect.size, CGSize(width: 40, height: 40))
        XCTAssertEqual(rect.midX, slot.midX)
        XCTAssertEqual(rect.midY, slot.midY)
    }

    // MARK: - Panel placement

    func testPanelRestsAboveABottomDock() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let frame = TrackAnnouncementPlacement.panelFrame(screenFrame: screen, visibleFrame: visible)

        XCTAssertEqual(frame.minY, 70)
        XCTAssertEqual(frame.width, 1440)
        XCTAssertEqual(frame.height, 96)
        XCTAssertEqual(frame.minX, 0)
    }

    func testPanelRunsBehindASideDock() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let leftDock = CGRect(x: 70, y: 0, width: 1370, height: 875)
        let left = TrackAnnouncementPlacement.panelFrame(screenFrame: screen, visibleFrame: leftDock)
        XCTAssertEqual(left.minX, 0, "the strip spans the whole width; the Dock draws over it")
        XCTAssertEqual(left.width, 1440)
        XCTAssertEqual(left.minY, 0)

        let rightDock = CGRect(x: 0, y: 0, width: 1370, height: 875)
        let right = TrackAnnouncementPlacement.panelFrame(screenFrame: screen, visibleFrame: rightDock)
        XCTAssertEqual(right.maxX, 1440)
    }

    func testPanelKeepsASecondDisplaysOrigin() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: 200, width: 1920, height: 1055)
        let frame = TrackAnnouncementPlacement.panelFrame(screenFrame: screen, visibleFrame: visible)

        XCTAssertEqual(frame.minX, -1920)
        XCTAssertEqual(frame.minY, 200)
        XCTAssertEqual(frame.width, 1920)
    }

    func testPanelHeightScalesToWholePoints() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(TrackAnnouncementPlacement.panelFrame(screenFrame: screen, visibleFrame: screen, scale: 1.5).height, 144)
        XCTAssertEqual(TrackAnnouncementPlacement.panelFrame(screenFrame: screen, visibleFrame: screen, scale: 1.44).height, 139)
        XCTAssertEqual(TrackAnnouncementPlacement.stripOrigin(shown: false, scale: 1.44).y, -139)
    }

    func testStripOrigins() {
        XCTAssertEqual(TrackAnnouncementPlacement.stripOrigin(shown: true), .zero)
        XCTAssertEqual(TrackAnnouncementPlacement.stripOrigin(shown: false), CGPoint(x: 0, y: -96))
        XCTAssertEqual(TrackAnnouncementPlacement.stripOrigin(shown: false, scale: 2), CGPoint(x: 0, y: -192))
    }

    func testReduceMotionSelectsFade() {
        XCTAssertEqual(TrackAnnouncementPlacement.transition(reduceMotion: false), .slide)
        XCTAssertEqual(TrackAnnouncementPlacement.transition(reduceMotion: true), .fade)
    }

    // MARK: - Preview sample

    func testPreviewHasSomethingToShow() {
        let preview = TrackAnnouncement.preview

        XCTAssertFalse(preview.title.isEmpty)
        XCTAssertFalse(preview.artist.isEmpty)
        XCTAssertFalse(preview.album.isEmpty)
        XCTAssertEqual(preview.accessibilityLabel, "Now playing: Music Video by StarBar")
    }

}
