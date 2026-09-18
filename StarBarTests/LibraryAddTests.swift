//
//  LibraryAddTests.swift
//  StarBarTests
//
//  The rule for spotting the song a library add produced. No Music app needed.
//

import XCTest
@testable import StarBar

final class LibraryAddTests: XCTestCase {

    func testNothingNewMeansTheAddHasNotLandedYet() {
        // Music returns from `duplicate` before the song is in the library, so an empty
        // result is the normal first answer rather than a failure
        XCTAssertEqual(LibraryAdd.result(before: [], after: []), .pending)
    }

    func testTheOneNewIDIsTheSongThatWasAdded() {
        XCTAssertEqual(LibraryAdd.result(before: [], after: [372979]), .added(databaseID: 372979))
    }

    func testTheSongIsFoundAlongsideCopiesTheLibraryAlreadyHad() {
        // The library can already hold the same song, so it is the new ID that matters,
        // not the only one
        XCTAssertEqual(
            LibraryAdd.result(before: [5769, 18216], after: [5769, 18216, 372979]),
            .added(databaseID: 372979)
        )
    }

    func testSeveralAppearingAtOnceIsRefused() {
        // No way to tell which one this add made, and rating the wrong song is worse than
        // rating none
        XCTAssertEqual(
            LibraryAdd.result(before: [1], after: [1, 2, 3]),
            .ambiguous(count: 2)
        )
    }

    func testASongDisappearingDoesNotCountAsAnAdd() {
        // Deleting during the add shouldn't be read as a result
        XCTAssertEqual(LibraryAdd.result(before: [1, 2], after: [1]), .pending)
    }

    func testAnUnchangedLibraryIsStillPending() {
        XCTAssertEqual(LibraryAdd.result(before: [5769], after: [5769]), .pending)
    }

    func testTheWholeLibraryBeingReplacedIsAmbiguousRatherThanAGuess() {
        XCTAssertEqual(
            LibraryAdd.result(before: [1], after: [7, 8]),
            .ambiguous(count: 2)
        )
    }

}
