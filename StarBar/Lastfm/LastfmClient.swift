//
//  LastfmClient.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-13.
//

import Foundation
import os

/// What the scrobbler sends through: Last.fm in the app, a fake in tests, and a logger for a
/// dry run (`DryRunLastfmSender`). Main thread only; every completion runs on the main thread.
protocol LastfmSending: AnyObject {
    /// Tell Last.fm what is playing now. Never retried: the next song says it again.
    func updateNowPlaying(_ track: Scrobble.Track, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void)
    /// Send up to `LastfmAPI.maxBatch` scrobbles in one call
    func scrobble(_ scrobbles: [Scrobble], completion: @escaping (Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>) -> Void)
    /// Love or unlove a song
    func setLoved(_ loved: Bool, title: String, artist: String, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void)
}

/// Last.fm's calls for one signed-in user, over an injectable transport (`SpotifyLibrary`'s,
/// which is only "send this request, hand back the data and the response"). A completion
/// that follows a request runs on a later turn of the main queue; one that needs no request
/// (an empty batch, a song with no title or artist) runs before the call returns.
final class LastfmClient: LastfmSending {

    let credentials: LastfmAPI.Credentials
    let session: LastfmSession
    private let transport: SpotifyLibrary.Transport

    init(credentials: LastfmAPI.Credentials, session: LastfmSession, transport: @escaping SpotifyLibrary.Transport = SpotifyLibrary.urlSessionTransport) {
        self.credentials = credentials
        self.session = session
        self.transport = transport
    }

    func updateNowPlaying(_ track: Scrobble.Track, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void) {
        guard track.canBeSent else {
            completion(.failure(LastfmClient.unsendable))
            return
        }
        let request = LastfmAPI.nowPlayingRequest(track, credentials: credentials, sessionKey: session.key)
        perform(request) { data, response in
            if let failure = LastfmAPI.failure(data: data, response: response) {
                LastfmClient.log(failure, of: "track.updateNowPlaying")
                completion(.failure(failure))
            } else {
                completion(.success(()))
            }
        }
    }

    /// An empty batch succeeds at once with an empty summary and sends nothing. An answer
    /// that worked but whose summary can't be read still succeeds, with `accepted` taken as
    /// the batch's size: the scrobbles reached Last.fm, and sending them again would double
    /// them.
    ///
    /// Only the first `LastfmAPI.maxBatch` are sent. A scrobble with no title or artist is
    /// left out of the request, because Last.fm could refuse the whole batch for it, and is
    /// counted as ignored; a batch of nothing else succeeds at once without a request.
    func scrobble(_ scrobbles: [Scrobble], completion: @escaping (Result<LastfmAPI.ScrobbleSummary, LastfmAPI.Failure>) -> Void) {
        let batch = Array(scrobbles.prefix(LastfmAPI.maxBatch))
        let sendable = batch.filter { $0.track.canBeSent }
        let unsendable = batch.count - sendable.count
        guard !sendable.isEmpty else {
            completion(.success(LastfmAPI.ScrobbleSummary(accepted: 0, ignored: unsendable, ignoredCodes: [])))
            return
        }
        let request = LastfmAPI.scrobbleRequest(sendable, credentials: credentials, sessionKey: session.key)
        perform(request) { data, response in
            if let failure = LastfmAPI.failure(data: data, response: response) {
                LastfmClient.log(failure, of: "track.scrobble")
                completion(.failure(failure))
                return
            }
            var summary = data.flatMap(LastfmAPI.parseScrobbles)
                ?? LastfmAPI.ScrobbleSummary(accepted: sendable.count, ignored: 0, ignoredCodes: [])
            summary.ignored += unsendable
            let codes: String = summary.ignoredCodes.isEmpty ? "" : " (codes " + summary.ignoredCodes.map { String($0) }.joined(separator: ", ") + ")"
            os_log("%{public}s[%{public}ld], %{public}s: Last.fm took %{public}ld scrobbles and ignored %{public}ld%{public}s", ((#file as NSString).lastPathComponent), #line, #function, summary.accepted, summary.ignored, codes)
            completion(.success(summary))
        }
    }

    func setLoved(_ loved: Bool, title: String, artist: String, completion: @escaping (Result<Void, LastfmAPI.Failure>) -> Void) {
        guard Scrobble.Track(title: title, artist: artist).canBeSent else {
            completion(.failure(LastfmClient.unsendable))
            return
        }
        let method = loved ? "track.love" : "track.unlove"
        let request = LastfmAPI.loveRequest(title: title, artist: artist, loved: loved, credentials: credentials, sessionKey: session.key)
        perform(request) { data, response in
            if let failure = LastfmAPI.failure(data: data, response: response) {
                LastfmClient.log(failure, of: method)
                completion(.failure(failure))
            } else {
                completion(.success(()))
            }
        }
    }

    /// What a song with no title or artist gets without a request: Last.fm's own answer to
    /// one, error 6 (invalid parameters), which is never sent again
    static let unsendable = LastfmAPI.Failure.refused(6)

    /// Send through the transport and answer on the main thread, always on a later turn of
    /// the main queue so a caller never sees its completion run inside its own call
    private func perform(_ request: URLRequest, completion: @escaping (Data?, HTTPURLResponse?) -> Void) {
        transport(request) { data, response in
            DispatchQueue.main.async { completion(data, response) }
        }
    }

    /// One line for a failed call. Names the method and the failure only: never the request,
    /// whose body holds the session key and signature.
    private static func log(_ failure: LastfmAPI.Failure, of method: String) {
        os_log(.error, "%{public}s[%{public}ld], %{public}s: %{public}s failed: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, method, String(describing: failure))
    }

}
