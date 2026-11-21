//
//  ProcessAudioOutput.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-21.
//

import CoreAudio
import Foundation
import os

/// Whether one process is sending sound to an output device on this Mac, from Core Audio's
/// process objects, with a call when that changes. `SpotifyPlayer` uses it to tell Spotify
/// playing here from Spotify playing on another device (`SpotifyPlaybackPlace`).
///
/// - Core Audio has listed the processes using it since macOS 14.2 (the same release as
///   process taps). Before that every answer is nil, which counts as "can't tell".
/// - Reading them asks for no permission: only recording another app's sound (a tap) does.
///   Measured 2026-11-20 on macOS 27.2, outside the sandbox: Spotify's main process is a Core
///   Audio client and its helper processes are not, so the main process is the one to watch.
///   A process that has never opened an audio stream has no object at all, which is no sound.
/// - A developer forum report (thread 770348, macOS 15.0.1) found a listener on
///   `kAudioProcessPropertyIsRunningOutput` never called, where ones on
///   `kAudioProcessPropertyIsRunning` and `kAudioProcessPropertyDevices` were. So all three are
///   listened to, and each call reads the output afresh. Not measured here.
/// - The list of processes is listened to as well, for a process that opens its first stream
///   after it is being watched.
///
/// Listeners are called on the main queue. Main thread only.
final class ProcessAudioOutput {

    /// Whether this Mac can answer at all
    static var isAvailable: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    /// Called on the main thread when the answer changes
    var didChange: ((Bool?) -> Void)?

    private var pid: pid_t?
    private var object = AudioObjectID(kAudioObjectUnknown)
    private var processListener: AudioObjectPropertyListenerBlock?
    private var listListener: AudioObjectPropertyListenerBlock?
    /// The last answer passed to `didChange`, or what was read when watching started
    private var lastAnswer: Bool?
    /// So a read that fails is logged once a process, not on every call
    private var hasLoggedFailure = false

    deinit {
        watch(pid: nil)
    }

    /// Watch the process `pid`, or nothing. Answers what it is doing now; `didChange` is
    /// called only for a later change.
    @discardableResult
    func watch(pid: pid_t?) -> Bool? {
        guard #available(macOS 14.2, *) else { return nil }
        removeProcessListener()
        removeListListener()
        self.pid = pid
        hasLoggedFailure = false
        object = AudioObjectID(kAudioObjectUnknown)
        guard pid != nil else {
            lastAnswer = nil
            return nil
        }
        addListListener()
        lookUpObject()
        lastAnswer = isSendingAudio()
        return lastAnswer
    }

    /// Whether the process is sending sound to an output now: nil when Core Audio can't say,
    /// false when the process has no audio stream at all
    func isSendingAudio() -> Bool? {
        guard #available(macOS 14.2, *), pid != nil else { return nil }
        if object == AudioObjectID(kAudioObjectUnknown) {
            lookUpObject()
        }
        guard object != AudioObjectID(kAudioObjectUnknown) else {
            // Translated, but no object: it has never opened a stream. Nil if the
            // translation itself failed.
            return lookUpFailed ? nil : false
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr else {
            logFailure("reading whether process \(pid ?? 0) sends sound", status)
            return nil
        }
        return value != 0
    }

    /// True when the last look for the process's object failed, as against finding none
    private var lookUpFailed = false

}

// MARK: - Core Audio

@available(macOS 14.2, *)
private extension ProcessAudioOutput {

    static let processSelectors: [AudioObjectPropertySelector] = [
        kAudioProcessPropertyIsRunningOutput,
        kAudioProcessPropertyIsRunning,
        kAudioProcessPropertyDevices,
    ]

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        return AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Find the process's Core Audio object, and listen to it if it is a new one
    func lookUpObject() {
        guard var qualifier = pid else { return }
        var address = ProcessAudioOutput.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var found = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &qualifier, &size, &found)
        guard status == noErr else {
            lookUpFailed = true
            logFailure("finding process \(qualifier)'s audio object", status)
            return
        }
        lookUpFailed = false
        guard found != object else { return }
        removeProcessListener()
        object = found
        if found != AudioObjectID(kAudioObjectUnknown) {
            addProcessListener()
        }
    }

    func addProcessListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.answerChanged()
        }
        for selector in ProcessAudioOutput.processSelectors {
            var address = ProcessAudioOutput.address(selector)
            let status = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, listener)
            if status != noErr {
                logFailure("listening to process \(pid ?? 0)'s sound", status)
            }
        }
        processListener = listener
    }

    func removeProcessListener() {
        guard let listener = processListener else { return }
        for selector in ProcessAudioOutput.processSelectors {
            var address = ProcessAudioOutput.address(selector)
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, listener)
        }
        processListener = nil
    }

    /// The list of processes changes when one opens its first audio stream or quits
    func addListListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            self.lookUpObject()
            self.answerChanged()
        }
        var address = ProcessAudioOutput.address(kAudioHardwarePropertyProcessObjectList)
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        if status != noErr {
            logFailure("listening to the list of audio processes", status)
        }
        listListener = listener
    }

    func removeListListener() {
        guard let listener = listListener else { return }
        var address = ProcessAudioOutput.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        listListener = nil
    }

}

private extension ProcessAudioOutput {

    func answerChanged() {
        let answer = isSendingAudio()
        guard answer != lastAnswer else { return }
        lastAnswer = answer
        os_log("%{public}s[%{public}ld], %{public}s: process %{public}d %{public}s", ((#file as NSString).lastPathComponent), #line, #function, pid ?? 0,
               answer.map { $0 ? "started sending sound to an output" : "stopped sending sound" } ?? "can no longer be read")
        didChange?(answer)
    }

    func logFailure(_ what: String, _ status: OSStatus) {
        guard !hasLoggedFailure else { return }
        hasLoggedFailure = true
        os_log(.error, "%{public}s[%{public}ld], %{public}s: Core Audio failed %{public}s: %{public}d; treating it as unknown", ((#file as NSString).lastPathComponent), #line, #function, what, status)
    }

}
