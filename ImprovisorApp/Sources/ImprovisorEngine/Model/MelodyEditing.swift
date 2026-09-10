//
//  MelodyEditing.swift
//  ImprovisorEngine
//
//  Slot-indexed editing of a MelodyPart. Events are stored as a run of notes
//  and rests whose positions are implied, so every edit is expressed as
//  "replace this slot range with these events", splitting whatever lies at
//  the range edges. Overwritten tails become rests, adjacent rests coalesce,
//  and the part's total length never changes unless asked (insert/remove).
//

import Foundation

public extension MelodyPart {

    /// One positioned event.
    struct Placed: Equatable, Sendable {
        public var index: Int
        public var start: Int
        public var event: MusicEvent
        public var end: Int { start + event.duration }
    }

    /// Every event with its absolute start slot.
    var placed: [Placed] {
        var out: [Placed] = []
        var t = 0
        for (i, e) in events.enumerated() {
            out.append(Placed(index: i, start: t, event: e))
            t += e.duration
        }
        return out
    }

    /// The event sounding at `slot`.
    func event(atSlot slot: Int) -> Placed? {
        guard slot >= 0 else { return nil }
        var t = 0
        for (i, e) in events.enumerated() {
            if slot < t + e.duration { return Placed(index: i, start: t, event: e) }
            t += e.duration
        }
        return nil
    }

    /// The note (not rest) whose onset is the last one at or before `slot`.
    func lastNote(atOrBefore slot: Int) -> Placed? {
        placed.last { $0.start <= slot && !$0.event.isRest }
    }

    /// A copy of the events in `range`, clipped to it (notes keep their pitch).
    func events(in range: Range<Int>) -> [MusicEvent] {
        var out: [MusicEvent] = []
        for p in placed where p.end > range.lowerBound && p.start < range.upperBound {
            let d = min(p.end, range.upperBound) - max(p.start, range.lowerBound)
            out.append(p.event.withDuration(d))
        }
        return out
    }

    // MARK: Mutations

    /// Split the event containing `slot` so that an event boundary falls at `slot`.
    /// A split note keeps its pitch on both sides (drawn tied); a rest stays a rest.
    mutating func split(at slot: Int) {
        guard let p = event(atSlot: slot), p.start < slot else { return }
        let head = p.event.withDuration(slot - p.start)
        let tail = p.event.withDuration(p.end - slot)
        events.replaceSubrange(p.index...p.index, with: [head, tail])
    }

    /// Replace `range` with `new` (padded with a rest or trimmed to the range's
    /// length). Anything previously in the range is removed; a note whose tail
    /// extends past the range keeps that tail as a rest.
    mutating func replace(range: Range<Int>, with new: [MusicEvent]) {
        guard !range.isEmpty else { return }
        fill(to: range.upperBound)
        split(at: range.lowerBound)
        split(at: range.upperBound)
        // Events fully inside the range.
        let inside = placed.filter { $0.start >= range.lowerBound && $0.end <= range.upperBound }
        guard let first = inside.first, let last = inside.last else { return }

        var replacement = fit(new, to: range.count)
        // A note overwritten in the middle leaves its tail as a rest.
        if let after = events.indices.contains(last.index + 1) ? events[last.index + 1] : nil,
           case .note = after, case .note = last.event,
           last.event.note?.pitch == after.note?.pitch, range.upperBound == last.end {
            // The tail was part of the same original note: make it a rest.
            events[last.index + 1] = .rest(Rest(duration: after.duration))
        }
        events.replaceSubrange(first.index...last.index, with: replacement)
        replacement.removeAll()
        coalesceRests()
    }

    /// Put a note at `slot` for `duration` slots (step entry).
    mutating func setNote(at slot: Int, pitch: Int, duration: Int, volume: Int = 127, spelling: Accidental = .natural) {
        replace(range: slot..<(slot + duration), with: [.note(Note(pitch: pitch, duration: duration, volume: volume, spelling: spelling))])
    }

    /// Put a rest at `slot` for `duration` slots.
    mutating func setRest(at slot: Int, duration: Int) {
        replace(range: slot..<(slot + duration), with: [.rest(Rest(duration: duration))])
    }

    /// Erase `range` to silence (keeps the timeline length).
    mutating func erase(range: Range<Int>) {
        guard !range.isEmpty else { return }
        replace(range: range, with: [.rest(Rest(duration: range.count))])
    }

    /// Remove `range` and close the gap (later events move earlier).
    mutating func remove(range: Range<Int>) {
        guard !range.isEmpty else { return }
        let clipped = range.lowerBound..<min(range.upperBound, size)
        guard !clipped.isEmpty else { return }
        split(at: clipped.lowerBound)
        split(at: clipped.upperBound)
        events.removeAll { _ in false }
        let keep = placed.filter { $0.end <= clipped.lowerBound || $0.start >= clipped.upperBound }
        events = keep.map(\.event)
        coalesceRests()
    }

    /// Insert `new` at `slot`, pushing later events later (grows the part).
    mutating func insert(_ new: [MusicEvent], at slot: Int) {
        fill(to: slot)
        split(at: slot)
        let index = placed.first { $0.start >= slot }?.index ?? events.count
        events.insert(contentsOf: new, at: index)
        coalesceRests()
    }

    /// Lengthen the note whose onset is the last at or before `slot` by
    /// `extra` slots, overwriting what follows (the `-` tie key).
    mutating func extendNote(endingAt slot: Int, by extra: Int) {
        guard extra > 0, let p = lastNote(atOrBefore: slot - 1) ?? lastNote(atOrBefore: slot), let n = p.event.note else { return }
        replace(range: p.start..<(p.end + extra), with: [.note(n.withDuration(p.event.duration + extra))])
    }

    /// Pad with a rest so the part is at least `total` slots long.
    mutating func fill(to total: Int) {
        let missing = total - size
        guard missing > 0 else { return }
        events.append(.rest(Rest(duration: missing)))
        coalesceRests()
    }

    /// Cut the part to exactly `total` slots (pads if shorter).
    mutating func truncate(to total: Int) {
        fill(to: total)
        if size > total {
            split(at: total)
            events = placed.filter { $0.end <= total }.map(\.event)
        }
    }

    /// Transpose only the notes in `range`.
    mutating func transpose(range: Range<Int>, by semitones: Int) {
        guard semitones != 0 else { return }
        for p in placed where p.start < range.upperBound && p.end > range.lowerBound {
            if case let .note(n) = p.event {
                events[p.index] = .note(Note(pitch: max(0, min(127, n.pitch + semitones)), duration: n.duration,
                                             volume: n.volume, spelling: n.spelling))
            }
        }
    }

    /// Apply `transform` to every note overlapping `range`.
    mutating func mapNotes(in range: Range<Int>, _ transform: (Note) -> Note) {
        for p in placed where p.start < range.upperBound && p.end > range.lowerBound {
            if case let .note(n) = p.event { events[p.index] = .note(transform(n)) }
        }
    }

    /// Merge runs of adjacent rests into one rest.
    mutating func coalesceRests() {
        var out: [MusicEvent] = []
        for e in events {
            if case let .rest(r) = e, case let .rest(prev)? = out.last {
                out[out.count - 1] = .rest(Rest(duration: prev.duration + r.duration))
            } else if e.duration > 0 {
                out.append(e)
            }
        }
        events = out
    }

    // MARK: Helpers

    /// `new` trimmed or rest-padded to exactly `length` slots.
    private func fit(_ new: [MusicEvent], to length: Int) -> [MusicEvent] {
        var out: [MusicEvent] = []
        var total = 0
        for e in new {
            guard total < length else { break }
            let d = min(e.duration, length - total)
            if d > 0 { out.append(e.withDuration(d)); total += d }
        }
        if total < length { out.append(.rest(Rest(duration: length - total))) }
        return out
    }
}

public extension MusicEvent {
    /// The same event with a different duration.
    func withDuration(_ d: Int) -> MusicEvent {
        switch self {
        case let .note(n): return .note(n.withDuration(d))
        case .rest: return .rest(Rest(duration: d))
        }
    }
}

public extension Note {
    func withDuration(_ d: Int) -> Note { Note(pitch: pitch, duration: d, volume: volume, spelling: spelling) }

    /// A black key spelled `.natural` has no letter name of its own; give it the
    /// key's preference (sharps in sharp keys, flats otherwise) so the note
    /// survives a save/load round trip unchanged.
    func withResolvedSpelling(key: Key) -> Note {
        let pc = ((pitch % 12) + 12) % 12
        guard spelling == .natural, [1, 3, 6, 8, 10].contains(pc) else { return self }
        var copy = self
        copy.spelling = key.index > 0 ? .sharp : .flat
        return copy
    }
    /// Flip between the sharp and flat spelling of a black key (no-op on white keys).
    func enharmonicToggled() -> Note {
        let pc = ((pitch % 12) + 12) % 12
        let black = [1, 3, 6, 8, 10].contains(pc)
        var copy = self
        if black {
            copy.spelling = spelling == .flat ? .sharp : (spelling == .sharp ? .flat : .sharp)
        } else if pc == 0 || pc == 5 {
            copy.spelling = spelling == .sharp ? .natural : .sharp   // b# / e#
        } else if pc == 4 || pc == 11 {
            copy.spelling = spelling == .flat ? .natural : .flat     // fb / cb
        }
        return copy
    }
}
