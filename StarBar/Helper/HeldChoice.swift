//
//  HeldChoice.swift
//  StarBar
//
//  A rating or heart the user just chose, kept on screen over Music's reads until Music has
//  it. Pure rule, no Apple Events: see `HeldChoiceTests`.
//

import Foundation

/// A rating or heart the user just chose, held on screen over Music's answers until Music
/// agrees, the song changes, Music refuses a write, or the hold runs out.
///
/// Music applies a write a moment after it is sent, and a rating can wait in `RatingWriter`
/// before it is sent at all, so a read in between still answers the old value; showing it
/// put the old stars back, and the rating shortcuts then counted from them.
///
/// Only an answer from Music can end the hold by agreeing. A read Music didn't answer says
/// nothing either way: taking what was on screen as Music's answer ended the hold, and the
/// next answer, still the old value, put the old stars back (the third review, 2026-10-29).
struct HeldChoice<Value: Equatable> {

    private struct Held {
        let value: Value
        /// Music's persistent ID of the track it was written to
        let trackID: String?
        let expires: Date
        /// `iTunesRadioStation.refusedWrites` when it was chosen
        let refusals: Int
    }

    private var held: Held?

    /// Whether a choice is being held
    var isHolding: Bool {
        return held != nil
    }

    /// Hold `value`, chosen for the track `trackID`, for `duration`. `refusals` is
    /// `iTunesRadioStation.refusedWrites` before the write is sent: a write Music refuses
    /// after that makes Music's value the true one again.
    mutating func hold(_ value: Value, for trackID: String?, during duration: TimeInterval, refusals: Int, now: Date = Date()) {
        held = Held(value: value, trackID: trackID, expires: now.addingTimeInterval(duration), refusals: refusals)
    }

    /// Stop holding: the song on show has changed
    mutating func drop() {
        held = nil
    }

    /// What to show for the track `trackID` when Music says `musicSays`: the choice while it
    /// is held for that track and Music has yet to report it, otherwise Music's answer.
    mutating func value(musicSays: Value, trackID: String?, refusals: Int, now: Date = Date()) -> Value {
        return value(answered: musicSays, trackID: trackID, refusals: refusals, now: now) ?? musicSays
    }

    /// The same when Music may not have answered (`answered` nil). No answer neither confirms
    /// nor ends a hold, so the choice is shown while it stands; nil means Music didn't answer
    /// and nothing is held for the track.
    mutating func value(answered: Value?, trackID: String?, refusals: Int, now: Date = Date()) -> Value? {
        guard let held = held else { return answered }
        guard held.trackID == trackID, now < held.expires, refusals == held.refusals else {
            self.held = nil
            return answered
        }
        if answered == held.value {
            self.held = nil
        }
        return held.value
    }

}
