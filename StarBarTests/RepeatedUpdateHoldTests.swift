//
//  RepeatedUpdateHoldTests.swift
//  StarBarTests
//
//  Music's repeat of a song's notification waits while the strip or the menu bar moves, and
//  only a repeat does. The station's hold is a `RepeatedUpdateHold<PlayInfo>`, so these drive one with a
//  fake clock and decide repeats with `PlayInfo.repeats(_:)`.
//

import XCTest
@testable import StarBar

final class RepeatedUpdateHoldTests: XCTestCase {

    private let clock = FakeClock()
    private var busy = true
    private var applied: [String] = []
    private var hold: RepeatedUpdateHold<String>!

    override func setUp() {
        super.setUp()
        busy = true
        applied = []
        hold = RepeatedUpdateHold(clock: { [unowned self] in self.clock }, isBusy: { [unowned self] in self.busy }, apply: { [unowned self] in self.applied.append($0) })
    }

    // MARK: - The hold

    func testAnUpdateThatIsNoRepeatGoesOnAtOnce() {
        XCTAssertFalse(hold.receive("A", repeatsLast: false))
        XCTAssertEqual(applied, ["A"])
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
    }

    func testARepeatGoesOnAtOnceWhenNothingIsMoving() {
        busy = false
        XCTAssertFalse(hold.receive("A again", repeatsLast: true))
        XCTAssertEqual(applied, ["A again"])
    }

    func testARepeatWaitsUntilTheMotionIsOver() {
        XCTAssertTrue(hold.receive("A again", repeatsLast: true))
        XCTAssertEqual(applied, [])
        XCTAssertTrue(hold.isHolding)

        clock.advance(by: RepeatedUpdateHold<String>.checkInterval)
        clock.fireAllOneShots()
        XCTAssertEqual(applied, [], "still moving")

        busy = false
        clock.advance(by: RepeatedUpdateHold<String>.checkInterval)
        clock.fireAllOneShots()
        XCTAssertEqual(applied, ["A again"])
        XCTAssertFalse(hold.isHolding)
        XCTAssertTrue(clock.pendingOneShots.isEmpty)
    }

    func testOnlyTheLatestRepeatIsKept() {
        hold.receive("A again", repeatsLast: true)
        hold.receive("A once more", repeatsLast: true)
        busy = false
        clock.advance(by: RepeatedUpdateHold<String>.checkInterval)
        clock.fireAllOneShots()
        XCTAssertEqual(applied, ["A once more"])
    }

    func testANewSongDropsTheRepeatItSupersedes() {
        hold.receive("A again", repeatsLast: true)
        hold.receive("B", repeatsLast: false)
        XCTAssertEqual(applied, ["B"])
        XCTAssertFalse(hold.isHolding)

        busy = false
        clock.pendingOneShots.forEach { $0.action() }
        XCTAssertEqual(applied, ["B"], "the old song's repeat never lands after the new song")
    }

    func testMotionThatDoesntEndCanOnlyHoldARepeatSoLong() {
        hold.receive("A again", repeatsLast: true)
        var waited: TimeInterval = 0
        while applied.isEmpty, waited < 10 {
            clock.advance(by: RepeatedUpdateHold<String>.checkInterval)
            clock.fireAllOneShots()
            waited += RepeatedUpdateHold<String>.checkInterval
        }
        XCTAssertEqual(applied, ["A again"])
        XCTAssertEqual(waited, RepeatedUpdateHold<String>.limit, accuracy: RepeatedUpdateHold<String>.checkInterval + 1e-9)
    }

    func testCancelDropsTheRepeat() {
        hold.receive("A again", repeatsLast: true)
        hold.cancel()
        busy = false
        clock.pendingOneShots.forEach { $0.action() }
        XCTAssertEqual(applied, [])
    }

    // MARK: - What a repeat is

    /// A `PlayInfo` as Codable spells it; the station decodes Music's own key names to these
    private func playInfo(_ fields: [String: Any]) throws -> PlayInfo {
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(PlayInfo.self, from: data)
    }

    private let desertRose: [String: Any] = ["name": "Desert Rose", "artist": "Sting", "album": "Brand New Day", "playerState": "Playing"]

    func testTheSameSongStillPlayingIsARepeat() throws {
        let first = try playInfo(desertRose)
        var again = desertRose
        again["artworkCount"] = 1
        XCTAssertTrue(try playInfo(again).repeats(first), "a cover counted the second time says nothing that can't wait")
        XCTAssertTrue(try playInfo(desertRose.merging(["persistentID": 42]) { $1 }).repeats(try playInfo(desertRose.merging(["persistentID": 42]) { $1 })))
    }

    func testAnIDInOnlyOneOfTheTwoFallsBackToTheNames() throws {
        let withoutID = try playInfo(desertRose)
        let withID = try playInfo(desertRose.merging(["persistentID": 42]) { $1 })
        XCTAssertTrue(withID.repeats(withoutID))
        XCTAssertTrue(withoutID.repeats(withID))
    }

    func testAnotherSongIsNoRepeat() throws {
        let first = try playInfo(desertRose.merging(["persistentID": 42]) { $1 })
        XCTAssertFalse(try playInfo(desertRose.merging(["persistentID": 43]) { $1 }).repeats(first), "the same names under another ID: another copy")
        XCTAssertFalse(try playInfo(desertRose.merging(["name": "Brand New Day"]) { $1 }).repeats(try playInfo(desertRose)))
        XCTAssertFalse(try playInfo(desertRose.merging(["album": "Live"]) { $1 }).repeats(try playInfo(desertRose)))
    }

    func testAChangedStateOrRatingIsNoRepeat() throws {
        let first = try playInfo(desertRose)
        XCTAssertFalse(try playInfo(desertRose.merging(["playerState": "Paused"]) { $1 }).repeats(first), "a pause")
        XCTAssertFalse(try playInfo(desertRose.merging(["playerState": "Stopped"]) { $1 }).repeats(try playInfo(desertRose.merging(["playerState": "Stopped"]) { $1 })), "a stop is never held")
        XCTAssertFalse(try playInfo(desertRose.merging(["rating": 80]) { $1 }).repeats(first), "perhaps rated in Music")
        XCTAssertTrue(try playInfo(desertRose.merging(["playerState": "Paused"]) { $1 }).repeats(try playInfo(desertRose.merging(["playerState": "Paused"]) { $1 })), "still paused")
    }

    func testAPayloadNamingNoSongIsNoRepeat() throws {
        let nameless = try playInfo(["playerState": "Playing"])
        XCTAssertFalse(nameless.repeats(nameless))
        let stateless = try playInfo(["name": "Desert Rose"])
        XCTAssertFalse(stateless.repeats(stateless), "sourceSaved's payload has no state")
    }

}
