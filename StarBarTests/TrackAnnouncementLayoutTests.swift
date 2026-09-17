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

        let topMargin = normal.height - frames.title.maxY
        let bottomMargin = frames.rating.minY
        XCTAssertEqual(topMargin, bottomMargin, accuracy: 0.5)
        XCTAssertGreaterThan(bottomMargin, 8, "the block must not hug the bottom edge")
    }

    func testRatingRowIsAlwaysLast() {
        let full = TrackAnnouncementLayout.frames(in: normal)
        let album = try! XCTUnwrap(full.album)
        XCTAssertLessThanOrEqual(full.rating.maxY, album.minY)
        XCTAssertEqual(full.rating.minX, full.title.minX)
        XCTAssertEqual(full.rating.height, 16)

        let bare = TrackAnnouncementLayout.frames(in: normal, hasArtist: false, hasAlbum: false)
        XCTAssertLessThanOrEqual(bare.rating.maxY, bare.title.minY)
        XCTAssertEqual(normal.height - bare.title.maxY, bare.rating.minY, accuracy: 0.5)
    }

    func testStarStylesForARating() {
        XCTAssertEqual(Stars.styles(forRating: 0), [.dot, .dot, .dot, .dot, .dot])
        XCTAssertEqual(Stars.styles(forRating: 70), [.full, .full, .full, .half, .dot])
        XCTAssertEqual(Stars.styles(forRating: 100), [.full, .full, .full, .full, .full])
        XCTAssertEqual(Stars.styles(forRating: 10), [.half, .dot, .dot, .dot, .dot])
        XCTAssertEqual(Stars.styles(forRating: 140), [.full, .full, .full, .full, .full], "clamped")
        XCTAssertEqual(Stars.styles(forRating: -20), [.dot, .dot, .dot, .dot, .dot], "clamped")
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

    func testMissingAlbumKeepsTheBlockCentred() {
        let frames = TrackAnnouncementLayout.frames(in: normal, hasArtist: true, hasAlbum: false)
        let artist = try! XCTUnwrap(frames.artist)

        XCTAssertNil(frames.album)
        XCTAssertLessThanOrEqual(frames.rating.maxY, artist.minY)
        XCTAssertEqual(normal.height - frames.title.maxY, frames.rating.minY, accuracy: 0.5)
    }

    func testMissingArtistPutsTheAlbumOnTheSecondLine() {
        let both = TrackAnnouncementLayout.frames(in: normal)
        let noArtist = TrackAnnouncementLayout.frames(in: normal, hasArtist: false, hasAlbum: true)

        XCTAssertNil(noArtist.artist)
        XCTAssertEqual(noArtist.album?.height, both.artist?.height)
        XCTAssertLessThan(noArtist.album!.maxY, noArtist.title.minY)
    }

    func testTitleAndRatingOnlyWhenBothDetailsAreMissing() {
        let frames = TrackAnnouncementLayout.frames(in: normal, hasArtist: false, hasAlbum: false)

        XCTAssertNil(frames.artist)
        XCTAssertNil(frames.album)
        let blockMidY = (frames.title.maxY + frames.rating.minY) / 2
        XCTAssertEqual(blockMidY, normal.height / 2, accuracy: 0.5)
    }

    func testFramesScaleWithWidthOnly() {
        let narrow = TrackAnnouncementLayout.frames(in: normal)
        let wide = TrackAnnouncementLayout.frames(in: CGSize(width: 2560, height: 96))

        XCTAssertEqual(wide.title.width, narrow.title.width + 1120)
        XCTAssertEqual(wide.title.minY, narrow.title.minY)
        XCTAssertEqual(wide.artist?.minY, narrow.artist?.minY)
        XCTAssertEqual(wide.album?.minY, narrow.album?.minY)
        XCTAssertEqual(wide.rating.minY, narrow.rating.minY)
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
        XCTAssertEqual(scaled.rating.height, 24)
        XCTAssertEqual(144 - scaled.title.maxY, scaled.rating.minY, accuracy: 0.5)
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

    func testEaseInOutIsSlowAtBothEnds() {
        XCTAssertEqual(TrackAnnouncementPlacement.easeInOut(0), 0)
        XCTAssertEqual(TrackAnnouncementPlacement.easeInOut(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(TrackAnnouncementPlacement.easeInOut(1), 1)
        XCTAssertLessThan(TrackAnnouncementPlacement.easeInOut(0.25), 0.25)
        XCTAssertGreaterThan(TrackAnnouncementPlacement.easeInOut(0.75), 0.75)
        XCTAssertEqual(TrackAnnouncementPlacement.easeInOut(2), 1)
        XCTAssertEqual(TrackAnnouncementPlacement.easeInOut(-1), 0)
    }

    // MARK: - Glass geometry

    func testGlassIsInsetFromTheSidesAndHangsBelowTheStrip() {
        let frame = TrackAnnouncementLayout.glassFrame(in: CGSize(width: 1280, height: 96))

        XCTAssertEqual(frame.minX, 16)
        XCTAssertEqual(frame.maxX, 1264)
        XCTAssertEqual(frame.minY, -24, "hangs below by the corner radius, so the bottom corners are never on screen")
        XCTAssertEqual(frame.maxY, 96, "flush with the strip's top")
        XCTAssertGreaterThanOrEqual(-frame.minY, TrackAnnouncementLayout.glassCornerRadius, "the overhang covers the whole bottom corner")
    }

    func testGlassScalesAndKeepsClearOfASideDock() {
        let frame = TrackAnnouncementLayout.glassFrame(in: CGSize(width: 2560, height: 192), scale: 2, leadingInset: 70, trailingInset: 0)

        XCTAssertEqual(frame.minX, 70 + 32)
        XCTAssertEqual(frame.maxX, 2560 - 32)
        XCTAssertEqual(frame.minY, -48)
        XCTAssertEqual(frame.height, 240)
        XCTAssertEqual(TrackAnnouncementLayout.glassFrame(in: CGSize(width: 40, height: 96), scale: 2).width, 0, "never a negative width")
    }

    func testOnlyTheGlassStyleAddsToTheContentInsets() {
        let classic = TrackAnnouncementLayout.contentInsets(for: .classic, scale: 2, leadingInset: 70, trailingInset: 5)
        XCTAssertEqual(classic.leading, 70)
        XCTAssertEqual(classic.trailing, 5)
        let blur = TrackAnnouncementLayout.contentInsets(for: .blur, scale: 2, leadingInset: 70, trailingInset: 5)
        XCTAssertEqual(blur.leading, 70)
        let glass = TrackAnnouncementLayout.contentInsets(for: .glass, scale: 2, leadingInset: 70, trailingInset: 5)
        XCTAssertEqual(glass.leading, 70 + 32, "the text stays inside the glass")
        XCTAssertEqual(glass.trailing, 5 + 32)
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
        XCTAssertEqual(preview.rating, 70)
        XCTAssertTrue(preview.isFavorited)
        XCTAssertEqual(preview.accessibilityLabel, "Now playing: Music Video by StarBar. 3½ stars, favourite")
    }

}
