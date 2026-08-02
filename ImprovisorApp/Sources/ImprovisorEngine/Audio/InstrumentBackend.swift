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
public struct PlaybackEvent: Equatable {
    public enum Kind: Equatable {
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

    /// Sort key so that, at the same instant, program changes and note-offs come
    /// before note-ons (avoids clipping a note-on with a simultaneous off).
    fileprivate var order: Int {
        switch kind {
        case .program: return 0
        case .noteOff: return 1
        case .noteOn: return 2
        }
    }
}

public enum PlaybackTimeline {
    /// Flatten tracks into a time-sorted event list. `loops` repeats the whole
    /// set, offsetting each repeat by `formSlots` (0 = derive from the tracks).
    /// Timing is the same slot→seconds mapping the SMF writer and live player use
    /// (`Constants.BEAT` slots per quarter).
    public static func events(tracks: [MIDITrack], tempoBPM: Double,
                              loops: Int = 1, formSlots: Int = 0) -> [PlaybackEvent] {
        let secondsPerSlot = 60.0 / (max(1, tempoBPM) * Double(Constants.BEAT))
        let span = formSlots > 0 ? formSlots : (tracks.flatMap { $0.notes }
            .map { $0.startTick + max(1, $0.duration) }.max() ?? 0)
        var events: [PlaybackEvent] = []

        for loop in 0..<max(1, loops) {
            let slotOffset = loop * span
            for track in tracks {
                let ch = track.channel & 0x0F
                if let program = track.program, loop == 0 {
                    events.append(PlaybackEvent(seconds: 0, channel: ch, kind: .program(program & 0x7F)))
                }
                for note in track.notes {
                    let onSlot = note.startTick + slotOffset
                    let offSlot = note.startTick + max(1, note.duration) + slotOffset
                    events.append(PlaybackEvent(seconds: Double(onSlot) * secondsPerSlot, channel: ch,
                                                kind: .noteOn(pitch: clampByte(note.pitch),
                                                              velocity: clampByte(note.velocity))))
                    events.append(PlaybackEvent(seconds: Double(offSlot) * secondsPerSlot, channel: ch,
                                                kind: .noteOff(pitch: clampByte(note.pitch))))
                }
            }
        }

        events.sort { a, b in a.seconds != b.seconds ? a.seconds < b.seconds : a.order < b.order }
        return events
    }

    /// Total duration of a timeline in seconds.
    public static func duration(_ events: [PlaybackEvent]) -> Double {
        events.last?.seconds ?? 0
    }
}
