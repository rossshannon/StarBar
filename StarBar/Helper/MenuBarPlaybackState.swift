/// Keeps the last song visible until the player being followed quits. Music sends the same
/// bare Stopped notification between songs, so it cannot be used to end the displayed session.
final class MenuBarPlaybackState {
    private(set) var isStopped = true
    private(set) var isWaitingForTrack = false
    private let didStop: () -> Void

    var canInteract: Bool { !isStopped && !isWaitingForTrack }

    init(didStop: @escaping () -> Void) {
        self.didStop = didStop
    }

    /// True when the caller can apply the new track's rating and favourite together.
    ///
    /// - Parameter isRunning: whether the player the menu bar follows is running: Music, or
    ///   Spotify while the arbiter follows Spotify
    func update(hasTrack: Bool, isStopped: Bool, isRunning: Bool) -> Bool {
        guard isRunning else {
            stop()
            return false
        }
        guard hasTrack, !isStopped else {
            isWaitingForTrack = true
            return false
        }

        isWaitingForTrack = false
        self.isStopped = false
        return true
    }

    private func stop() {
        isWaitingForTrack = false
        guard !isStopped else { return }
        isStopped = true
        didStop()
    }
}
