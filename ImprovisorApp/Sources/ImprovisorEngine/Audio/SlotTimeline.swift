//
//  SlotTimeline.swift
//  ImprovisorEngine
//
//  Phase 3 (Transport): a slot-space twin of PlaybackTimeline. Events are kept
//  in musical slots (not seconds) so a live Transport can advance its clock at
//  the CURRENT tempo every tick instead of baking a tempo-derived wall-clock
//  time into each event up front. `PlaybackTimeline.events` is now a thin
//  wrapper that maps these slots to seconds for callers (tests, the SMF-timed
//  preview) that just want a fixed-tempo, non-live timeline.
//
//  Ordering rules are identical to the old PlaybackTimeline: program changes at
//  slot 0 on loop 0 only, then sorted by slot, and at equal slots program <
//  noteOff < noteOn (so a same-instant off/on pair never clips the new note).
//

import Foundation

/// One timed message in a flattened, slot-space playback timeline.
public struct SlotEvent: Equatable, Sendable {
    /// Absolute position in slots from the start of playback (loop 0, slot 0).
    public var slot: Int
    public var channel: UInt8
    public var kind: PlaybackEvent.Kind

    public init(slot: Int, channel: UInt8, kind: PlaybackEvent.Kind) {
        self.slot = slot
        self.channel = channel
        self.kind = kind
    }

    /// Sort key so that, at the same slot, program changes and note-offs come
    /// before note-ons (avoids clipping a note-on with a simultaneous off).
    fileprivate var order: Int {
        switch kind {
        case .program: return 0
        case .noteOff: return 1
        case .noteOn: return 2
        }
    }
}

public enum SlotTimeline {
    /// Flatten tracks into a slot-ordered event list. `loops` repeats the whole
    /// set, offsetting each repeat by `formSlots` (0 = derive from the tracks).
    public static func events(tracks: [MIDITrack], loops: Int = 1, formSlots: Int = 0) -> [SlotEvent] {
        let span = formSlots > 0 ? formSlots : (tracks.flatMap { $0.notes }
            .map { $0.startTick + max(1, $0.duration) }.max() ?? 0)
        var events: [SlotEvent] = []

        for loop in 0..<max(1, loops) {
            let slotOffset = loop * span
            for track in tracks {
                let ch = track.channel & 0x0F
                if let program = track.program, loop == 0 {
                    events.append(SlotEvent(slot: 0, channel: ch, kind: .program(program & 0x7F)))
                }
                for note in track.notes {
                    let onSlot = note.startTick + slotOffset
                    let offSlot = note.startTick + max(1, note.duration) + slotOffset
                    events.append(SlotEvent(slot: onSlot, channel: ch,
                                             kind: .noteOn(pitch: clampByte(note.pitch),
                                                           velocity: clampByte(note.velocity))))
                    events.append(SlotEvent(slot: offSlot, channel: ch,
                                             kind: .noteOff(pitch: clampByte(note.pitch))))
                }
            }
        }

        events.sort { a, b in a.slot != b.slot ? a.slot < b.slot : a.order < b.order }
        return events
    }
}
