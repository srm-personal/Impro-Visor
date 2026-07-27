//
//  MIDIEvent.swift
//  ImprovisorEngine
//
//  The engine's MIDI interchange types. Generators emit `ScheduledNote`s
//  (pitch + velocity + absolute start slot + duration + channel), which the
//  audio layer (Step 7) turns into timed AUSampler start/stop calls. A flatter
//  `MIDIEvent` (note-on/note-off at a tick) is also provided for tests and for
//  any consumer that prefers discrete events.
//

import Foundation

/// Which instrumental line a note belongs to.
public enum Track: String, Equatable, Sendable, CaseIterable {
    case bass, chords, drums, melody
}

/// A note with an absolute start position and a duration, both in slots.
public struct ScheduledNote: Equatable, Sendable {
    public var pitch: Int
    public var velocity: Int
    /// Absolute start position in slots.
    public var startTick: Int
    /// Duration in slots.
    public var duration: Int
    /// MIDI channel (0–15). Drums use channel 9.
    public var channel: UInt8

    public init(pitch: Int, velocity: Int, startTick: Int, duration: Int, channel: UInt8) {
        self.pitch = pitch
        self.velocity = velocity
        self.startTick = startTick
        self.duration = duration
        self.channel = channel
    }

    /// The note split into a note-on / note-off pair.
    public var midiEvents: [MIDIEvent] {
        [
            MIDIEvent(type: .noteOn, channel: channel,
                      pitch: clampByte(pitch), velocity: clampByte(velocity),
                      tick: startTick),
            MIDIEvent(type: .noteOff, channel: channel,
                      pitch: clampByte(pitch), velocity: 0,
                      tick: startTick + duration)
        ]
    }
}

/// A discrete MIDI event at a slot position.
public struct MIDIEvent: Equatable, Sendable {
    public enum EventType: Equatable, Sendable { case noteOn, noteOff }

    public var type: EventType
    public var channel: UInt8
    public var pitch: UInt8
    public var velocity: UInt8
    /// Position in slots.
    public var tick: Int

    public init(type: EventType, channel: UInt8, pitch: UInt8, velocity: UInt8, tick: Int) {
        self.type = type
        self.channel = channel
        self.pitch = pitch
        self.velocity = velocity
        self.tick = tick
    }
}

/// Clamp an Int into valid MIDI byte range (0–127).
func clampByte(_ v: Int) -> UInt8 {
    UInt8(max(0, min(127, v)))
}

public extension Array where Element == ScheduledNote {
    /// All notes flattened into time-ordered note-on/note-off events.
    func toMIDIEvents() -> [MIDIEvent] {
        flatMap(\.midiEvents).sorted { $0.tick < $1.tick }
    }
}
