//
//  PlayerViewController.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-8-18.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import os
import Cocoa
import CoreImage

final class PlayerViewController: NSViewController {

    private let playerPanelViewController = PlayerPanelViewController()

    // back cover with blur effect
    private let backCoverImageView: MovableImageView = {
        let view = MovableImageView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.contentsGravity = CALayerContentsGravity.resizeAspectFill
        return view
    }()

    // normal cover
    private let coverImageView: MovableImageView = {
        let imageView = MovableImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    // Misc.
    private lazy var menuButtonMenu: NSMenu = {
        let menu = NSMenu()
        let about = NSMenuItem(title: "About StarBar", action: #selector(WindowManager.aboutMenuItemPressed(_:)), keyEquivalent: "")
        about.target = WindowManager.shared
        menu.addItem(about)
        let preferences = NSMenuItem(title: "Preferences…", action: #selector(WindowManager.preferencesMenuItemPressed(_:)), keyEquivalent: ",")
        preferences.target = WindowManager.shared
        menu.addItem(preferences)
        let showCurrentTrack = NSMenuItem(title: "Show Current Track", action: #selector(TrackAnnouncementController.showCurrentTrackMenuItemPressed(_:)), keyEquivalent: "")
        showCurrentTrack.target = TrackAnnouncementController.shared
        menu.addItem(showCurrentTrack)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit StarBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }()

    override func loadView() {
        self.view = NSView()
    }

}

extension PlayerViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addTrackingArea(NSTrackingArea(rect: view.bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))

        playerPanelViewController.delegate = self

        // V-StackView
        // - backCoverImageView & coverImageView
        // - playerInfoView

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stackView.alignment = .centerX
        stackView.spacing = 0

        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(coverImageView)
        NSLayoutConstraint.activate([
            coverImageView.widthAnchor.constraint(equalToConstant: 300),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor),
        ])

        backCoverImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backCoverImageView, positioned: .below, relativeTo: stackView)
        NSLayoutConstraint.activate([
            backCoverImageView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            backCoverImageView.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor),
            backCoverImageView.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor),
            backCoverImageView.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor),
        ])

        addChild(playerPanelViewController)
        playerPanelViewController.view.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(playerPanelViewController.view)
        NSLayoutConstraint.activate([
            playerPanelViewController.view.widthAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 1.0),
        ])
    }

}

extension PlayerViewController {

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        os_log("%{public}s[%{public}ld], %{public}s: mouseEntered", ((#file as NSString).lastPathComponent), #line, #function)

        playerPanelViewController.state = .control
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        os_log("%{public}s[%{public}ld], %{public}s: mouseEntered", ((#file as NSString).lastPathComponent), #line, #function)

        playerPanelViewController.state = .info
    }

}


extension PlayerViewController {

    func updateCurrentTrack(_ track: iTunesTrack?) {
        defer {
            view.needsLayout = true
            playerPanelViewController.updateCurrentTrack(track)
        }

        // update cover image
        guard let track = track else {
            coverImageView.image = nil
            backCoverImageView.layer?.contents = nil
            return
        }

        if let image = track.firstArtworkImage() {
            let transition = CATransition()
            transition.duration = 0.33
            transition.type = .fade
            transition.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            transition.isRemovedOnCompletion = true
            coverImageView.layer?.add(transition, forKey: nil)

            coverImageView.image = image
            backCoverImageView.layer?.contents = NSImage(size: coverImageView.frame.size, flipped: true) { rect -> Bool in
                let context = CIContext()
                guard let tiffData = image.tiffRepresentation, let ciImage = CIImage(data: tiffData),
                let clampFilter = CIFilter(name: "CIAffineClamp"),
                let gaussianBlur = CIFilter(name: "CIGaussianBlur") else {
                    return true
                }
                let extent = ciImage.extent

                clampFilter.setValue(ciImage, forKey: kCIInputImageKey)
                clampFilter.setValue(NSAffineTransform(transform: .identity), forKey: kCIInputTransformKey)
                guard let clampFilterOutput = clampFilter.outputImage else {
                    return true
                }

                gaussianBlur.setValue(clampFilterOutput, forKey: kCIInputImageKey)
                gaussianBlur.setValue(100, forKey: kCIInputRadiusKey)

                guard let outputImage = gaussianBlur.outputImage,
                let cgImage = context.createCGImage(outputImage, from: extent) else {
                    return true
                }

                let nsImage = NSImage(cgImage: cgImage, size: .zero)
                nsImage.draw(in: rect)

                return true
            }

        } else {
            coverImageView.image = nil
            backCoverImageView.layer?.contents = nil
        }
    }

}

// MARK: - PlayerPanelViewControllerDelegate
extension PlayerViewController: PlayerPanelViewControllerDelegate {

    func playerPanelViewController(_ playerPanelViewController: PlayerPanelViewController, menuButtonPressed button: NSButton) {
        os_log("%{public}s[%{public}ld], %{public}s: menuButtonPressed", ((#file as NSString).lastPathComponent), #line, #function)
        menuButtonMenu.popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: button.bounds.midY - 5), in: button)
    }

    func playerPanelViewController(_ playerPanelViewController: PlayerPanelViewController, listButtonPressed button: NSButton) {
        os_log("%{public}s[%{public}ld], %{public}s: listButtonPressed", ((#file as NSString).lastPathComponent), #line, #function)

    }

    func playerPanelViewController(_ playerPanelViewController: PlayerPanelViewController, backwardButtonPressed button: NSButton) {
        os_log("%{public}s[%{public}ld], %{public}s: backwardButtonPressed", ((#file as NSString).lastPathComponent), #line, #function)
        iTunesRadioStation.shared.backward()

    }

    func playerPanelViewController(_ playerPanelViewController: PlayerPanelViewController, forwardButtonPressed button: NSButton) {
        os_log("%{public}s[%{public}ld], %{public}s: forwardButtonPressed", ((#file as NSString).lastPathComponent), #line, #function)
        iTunesRadioStation.shared.forward()
    }

    func playerPanelViewController(_ playerPanelViewController: PlayerPanelViewController, playPauseButtonToggled button: NSButton) {
        os_log("%{public}s[%{public}ld], %{public}s: playPauseButtonToggled", ((#file as NSString).lastPathComponent), #line, #function)
        iTunesRadioStation.shared.playPause()
    }

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct PlayerViewController_Preview: PreviewProvider {

    // Live preview
    static var previews: some View {
        NSViewControllerPreview {
            let playerViewController = PlayerViewController()
            NotificationCenter.default.addObserver(forName: .iTunesPlayerDidUpdated, object: nil, queue: .main) { notification in
                playerViewController.updateCurrentTrack(iTunesPlayer.shared.currentTrack)
            }
            playerViewController.updateCurrentTrack(iTunesPlayer.shared.currentTrack)
            return playerViewController
        }.frame(width: 300, height: 800, alignment: .center)
    }

}

#endif
