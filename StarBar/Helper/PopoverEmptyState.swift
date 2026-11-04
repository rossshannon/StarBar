//
//  PopoverEmptyState.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-04.
//

import Foundation

/// What the player popover says in the artwork's square while Music has no song: that nothing
/// is playing, and what the play button will do about it, naming the song it would start so
/// that pressing it is never a surprise.
///
/// "Not Playing" is what macOS's own Now Playing says for the same thing.
struct PopoverEmptyState: Equatable {

    let title: String
    let detail: String

    static let title = "Not Playing"

    /// - Parameters:
    ///   - musicIsRunning: whether Music is running, with no Apple Event
    ///   - starting: what pressing play has set going (`MusicStarter`)
    ///   - song: the song a press starts (`MusicStarter.song`), or nil when it would bring
    ///     Music forward instead
    static func when(musicIsRunning: Bool, starting: MusicStarter.Status, song: LastMusicSong?) -> PopoverEmptyState {
        let detail: String
        switch starting {
        case .opening:
            detail = "Opening Music…"
        case .starting:
            detail = song.map { "Starting \($0.displayName)…" } ?? "Starting Music…"
        case .couldNotPlay where musicIsRunning:
            detail = "Music couldn\u{2019}t play that song. Press play to choose something in Music."
        case .idle, .couldNotPlay:
            if let song = song {
                detail = "Press play for \(song.displayName)."
            } else {
                detail = musicIsRunning ? "Press play to choose something in Music." : "Press play to open Music."
            }
        }
        return PopoverEmptyState(title: title, detail: detail)
    }

}
