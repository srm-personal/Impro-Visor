//
//  NoteValue.swift
//  LeadsheetKit
//
//  Notated rhythmic values and the splitter that turns slot durations into
//  drawable pieces. A melody event may span bar lines or have a duration with
//  no single symbol (`c4+8/3`); it is drawn as several tied pieces.
//

import Foundation
import ImprovisorEngine

public struct NoteValue: Equatable, Hashable, Sendable {
    public enum Base: Int, Equatable, Hashable, Sendable, CaseIterable {
        case whole = 480, half = 240, quarter = 120, eighth = 60, sixteenth = 30, thirtySecond = 15
    }

    public var base: Base
    public var dots: Int
    /// 1 = none, 3 = triplet (two thirds of the plain value).
    public var tuplet: Int

    public init(_ base: Base, dots: Int = 0, tuplet: Int = 1) {
        self.base = base
        self.dots = dots
        self.tuplet = tuplet
    }

    /// Slot duration of the symbol.
    public var slots: Int {
        var d = base.rawValue
        var inc = d
        for _ in 0..<dots { inc /= 2; d += inc }
        if tuplet == 3 { d = d * 2 / 3 }
        return d
    }

    /// Flags / beams: 0 for quarter and longer, 1 eighth, 2 sixteenth, 3 thirty-second.
    public var flags: Int {
        switch base {
        case .whole, .half, .quarter: return 0
        case .eighth: return 1
        case .sixteenth: return 2
        case .thirtySecond: return 3
        }
    }

    public var isFilled: Bool { base.rawValue <= Base.quarter.rawValue }
    public var hasStem: Bool { base != .whole }

    /// All values the splitter may emit, longest first. Plain and single-dotted
    /// values, plus triplets of half … thirty-second.
    public static let candidates: [NoteValue] = {
        var all: [NoteValue] = []
        for base in Base.allCases {
            all.append(NoteValue(base))
            if base != .thirtySecond { all.append(NoteValue(base, dots: 1)) }
            if base != .whole { all.append(NoteValue(base, tuplet: 3)) }
        }
        return all.sorted { $0.slots > $1.slots }
    }()
}

/// One drawable note or rest symbol.
public struct NotePiece: Equatable, Sendable {
    /// Index of the source event in the melody part.
    public var eventIndex: Int
    /// Absolute start slot.
    public var start: Int
    /// Actual slots this piece occupies (may exceed `value.slots` by an
    /// unrepresentable residue, which is absorbed silently).
    public var duration: Int
    public var value: NoteValue
    public var isRest: Bool
    public var pitch: Int
    public var spelling: Accidental
    /// This piece continues into the next piece of the same event (tie).
    public var tiedToNext: Bool

    public var end: Int { start + duration }
}

public enum DurationSplitter {
    /// Smallest value we draw; residues below it are absorbed.
    static let minimumSlots = 10

    /// Greedy decomposition of a duration into notated values, longest first,
    /// never leaving an undrawable remainder.
    public static func values(for duration: Int) -> [NoteValue] {
        var remaining = duration
        var out: [NoteValue] = []
        while remaining >= minimumSlots {
            let clean = NoteValue.candidates.first { c in
                c.slots <= remaining && (remaining - c.slots == 0 || remaining - c.slots >= minimumSlots)
            }
            guard let pick = clean ?? NoteValue.candidates.first(where: { $0.slots <= remaining }) else { break }
            out.append(pick)
            remaining -= pick.slots
        }
        if out.isEmpty, duration > 0 { out.append(NoteValue(.thirtySecond, tuplet: 3)) }
        return out
    }

    /// Split `[start, start+duration)` at bar lines.
    public static func barSegments(start: Int, duration: Int, slotsPerMeasure: Int) -> [(start: Int, duration: Int)] {
        guard slotsPerMeasure > 0, duration > 0 else { return [(start, max(0, duration))] }
        var out: [(Int, Int)] = []
        var s = start
        let end = start + duration
        while s < end {
            let barEnd = (s / slotsPerMeasure + 1) * slotsPerMeasure
            let e = min(end, barEnd)
            out.append((s, e - s))
            s = e
        }
        return out
    }

    /// All pieces for a melody part.
    public static func split(_ part: MelodyPart, slotsPerMeasure: Int) -> [NotePiece] {
        var pieces: [NotePiece] = []
        var t = 0
        for (index, event) in part.events.enumerated() {
            let duration = event.duration
            defer { t += duration }
            guard duration > 0 else { continue }
            let isRest = event.isRest
            let pitch = event.note?.pitch ?? 0
            let spelling = event.note?.spelling ?? .natural

            var eventPieces: [NotePiece] = []
            for segment in barSegments(start: t, duration: duration, slotsPerMeasure: slotsPerMeasure) {
                let vals = values(for: segment.duration)
                var s = segment.start
                let symbolTotal = vals.reduce(0) { $0 + $1.slots }
                for (i, v) in vals.enumerated() {
                    // The last value of the segment absorbs any residue.
                    let d = i == vals.count - 1 ? v.slots + (segment.duration - symbolTotal) : v.slots
                    eventPieces.append(NotePiece(eventIndex: index, start: s, duration: d, value: v,
                                                 isRest: isRest, pitch: pitch, spelling: spelling,
                                                 tiedToNext: true))
                    s += d
                }
            }
            if !eventPieces.isEmpty {
                eventPieces[eventPieces.count - 1].tiedToNext = false
            }
            if isRest { for i in eventPieces.indices { eventPieces[i].tiedToNext = false } }
            pieces += eventPieces
        }
        return pieces
    }
}
