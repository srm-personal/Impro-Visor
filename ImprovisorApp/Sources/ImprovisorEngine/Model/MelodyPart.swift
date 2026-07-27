//
//  MelodyPart.swift
//  ImprovisorEngine
//
//  An ordered sequence of notes/rests (a melody or a generated solo). The slot
//  position of each event is the running sum of the durations before it, so the
//  part is stored simply as its event list. Ports the data behavior of
//  imp/data/MelodyPart.
//

import Foundation

public struct MelodyPart: Equatable {
    public private(set) var events: [MusicEvent]

    public init(events: [MusicEvent] = []) {
        self.events = events
    }

    /// Total length in slots.
    public var size: Int { events.reduce(0) { $0 + $1.duration } }

    /// Number of events (notes and rests).
    public var count: Int { events.count }

    /// Number of sounding notes (excludes rests).
    public var noteCount: Int { events.lazy.filter { !$0.isRest }.count }

    /// Just the sounding notes.
    public var notes: [Note] { events.compactMap(\.note) }

    public mutating func append(_ event: MusicEvent) {
        events.append(event)
    }

    /// This melody transposed by a number of semitones (rests unaffected).
    public func transposed(by semitones: Int) -> MelodyPart {
        MelodyPart(events: events.map { event in
            switch event {
            case let .note(n): return .note(n.transposed(by: semitones))
            case .rest: return event
            }
        })
    }
}
