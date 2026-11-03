//
//  PlayInfo.swift
//  StarBar
//
//  Created by Cirno MainasuK on 2019-6-28.
//  Copyright © 2019 Cirno MainasuK. All rights reserved.
//

import Foundation

struct PlayInfo: Codable {
    // MARK: - basic meta
    let name: String?
    let artist: String?
    let album: String?
    let albumArtist: String?
    let composer: String?
    let grouping: String?
    let compilation: Int?
    let genre: String?

    let year: Int?
    let trackNumber: Int?
    let trackCount: Int?
    let discNumber: Int?
    let discCount: Int?
    // ?
    var rating: Int?            // be careful it's maybe computed rating
    let likeStatus: String?     // always "None"
    let playCount: Int?

    let albumRating: Int?
    let ratingComputed: Int?
    let albumRatingComputed: Int?
    

    // MARK: - additional meta
    let artworkCount: Int?
    
    // MARK: - player state
    let elapsedStr: String?
    let totalTime: Int?
    let playerState: PlayerState?

    // MARK: - sort info
    let displayLine0: String?
    let displayLine1: String?

    // MARK: - URI
    let persistentID: Int?
    let playlistPersistentID: Int?
    let libraryPersistentID: Int?
    let storeURL: String?
    let location: String?
    
    // MARK: - player history
    let playDate: Date?
    let skipCount: Int?
    let skipDate: Date?

    // MARK: - others
    let backButtonState: String?
}

extension PlayInfo {
    
    var notComputedRating: Int? {
        guard rating != nil else { return nil }
        return ratingComputed != 1 ? rating : 0
    }

    /// Which song this payload describes, for telling two songs apart at no cost.
    ///
    /// The persistent ID when Music sent one, otherwise `name|artist|album`: some Apple Music
    /// catalog tracks arrive with no ID field at all, and comparing a missing ID only ever
    /// compares nil with nil. Nil when the payload names no song. Not for matching against a
    /// track read through the Scripting Bridge, whose persistent ID is a hex string.
    ///
    /// **It lags.** It describes the last notification, and Music posts that after the song
    /// has changed, so anything read from the player in the meantime is about a newer song
    /// than this is. `RatingWriter` uses it only as a fallback for that reason. Two songs with
    /// the same three names and no ID also compare equal.
    var songIdentity: String? {
        if let persistentID = persistentID {
            return String(persistentID)
        }
        guard let name = name, !name.isEmpty else { return nil }
        return [name, artist ?? "", album ?? ""].joined(separator: "|")
    }

    /// Whether this payload says nothing `previous` didn't about what the player is doing:
    /// the same song, playing or paused as before, with the same rating. Music often sends
    /// one of these a moment after a song's first (`RepeatedUpdateHold`).
    ///
    /// The same song is the same persistent ID when both carry one, and otherwise the same
    /// name, artist and album, since Music sends some Apple Music songs with no ID at all and
    /// could send it in one of the two only. A stop, an unknown state or a payload that names
    /// no song is never a repeat, and nor is a changed rating, which may be the user's, made
    /// in Music. Anything else may differ, such as the artwork count.
    func repeats(_ previous: PlayInfo) -> Bool {
        guard let state = playerState, state == .playing || state == .paused, state == previous.playerState else { return false }
        guard rating == previous.rating, ratingComputed == previous.ratingComputed else { return false }
        if let id = persistentID, let previousID = previous.persistentID {
            return id == previousID
        }
        guard let name = name, !name.isEmpty else { return false }
        return name == previous.name && artist == previous.artist && album == previous.album
    }

}

extension PlayInfo {
    
    enum PlayerState: String, Codable {
        case paused = "Paused"
        case playing = "Playing"
        
        case unknown
        
        init(from decoder: Decoder) throws {
            self = try PlayerState(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }
    
}

extension PlayInfo: CustomStringConvertible {
    
    var description: String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(self)
            let jsonString = String(data: jsonData, encoding: .utf8).flatMap { String(describing: PlayInfo.self) + ": " + $0 }
            return jsonString ?? shortDescription
        } catch {
            return shortDescription
        }
    }
    
    var shortDescription: String {
        let playerState = self.playerState.flatMap { $0 != .unknown ? "\($0.rawValue): " : nil  } ?? ""
        return playerState + [
            ([trackNumber.flatMap { "[\(String($0))]" }, name].compactMap { $0 }.joined(separator: " ")),
            artist,
            [album, year.flatMap { "(\(String($0)))" }].compactMap { $0 }.joined(separator: " "),
            "\(notComputedRating ?? -1)"
        ].compactMap { $0 }.joined(separator: " | ")
    }
    
}

