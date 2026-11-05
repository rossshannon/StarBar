//
//  PlayerPlaceholderView.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-04.
//

import Cocoa

/// What the player popover shows in the artwork's square when there is no artwork: a quiet
/// rounded square with a music note, and, when Music has no song at all, a line saying so and
/// what the play button will do.
///
/// Without it the popover was a blank square of its own blurred background over the
/// transport controls, which read as broken rather than as "nothing is playing".
final class PlayerPlaceholderView: NSView {

    /// The note's size in the 300 point square
    static let notePointSize: CGFloat = 72

    private let noteView: NSImageView = {
        let view = NSImageView()
        let configuration = NSImage.SymbolConfiguration(pointSize: PlayerPlaceholderView.notePointSize, weight: .light)
        view.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        view.contentTintColor = .tertiaryLabelColor
        view.imageScaling = .scaleNone
        view.setAccessibilityElement(false)
        return view
    }()

    private let titleField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        field.textColor = .secondaryLabelColor
        field.alignment = .center
        return field
    }()

    private let detailField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        field.textColor = .tertiaryLabelColor
        field.alignment = .center
        // A long song name wraps, and past three lines ends in an ellipsis
        field.maximumNumberOfLines = 3
        field.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.preferredMaxLayoutWidth = 240
        return field
    }()

    private lazy var textStack: NSStackView = {
        let stack = NSStackView(views: [titleField, detailField])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        return stack
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _init()
    }

    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        _init()
    }

    private func _init() {
        wantsLayer = true
        layer?.cornerRadius = PlayerViewController.artworkCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        let stack = NSStackView(views: [noteView, textStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            trailingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 24),
        ])
        show(nil)
    }

    /// A fill that suits the popover's material in light and dark alike, redrawn when the
    /// appearance changes
    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }

    override var wantsUpdateLayer: Bool {
        return true
    }

    /// Show `text` under the note, or the note on its own when nil: a song with no artwork
    func show(_ text: PopoverEmptyState?) {
        textStack.isHidden = text == nil
        titleField.stringValue = text?.title ?? ""
        detailField.stringValue = PlayerPlaceholderView.keepingLastWordsTogether(text?.detail ?? "")
        detailField.isHidden = text?.detail.isEmpty ?? true
    }

    /// `text` with its last space made a no-break space, so that a line that wraps never ends
    /// on one word alone: "Press play for “Veridis Quo” by Daft Punk." left "Punk." on a line
    /// of its own (2026-11-05)
    static func keepingLastWordsTogether(_ text: String) -> String {
        guard let space = text.range(of: " ", options: .backwards) else { return text }
        return text.replacingCharacters(in: space, with: "\u{00A0}")
    }

}
