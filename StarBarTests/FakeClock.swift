//
//  FakeClock.swift
//  StarBarTests
//
//  A clock the tests advance by hand, with timers they fire when they choose, so the rating
//  reminder and the track announcement run without waiting.
//

import Foundation
import XCTest
@testable import StarBar

final class FakeClock: RatingReminderClock {

    final class FakeTimer: RatingReminderTimer {
        let seconds: TimeInterval
        let repeats: Bool
        let action: () -> Void
        private(set) var isValid = true

        init(seconds: TimeInterval, repeats: Bool, action: @escaping () -> Void) {
            self.seconds = seconds
            self.repeats = repeats
            self.action = action
        }

        func invalidate() { isValid = false }
    }

    private var current = Date(timeIntervalSinceReferenceDate: 0)
    private(set) var timers: [FakeTimer] = []

    func now() -> Date { return current }

    func schedule(after seconds: TimeInterval, repeats: Bool, action: @escaping () -> Void) -> RatingReminderTimer {
        let timer = FakeTimer(seconds: seconds, repeats: repeats, action: action)
        timers.append(timer)
        return timer
    }

    var pendingOneShot: FakeTimer? {
        return timers.last { $0.isValid && !$0.repeats }
    }

    /// All one-shot timers still valid, oldest first
    var pendingOneShots: [FakeTimer] {
        return timers.filter { $0.isValid && !$0.repeats }
    }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }

    /// Fire the pending one-shot timer, as the run loop would when it's due
    func fireOneShot(file: StaticString = #filePath, line: UInt = #line) {
        guard let timer = pendingOneShot else { return XCTFail("no pending timer", file: file, line: line) }
        timer.invalidate()
        timer.action()
    }

    /// Fire every pending one-shot timer, oldest first, as the run loop would once they were
    /// all due. Unlike `fireOneShot()`, a timer the code forgot to invalidate fires too, so a
    /// test counting what the timers do sees it. Timers scheduled while these fire wait for
    /// the next call.
    func fireAllOneShots(file: StaticString = #filePath, line: UInt = #line) {
        let due = pendingOneShots
        guard !due.isEmpty else { return XCTFail("no pending timer", file: file, line: line) }
        for timer in due where timer.isValid {
            timer.invalidate()
            timer.action()
        }
    }

    func fireRepeating() {
        timers.filter { $0.isValid && $0.repeats }.forEach { $0.action() }
    }

}
