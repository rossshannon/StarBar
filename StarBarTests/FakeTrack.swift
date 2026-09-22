//
//  FakeTrack.swift
//  StarBarTests
//
//  A track that records what the app writes to it. The Scripting Bridge header declares
//  `iTunesTrack` as an Objective-C protocol of optional members, so an NSObject can play a
//  track without Music: every read answers from memory and every write is remembered.
//
//  The protocol's writes are `setRating(_:)` and the like, whose Objective-C selectors are
//  the same ones a Swift `var` setter would take, so the readable properties are computed
//  over private storage and only the protocol's methods change them.
//

import Foundation
@testable import StarBar

final class FakeTrack: NSObject, iTunesTrack {

    let name: String
    let artist: String
    let album: String
    let persistentID: String
    let databaseID: Int
    let duration: Double

    private var storedRating: Int
    private var storedRatingKind: iTunesERtK
    private var storedFavorited: Bool

    var rating: Int { return storedRating }
    var ratingKind: iTunesERtK { return storedRatingKind }
    var favorited: Bool { return storedFavorited }

    /// Every rating written, in order, so a test can see repeats and their order
    private(set) var ratingsWritten: [Int] = []
    private(set) var favoritesWritten: [Bool] = []
    var isPresent = true
    var objectClassCode: FourCharCode?

    init(name: String = "Song", artist: String = "Artist", album: String = "Album",
         persistentID: String = "0123456789ABCDEF", databaseID: Int = 1, duration: Double = 240,
         rating: Int = 0, ratingKind: iTunesERtK = .user, favorited: Bool = false) {
        self.name = name
        self.artist = artist
        self.album = album
        self.persistentID = persistentID
        self.databaseID = databaseID
        self.duration = duration
        self.storedRating = rating
        self.storedRatingKind = ratingKind
        self.storedFavorited = favorited
    }

    // MARK: iTunesTrack writes the app makes

    func setRating(_ rating: Int) {
        storedRating = rating
        storedRatingKind = .user
        ratingsWritten.append(rating)
    }

    func setFavorited(_ favorited: Bool) {
        storedFavorited = favorited
        favoritesWritten.append(favorited)
    }

    /// `iTunesTrack.scriptingClassCode` reads `objectClass` by key-value coding, which a real
    /// Scripting Bridge object answers. Tests can supply its class code; by default the
    /// fake answers nil instead of raising the exception an unknown KVC key would.
    override func value(forUndefinedKey key: String) -> Any? {
        if key == "objectClass", let code = objectClassCode {
            return NSAppleEventDescriptor(typeCode: code)
        }
        return nil
    }

    // MARK: SBObjectProtocol and iTunesGenericMethods

    /// A live Scripting Bridge object resolves to a copy; the fake is its own copy
    func get() -> Any! {
        return self
    }

    func exists() -> Bool {
        return isPresent
    }

}
