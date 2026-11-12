//
//  RepeatedUpdateHold.swift
//  StarBar
//

import Foundation
import os.log

/// Holds back an update that repeats the last one while something on screen is moving, and
/// passes it on once the motion is over.
///
/// Music often follows a song's `playerInfo` notification with a second for the same song a
/// moment later. Each one replaces the player record, so the menu bar, the strip and the
/// popover all read Music again, over Apple Events on the main thread. Measured on 2026-11-03,
/// for an Apple Music song, the second came 15 ms after the strip was announced and its reads
/// took about 26 Apple Events and 440 ms, during which the strip's slide could not be drawn.
/// A repeat says nothing that can't wait a second or so, so it waits for the strip to stop
/// moving; it is not dropped, because it may still carry something the first didn't (a cover,
/// or a track Music had not switched to yet).
///
/// It waits for the menu bar's transitions as well, which are drawn the same way. The strip is
/// still after 0.65 s, but the stars roll in for a second, so a repeat let go when the strip
/// stopped was read while they rolled: on 2026-11-12, in the one rollout with a repeat that
/// the log still held, the repeat was passed on 0.67 s after it came, about 0.46 s into the
/// roll, and the menu bar's reads for it alone then held the main thread for 124 ms.
///
/// Only the latest repeat is kept. Anything that is not a repeat goes on at once and drops the
/// one held, which it supersedes. The wait is checked every `checkInterval` and never runs past
/// `limit`, so motion that doesn't end can't hold Music's news back for long.
final class RepeatedUpdateHold<Update> {

    /// How often a held update checks whether the motion has ended
    static var checkInterval: TimeInterval { return 0.05 }
    /// The longest an update is held. The slide in and the sleeve's rise take 0.65 s; the
    /// menu bar's longest transition, the rollout from Spotify's heart, 1.35 s from its first
    /// frame (the heart's fade, the wait for the widened item and the roll), and a held main
    /// thread pauses it. A transition whose frames never come, as with the display asleep,
    /// is why there is a limit at all.
    static var limit: TimeInterval { return 2.0 }

    /// Where the timers come from; the station swaps its clock for a fake one in tests
    private let clock: () -> RatingReminderClock
    /// Whether anything is moving that a held-up main thread would stall
    private let isBusy: () -> Bool
    /// Passes an update on
    private let apply: (Update) -> Void

    private var held: Update?
    private var heldSince: Date?
    private var timer: RatingReminderTimer?

    init(clock: @escaping () -> RatingReminderClock, isBusy: @escaping () -> Bool, apply: @escaping (Update) -> Void) {
        self.clock = clock
        self.isBusy = isBusy
        self.apply = apply
    }

    /// Whether an update is waiting
    var isHolding: Bool {
        return held != nil
    }

    /// Pass `update` on now, or hold it while something is moving if it repeats the last one
    /// passed on. Returns true when it was held.
    @discardableResult
    func receive(_ update: Update, repeatsLast: Bool) -> Bool {
        guard repeatsLast, isBusy() else {
            cancel()
            apply(update)
            return false
        }
        held = update
        if heldSince == nil {
            heldSince = clock().now()
            scheduleCheck()
        }
        return true
    }

    /// Drop a held update without passing it on
    func cancel() {
        timer?.invalidate()
        timer = nil
        held = nil
        heldSince = nil
    }

    private func scheduleCheck() {
        timer?.invalidate()
        timer = clock().schedule(after: RepeatedUpdateHold.checkInterval, repeats: false) { [weak self] in
            self?.check()
        }
    }

    private func check() {
        timer = nil
        guard let update = held, let since = heldSince else { return }
        if isBusy(), clock().now().timeIntervalSince(since) < RepeatedUpdateHold.limit {
            scheduleCheck()
            return
        }
        held = nil
        heldSince = nil
        os_log("%{public}s[%{public}ld], %{public}s: passing on a repeated update held for %.2f s", ((#file as NSString).lastPathComponent), #line, #function, clock().now().timeIntervalSince(since))
        apply(update)
    }

}
