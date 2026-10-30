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
    let mediaKind: iTunesEMdK
    let playedCount: Int

    private var storedRating: Int
    private var storedRatingKind: iTunesERtK
    private var storedFavorited: Bool

    var rating: Int {
        whenRead?()
        return storedRating
    }
    var ratingKind: iTunesERtK {
        ratingKindReads += 1
        return storedRatingKind
    }
    var favorited: Bool {
        whenRead?()
        return storedFavorited
    }

    /// How many times the rating's kind was read, each an Apple Event to a real Music
    private(set) var ratingKindReads = 0

    /// Every rating written, in order, so a test can see repeats and their order
    private(set) var ratingsWritten: [Int] = []
    private(set) var favoritesWritten: [Bool] = []
    var isPresent = true
    var objectClassCode: FourCharCode?
    /// Runs as the rating or heart is read, and as either is written, the way Music's
    /// failure reaches `iTunesRadioStation.eventDidFail` inside the call that sent the event
    var whenRead: (() -> Void)?
    var whenWritten: (() -> Void)?

    init(name: String = "Song", artist: String = "Artist", album: String = "Album",
         persistentID: String = "0123456789ABCDEF", databaseID: Int = 1, duration: Double = 240,
         rating: Int = 0, ratingKind: iTunesERtK = .user, favorited: Bool = false,
         mediaKind: iTunesEMdK = .music, playedCount: Int = 0) {
        self.name = name
        self.artist = artist
        self.album = album
        self.persistentID = persistentID
        self.databaseID = databaseID
        self.duration = duration
        self.mediaKind = mediaKind
        self.playedCount = playedCount
        self.storedRating = rating
        self.storedRatingKind = ratingKind
        self.storedFavorited = favorited
    }

    // MARK: iTunesTrack writes the app makes

    func setRating(_ rating: Int) {
        storedRating = rating
        storedRatingKind = .user
        ratingsWritten.append(rating)
        whenWritten?()
    }

    func setFavorited(_ favorited: Bool) {
        storedFavorited = favorited
        favoritesWritten.append(favorited)
        whenWritten?()
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

/// An Apple Event by its class and ID, such as 'core'/'setd' for a property write or
/// 'core'/'getd' for a read, for a test to report to `iTunesRadioStation.eventDidFail` as
/// one Music failed
func appleEvent(eventClass: UInt32, eventID: UInt32) -> NSAppleEventDescriptor {
    return NSAppleEventDescriptor.appleEvent(
        withEventClass: AEEventClass(eventClass),
        eventID: AEEventID(eventID),
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
}
