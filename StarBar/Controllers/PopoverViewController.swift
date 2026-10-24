//
//  PopoverViewController.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-8-17.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Cocoa

/// The player popover's content: the artwork, title and transport controls.
///
/// When the popover is dragged off the menu bar it becomes a detached window with the
/// system's own close button. An earlier version hid that button by reaching into the
/// private `NSPopoverFrame` class and drew its own; the private class changes between
/// macOS releases, so the system button stays.
final class PopoverViewController: NSViewController {

    private let playerViewController = PlayerViewController()

    override func loadView() {
        self.view = NSView()
    }
}

extension PopoverViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(playerViewController)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerViewController.view)

        NSLayoutConstraint.activate([
            playerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(PopoverViewController.iTunesPlayerDidUpdated(_:)), name: .iTunesPlayerDidUpdated, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        showCurrentTrack()
    }

}

extension PopoverViewController {

    @objc private func iTunesPlayerDidUpdated(_ notification: Notification) {
        showCurrentTrack()
    }

    /// The artwork comes from the same track the strip reads it from, the user's own copy
    /// first, so the two can't disagree. See `PlayingTrack.artworkTrack`.
    private func showCurrentTrack() {
        let player = iTunesPlayer.shared
        playerViewController.updateCurrentTrack(player.currentTrack, artworkFrom: player.playing?.artworkTrack)
    }

}

#if canImport(SwiftUI) && DEBUG
import SwiftUI

@available(macOS 10.15.0, *)
struct PopoverViewController_Preview: PreviewProvider {

    static var previews: some View {
        NSViewControllerPreview {
            return PopoverViewController()
        }
    }

}

#endif
