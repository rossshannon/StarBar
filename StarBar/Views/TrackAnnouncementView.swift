//
//  TrackAnnouncementView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Cocoa

/// The announcement strip: a translucent black band with the artwork on the left and the
/// title, artist and album in white, drawn the way Growl's Music Video view drew them.
final class TrackAnnouncementView: NSView {

    var announcement: TrackAnnouncement {
        didSet {
            needsDisplay = true
            setAccessibilityLabel(announcement.accessibilityLabel)
        }
    }

    /// 0.6 normally; 1 when Reduce Transparency is on
    var backgroundAlpha: CGFloat = TrackAnnouncementLayout.backgroundAlpha {
        didSet { needsDisplay = true }
    }

    /// How much bigger than Growl's 1280 by 800 design to draw, set from the screen
    var scale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    /// Space at the left and right the content keeps clear: a Dock at the side that the
    /// strip's background runs behind
    var leadingInset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var trailingInset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init(announcement: TrackAnnouncement, frame: NSRect = .zero) {
        self.announcement = announcement
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(announcement.accessibilityLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(backgroundAlpha).setFill()
        bounds.fill()

        let frames = TrackAnnouncementLayout.frames(
            in: bounds.size,
            scale: scale,
            leadingInset: leadingInset,
            trailingInset: trailingInset,
            hasArtist: !announcement.artist.isEmpty,
            hasAlbum: !announcement.album.isEmpty
        )
        drawArtwork(in: frames.artwork)
        draw(announcement.title, in: frames.title, font: NSFont.boldSystemFont(ofSize: TrackAnnouncementLayout.titleFontSize * scale))
        let detailFont = NSFont.messageFont(ofSize: TrackAnnouncementLayout.detailFontSize * scale)
        if let artistRect = frames.artist {
            draw(announcement.artist, in: artistRect, font: detailFont)
        }
        if let albumRect = frames.album {
            draw(announcement.album, in: albumRect, font: detailFont)
        }
    }

    private func drawArtwork(in slot: NSRect) {
        if let artwork = announcement.artwork, artwork.size.width > 0, artwork.size.height > 0 {
            let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: artwork.size, in: slot)
            NSGraphicsContext.current?.imageInterpolation = .high
            artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            // No artwork: a quiet square with a music note, so the slot never looks broken
            NSColor.white.withAlphaComponent(0.12).setFill()
            slot.fill()
            if let note = TrackAnnouncementView.placeholderImage {
                // Drawn at 36 points in an 80 point slot at scale 1, and in proportion above
                let noteSize = CGSize(width: note.size.width * scale, height: note.size.height * scale)
                let rect = TrackAnnouncementLayout.artworkDrawingRect(imageSize: noteSize, in: slot)
                note.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.9)
            }
        }
    }

    private static let placeholderImage: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        symbol.isTemplate = true
        return symbol.withTintColor(.white)
    }()

    private func draw(_ text: String, in rect: NSRect, font: NSFont) {
        guard !text.isEmpty else { return }
        let shadow = NSShadow()
        shadow.shadowOffset = CGSize(
            width: TrackAnnouncementLayout.shadowOffset.width * scale,
            height: TrackAnnouncementLayout.shadowOffset.height * scale
        )
        shadow.shadowBlurRadius = TrackAnnouncementLayout.shadowBlurRadius * scale
        shadow.shadowColor = NSColor.black
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

}
