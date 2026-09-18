//
//  LibraryAdd.swift
//  StarBar
//
//  Working out which song a library add produced. Pure rule, no Apple Events:
//  see `LibraryAddTests`.
//

import Foundation

/// What became of a song added to the library.
///
/// Music's add is asynchronous: `duplicate` returns before the song is in the library, so the
/// only way to find the new entry is to compare the database IDs matching that song before and
/// after, and to keep looking until one appears.
enum LibraryAdd: Equatable {

    /// Nothing new yet. Normal until the add lands, so keep waiting.
    case pending
    /// The song that was added, by its Music database ID
    case added(databaseID: Int)
    /// Several songs appeared at once, so there is no telling which one this add made
    case ambiguous(count: Int)

    /// Compare the database IDs that matched the song before and after the add.
    ///
    /// - Parameters:
    ///   - before: IDs matching the song just before `duplicate` was sent
    ///   - after: IDs matching it now
    static func result(before: Set<Int>, after: Set<Int>) -> LibraryAdd {
        let appeared = after.subtracting(before)

        switch appeared.count {
        case 0:
            return .pending
        case 1:
            // `first` is safe: the count is exactly one
            return .added(databaseID: appeared.first!)
        default:
            // Rating the wrong song is worse than rating none, so don't guess
            return .ambiguous(count: appeared.count)
        }
    }

}
