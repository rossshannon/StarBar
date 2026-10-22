//
//  AboutViewController.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-7-2.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa

final class AboutViewController: NSViewController {

    static let copyright = "© 2025–2026 Ross Shannon"
    static let repositoryURL = URL(string: "https://github.com/rossshannon/StarBar")!
    static let issuesURL = URL(string: "https://github.com/rossshannon/StarBar/issues")!
    static let upstreamURL = URL(string: "https://github.com/MainasuK/Song-Rating")!

    private static let contentWidth: CGFloat = 300

    lazy var visualEffectBackgroundView: NSVisualEffectView = {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .underWindowBackground
        visualEffectView.isEmphasized = true
        visualEffectView.state = .active
        return visualEffectView
    }()

    lazy var iconImageView: NSImageView = {
        let imageView = NSImageView(image: NSApp.applicationIconImage)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("StarBar app icon")
        return imageView
    }()

    lazy var titleTextField: NSTextField = {
        let textField = NSTextField(labelWithString: String.infoValue(for: "CFBundleName") ?? "StarBar")
        textField.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        return textField
    }()

    lazy var versionTextField: NSTextField = {
        let version = String.infoValue(for: "CFBundleShortVersionString") ?? "NA"
        let build = String.infoValue(for: "CFBundleVersion") ?? "NA"
        let textField = NSTextField(labelWithString: "Version \(version) (\(build))")
        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        textField.textColor = .secondaryLabelColor
        // Selectable, so the version can be copied into a bug report
        textField.isSelectable = true
        return textField
    }()

    lazy var taglineTextField: NSTextField = {
        let textField = NSTextField(wrappingLabelWithString: "Star ratings and favourites for Music, right from the menu bar.")
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.alignment = .center
        textField.preferredMaxLayoutWidth = AboutViewController.contentWidth
        return textField
    }()

    lazy var githubButton: NSButton = {
        let button = NSButton(title: "GitHub", target: self, action: #selector(AboutViewController.githubButtonPressed(_:)))
        button.bezelStyle = .rounded
        return button
    }()

    lazy var contactMeButton: NSButton = {
        let button = NSButton(title: "Report a Problem", target: self, action: #selector(AboutViewController.contactMeButtonPressed(_:)))
        button.bezelStyle = .rounded
        return button
    }()

    lazy var copyrightTextField: NSTextField = {
        return AboutViewController.footnoteLabel(AboutViewController.copyright)
    }()

    // One attributed line rather than labels around a button, whose padding left wide gaps by the link
    lazy var creditTextField: NSTextField = {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AboutViewController.footnoteFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let credit = NSMutableAttributedString(string: "Uses elements of ", attributes: attributes)
        var linkAttributes = attributes
        linkAttributes[.link] = AboutViewController.upstreamURL
        credit.append(NSAttributedString(string: "Song-Rating", attributes: linkAttributes))
        credit.append(NSAttributedString(string: " by Cirno MainasuK", attributes: attributes))

        let textField = NSTextField(labelWithAttributedString: credit)
        // A link in a label is only clickable when the label is selectable and allows attributed editing
        textField.isSelectable = true
        textField.allowsEditingTextAttributes = true
        return textField
    }()

    lazy var licenseButton: NSButton = {
        return AboutViewController.linkButton("MIT Licence", target: self, action: #selector(AboutViewController.licenseButtonPressed(_:)))
    }()

    override func loadView() {
        self.view = NSView()
    }

}

extension AboutViewController {

    private static let footnoteFont = NSFont.systemFont(ofSize: 10)

    private static func footnoteLabel(_ string: String) -> NSTextField {
        let textField = NSTextField(labelWithString: string)
        textField.font = footnoteFont
        textField.textColor = .secondaryLabelColor
        return textField
    }

    private static func linkButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: footnoteFont,
            .foregroundColor: NSColor.linkColor,
        ])
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

}

extension AboutViewController {

    func setupWindow() {
        view.window?.styleMask.remove(.resizable)
        view.window?.styleMask.remove(.miniaturizable)
        view.window?.styleMask.insert(.fullSizeContentView)
        view.window?.titleVisibility = .hidden
        view.window?.titlebarAppearsTransparent = true
        view.window?.isOpaque = false
        view.window?.isMovableByWindowBackground = true
    }

    @objc func contactMeButtonPressed(_ sender: NSButton) {
        NSWorkspace.shared.open(AboutViewController.issuesURL)
    }

    @objc func githubButtonPressed(_ sender: NSButton) {
        NSWorkspace.shared.open(AboutViewController.repositoryURL)
    }

    // The bundled LICENSE carries Song-Rating's original MIT notice, which the licence requires every copy to keep
    @objc func licenseButtonPressed(_ sender: NSButton) {
        guard let window = view.window,
              let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            NSWorkspace.shared.open(AboutViewController.repositoryURL.appendingPathComponent("blob/main/LICENSE"))
            return
        }

        // Narrower than the About window, so the sheet doesn't hang over its sides
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 260, height: 240)
        scrollView.borderType = .bezelBorder
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.font = NSFont.systemFont(ofSize: 11)
            textView.textContainerInset = NSSize(width: 6, height: 6)
            textView.string = text
        }

        let alert = NSAlert()
        alert.messageText = "MIT Licence"
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "OK")
        alert.layout()
        // The text view lays out scrolled a little way down; start at the first copyright line
        scrollView.documentView?.scroll(.zero)
        alert.beginSheetModal(for: window)
    }

}

extension AboutViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "About StarBar"

        visualEffectBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(visualEffectBackgroundView)
        NSLayoutConstraint.activate([
            visualEffectBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            visualEffectBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            visualEffectBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            visualEffectBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let buttonStackView = NSStackView(views: [githubButton, contactMeButton])
        buttonStackView.orientation = .horizontal
        buttonStackView.spacing = 8

        let footerStackView = NSStackView(views: [copyrightTextField, creditTextField, licenseButton])
        footerStackView.orientation = .vertical
        footerStackView.alignment = .centerX
        footerStackView.spacing = 2

        let stackView = NSStackView(views: [iconImageView, titleTextField, versionTextField, taglineTextField, buttonStackView, footerStackView])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 4
        stackView.setCustomSpacing(10, after: iconImageView)
        stackView.setCustomSpacing(12, after: versionTextField)
        stackView.setCustomSpacing(18, after: taglineTextField)
        stackView.setCustomSpacing(20, after: buttonStackView)

        // Leaves the title bar's traffic lights clear of the icon
        let titleBarHeight: CGFloat = 28
        stackView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectBackgroundView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: visualEffectBackgroundView.topAnchor, constant: titleBarHeight),
            stackView.leadingAnchor.constraint(equalTo: visualEffectBackgroundView.leadingAnchor, constant: 30),
            visualEffectBackgroundView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 30),
            visualEffectBackgroundView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 18),
            stackView.widthAnchor.constraint(equalToConstant: AboutViewController.contentWidth),
            iconImageView.widthAnchor.constraint(equalToConstant: 112),
            iconImageView.heightAnchor.constraint(equalToConstant: 112),
            githubButton.widthAnchor.constraint(equalTo: contactMeButton.widthAnchor),
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.center()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupWindow()
    }

}

extension String {

    fileprivate static func infoValue(for key: String) -> String? {
        return Bundle.main.infoDictionary?[key] as? String
    }

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(OSX 10.15.0, *)
struct AboutViewController_Preview: PreviewProvider {

    static var previews: some View {
        NSViewControllerPreview {
            return AboutViewController()
        }
    }

}

#endif
