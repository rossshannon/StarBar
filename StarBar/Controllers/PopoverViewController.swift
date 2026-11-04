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
        // A catalog track's cover came late, Apple's or Music's own once Apple had none: read
        // again, and `PlayingTrack.sleeve()` now answers with it
        NotificationCenter.default.addObserver(self, selector: #selector(PopoverViewController.iTunesPlayerDidUpdated(_:)), name: .appleMusicCoverDidLoad, object: nil)
        // Play was pressed with nothing loaded: say Music is opening, or has nothing to play
        NotificationCenter.default.addObserver(self, selector: #selector(PopoverViewController.musicStarterDidChange(_:)), name: .musicStarterDidChange, object: nil)
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

    @objc private func musicStarterDidChange(_ notification: Notification) {
        showCurrentTrack()
    }

    /// The artwork comes the same way as the strip's, the user's own copy first, then Apple's
    /// cover, and never the previous song's cover left over, so the two can't disagree. See
    /// `PlayingTrack.sleeve()`.
    private func showCurrentTrack() {
        let player = iTunesPlayer.shared
        let starter = MusicStarter.shared
        let starting = starter.status
        playerViewController.updateCurrentTrack(
            player.currentTrack, artwork: player.playing?.sleeve(),
            emptyState: .when(musicIsRunning: MusicStarter.musicIsRunning(), starting: starting, song: starter.song),
            isStarting: starting == .opening || starting == .starting)
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
