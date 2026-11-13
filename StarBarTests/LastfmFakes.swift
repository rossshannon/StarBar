//
//  LastfmFakes.swift
//  StarBarTests
//
//  Stand-ins shared by the Last.fm tests: a sender that records what it was asked to send
//  and answers as the test says, an account, and a queue store kept in memory. For requests
//  on the wire, `FakeSpotifyTransport` (SpotifyLibraryTests.swift) serves Last.fm as well.
//

import Foundation
import XCTest
@testable import StarBar

/// Records what the scrobbler sent and answers when the test says so
final class FakeLastfmSender: LastfmSending {

    enum Call: Equatable {
        case nowPlaying(Scrobble.Track)
        case scrobble([Scrobble])
        case love(title: String, artist: String, loved: Bool)
    }

    private(set) var calls: [Call] = []
    /// Answers for `scrobble`, used in turn. With none left, a batch is accepted whole.
    var scrobbleAnswers: [Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>] = []
    /// Answers for `setLoved`, used in turn. With none left, it succeeds.
    var loveAnswers: [Result<Void, LastfmAPI.Failure>] = []
    /// Answers for `updateNowPlaying`, used in turn. With none left, it succeeds.
    var nowPlayingAnswers: [Result<Void, LastfmAPI.Failure>] = []
    /// When false, completions wait in `pending` until `answerPending()`
    var answersAtOnce = true
    private var pending: [() -> Void] = []

    var scrobbleCalls: [[Scrobble]] {
        return calls.compactMap { if case .scrobble(let batch) = $0 { return batch } else { return nil } }
    }

    var loveCalls: [Call] {
        return calls.filter { if case .love = $0 { return true } else { return false } }
    }

    var nowPlayingCalls: [Scrobble.Track] {
        return calls.compactMap { if case .nowPlaying(let track) = $0 { return track } else { return nil } }
    }

    var pendingCount: Int {
        return pending.count
    }

    func answerPending() {
        let waiting = pending
        pending = []
        waiting.forEach { $0() }
    }

    func updateNowPlaying(_ track: Scrobble.Track, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void) {
        calls.append(.nowPlaying(track))
        let answer = nowPlayingAnswers.isEmpty ? .success(()) : nowPlayingAnswers.removeFirst()
        deliver { completion(answer) }
    }

    func scrobble(_ scrobbles: [Scrobble], completion: @escaping (Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>) -> Void) {
        calls.append(.scrobble(scrobbles))
        let accepted = LastfmAPI.ScrobbleSummary(accepted: scrobbles.count, ignored: 0, ignoredCodes: [])
        let answer = scrobbleAnswers.isEmpty ? .success(accepted) : scrobbleAnswers.removeFirst()
        deliver { completion(answer) }
    }

    func setLoved(_ loved: Bool, title: String, artist: String, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void) {
        calls.append(.love(title: title, artist: artist, loved: loved))
        let answer = loveAnswers.isEmpty ? .success(()) : loveAnswers.removeFirst()
        deliver { completion(answer) }
    }

    private func deliver(_ completion: @escaping () -> Void) {
        if answersAtOnce {
            completion()
        } else {
            pending.append(completion)
        }
    }

}

/// A sign-in the test sets by hand, which records what the scrobbler told it
final class FakeLastfmAccount: LastfmAccountProviding {

    var username: String?
    var sender: LastfmSending?
    private(set) var rejections = 0
    private(set) var failures: [LastfmAPI.Failure] = []
    private(set) var successes = 0

    init(username: String? = nil, sender: LastfmSending? = nil) {
        self.username = username
        self.sender = sender
    }

    /// As the real account does: the sign-in is gone
    func sessionWasRejected() {
        rejections += 1
        username = nil
        sender = nil
    }

    func note(_ failure: LastfmAPI.Failure) {
        failures.append(failure)
    }

    func noteSuccess() {
        successes += 1
    }

}

/// Queues kept in memory, by user, with a count of saves
final class MemoryScrobbleQueueStore: ScrobbleQueueStore {

    var contents: [String: ScrobbleQueue.Contents] = [:]
    private(set) var saves = 0
    private(set) var deletes: [String] = []
    private(set) var synchronizes = 0

    func load(user: String) -> ScrobbleQueue.Contents? {
        return contents[user]
    }

    func save(_ contents: ScrobbleQueue.Contents, user: String) {
        saves += 1
        self.contents[user] = contents
    }

    func delete(user: String) {
        deletes.append(user)
        contents[user] = nil
    }

    func synchronize() {
        synchronizes += 1
    }

}

extension Scrobble.Track {

    /// A song for tests, four minutes long unless told otherwise
    static func test(_ title: String = "Song", artist: String = "Artist", album: String? = "Album", duration: TimeInterval? = 240) -> Scrobble.Track {
        return Scrobble.Track(title: title, artist: artist, album: album, duration: duration)
    }

}

extension PlayTracker.Song {

    /// A song for tests, identified by its title
    static func test(_ title: String = "Song", artist: String = "Artist", duration: TimeInterval? = 240, isScrobblable: Bool = true) -> PlayTracker.Song {
        return PlayTracker.Song(identity: "id-\(title)", track: .test(title, artist: artist, duration: duration), isScrobblable: isScrobblable)
    }

}
