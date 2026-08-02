//
//  AVAudioEngineSynth.swift
//  ImprovisorEngine
//
//  Self-contained audio backend: AVAudioEngine hosting macOS's built-in General
//  MIDI instrument (Apple's DLS synth). No SoundFont or setup required — it plays
//  immediately using the system GM sounds.
//
//  Forward-compatibility (the agreed plan): this is one implementation of
//  `InstrumentBackend`. To upgrade the sound later without touching the player or
//  the app, swap the node here for an `AVAudioUnitSampler` loading a SoundFont
//  (.sf2/.dls), or host an installed AUv3 instrument via `AVAudioUnit.instantiate`
//  with its component description. macOS's own GarageBand/Logic *patches* are not
//  loadable this way — for those, route MIDI to that app with `CoreMIDIBackend`.
//

#if canImport(AVFoundation)
import Foundation
import AVFoundation
import AudioToolbox

public final class AVAudioEngineSynth: InstrumentBackend {
    private let engine = AVAudioEngine()
    private var synth: AVAudioUnit?
    private var started = false

    public init() {}

    public func start() throws {
        guard !started else { return }

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_DLSSynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)

        // Instantiate the built-in synth (async API; block the calling background
        // thread until it's ready).
        let semaphore = DispatchSemaphore(value: 0)
        var made: AVAudioUnit?
        var failure: Error?
        AVAudioUnit.instantiate(with: description, options: []) { unit, error in
            made = unit
            failure = error
            semaphore.signal()
        }
        semaphore.wait()
        if let failure { throw failure }
        guard let unit = made else {
            throw NSError(domain: "AVAudioEngineSynth", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the built-in synth"])
        }

        engine.attach(unit)
        engine.connect(unit, to: engine.mainMixerNode, format: nil)
        synth = unit
        try engine.start()
        started = true
        _ = description   // silence "written but never read" on some toolchains
    }

    public func stop() {
        allNotesOff()
        engine.stop()
        started = false
    }

    public func programChange(_ program: UInt8, channel: UInt8) {
        send(0xC0 | (channel & 0x0F), program & 0x7F, 0)
    }

    public func noteOn(_ pitch: UInt8, velocity: UInt8, channel: UInt8) {
        send(0x90 | (channel & 0x0F), pitch & 0x7F, velocity & 0x7F)
    }

    public func noteOff(_ pitch: UInt8, channel: UInt8) {
        send(0x80 | (channel & 0x0F), pitch & 0x7F, 0)
    }

    public func allNotesOff() {
        for channel in 0..<16 { send(0xB0 | UInt8(channel), 123, 0) }
    }

    private func send(_ status: UInt8, _ data1: UInt8, _ data2: UInt8) {
        guard let audioUnit = synth?.audioUnit else { return }
        MusicDeviceMIDIEvent(audioUnit, UInt32(status), UInt32(data1), UInt32(data2), 0)
    }

    deinit {
        if started { engine.stop() }
    }
}
#endif
