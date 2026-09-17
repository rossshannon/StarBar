//
//  StarSweep.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-09-17.
//

import Foundation

/// The animation that reminds the user to rate a track: a hollow star moves across the five
/// dots to the right and back again, once. It starts with the bell sound and lasts about half
/// as long.
enum StarSweep {

    /// Star positions in order, 0 (leftmost) to 4 (rightmost) and back
    static let positions = [0, 1, 2, 3, 4, 3, 2, 1, 0]

    /// Time on each position, in seconds
    static let stepDuration: TimeInterval = 0.087

    /// Length of the whole sweep, in seconds
    static var duration: TimeInterval {
        return Double(positions.count) * stepDuration
    }

    /// Star position `elapsed` seconds after the sweep started, or nil when the sweep is over
    static func position(atElapsed elapsed: TimeInterval) -> Int? {
        guard elapsed >= 0 else { return nil }
        let step = Int(elapsed / stepDuration)
        return step < positions.count ? positions[step] : nil
    }

}
