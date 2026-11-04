//
//  PopoverEmptyState.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-04.
//

import Foundation

/// What the player popover says in the artwork's square while Music has no song: that nothing
/// is playing, and what the play button will do about it.
///
/// "Not Playing" is what macOS's own Now Playing says for the same thing.
struct PopoverEmptyState: Equatable {

    let title: String
    let detail: String

    static let title = "Not Playing"

    /// - Parameters:
    ///   - musicIsRunning: whether Music is running, with no Apple Event
    ///   - starting: what pressing play has set going (`MusicStarter`)
    static func when(musicIsRunning: Bool, starting: MusicStarter.Status) -> PopoverEmptyState {
        switch starting {
        case .opening:
            return PopoverEmptyState(title: title, detail: "Opening Music…")
        case .starting:
            return PopoverEmptyState(title: title, detail: "Starting Music…")
        case .nothingToPlay where musicIsRunning:
            return PopoverEmptyState(title: title, detail: "Music has nothing queued. Press play to choose something in Music.")
        case .idle, .nothingToPlay:
            return PopoverEmptyState(title: title, detail: musicIsRunning ? "Press play to start Music." : "Press play to open Music.")
        }
    }

}
