//
//  InstrumentBackend.swift
//  ImprovisorEngine
//
//  The seam that keeps the audio backend swappable (Step 8). A backend is just
//  something that can receive MIDI-style messages; the `SequencePlayer` turns a
//  set of tracks into a timed stream of those messages and drives any backend.
//
//  This is what makes the "decide the sound source later" plan work at no cost:
//   - AVAudioEngineSynth  → self-contained playback via macOS's built-in General
//                           MIDI instrument (swap in a SoundFont or an AUv3
//                           instrument later without touching the player).
//   - CoreMIDIBackend     → send to an external synth / DAW (e.g. GarageBand via
//                           the IAC bus, or a hardware piano).
//

import Foundation

/// A destination for real-time MIDI-style messages. Channels are 0–15.
public protocol InstrumentBackend: AnyObject {
    /// Start the backend (e.g. boot the audio engine). No-op for pure MIDI out.
    func start() throws
    /// Stop the backend and release resources.
    func stop()
    /// Set a channel's General MIDI program (instrument).
    func programChange(_ program: UInt8, channel: UInt8)
    func noteOn(_ pitch: UInt8, velocity: UInt8, channel: UInt8)
    func noteOff(_ pitch: UInt8, channel: UInt8)
    /// Silence everything immediately (panic).
    func allNotesOff()
}

/// One timed message in a flattened playback timeline.
public struct PlaybackEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case program(UInt8)
        case noteOn(pitch: UInt8, velocity: UInt8)
        case noteOff(pitch: UInt8)
    }
    /// Seconds from the start of playback.
    public var seconds: Double
    public var channel: UInt8
    public var kind: Kind

    public init(seconds: Double, channel: UInt8, kind: Kind) {
        self.seconds = seconds
        self.channel = channel
        self.kind = kind
    }
}

public enum PlaybackTimeline {
    /// Flatten tracks into a time-sorted event list. `loops` repeats the whole
    /// set, offsetting each repeat by `formSlots` (0 = derive from the tracks).
    /// Timing is the same slot→seconds mapping the SMF writer and live player use
    /// (`Constants.BEAT` slots per quarter).
    ///
    /// This is a thin wrapper over `SlotTimeline.events`, which does the actual
    /// flattening/ordering in slot space (used directly by `Transport` so a
    /// live tempo change doesn't require re-baking any seconds). This function
    /// just maps each slot to seconds at a single fixed tempo, for callers that
    /// want a static, non-live timeline (e.g. tests, one-shot preview).
    public static func events(tracks: [MIDITrack], tempoBPM: Double,
                              loops: Int = 1, formSlots: Int = 0) -> [PlaybackEvent] {
        let secondsPerSlot = 60.0 / (max(1, tempoBPM) * Double(Constants.BEAT))
        let slotEvents = SlotTimeline.events(tracks: tracks, loops: loops, formSlots: formSlots)
        // SlotTimeline already sorts by slot then program<off<on, and ties at
        // the same slot map to the same seconds value, so the ordering carries
        // over unchanged — no re-sort needed here.
        return slotEvents.map { e in
            PlaybackEvent(seconds: Double(e.slot) * secondsPerSlot, channel: e.channel, kind: e.kind)
        }
    }

    /// Total duration of a timeline in seconds.
    public static func duration(_ events: [PlaybackEvent]) -> Double {
        events.last?.seconds ?? 0
    }
}
