//
//  NoteSerializer.swift
//  ImprovisorEngine
//
//  Writes notes and rests back out as leadsheet tokens (`c#+4+8`, `r8/3`) — the
//  inverse of `NoteSymbol.parse`. Ports `Note.toLeadsheet` and
//  `Note.getDurationString`, including the two-decomposition trick that picks
//  the shorter of "plain values first" vs "triplets first".
//

import Foundation

public enum NoteSerializer {

    // MARK: Pitch names (Java Note.flat/sharp/naturalPitchFromMidi)

    private static let flatNames = ["c", "db", "d", "eb", "fb", "f", "gb", "g", "ab", "a", "bb", "cb"]
    private static let sharpNames = ["b#", "c#", "d", "d#", "e", "e#", "f#", "g", "g#", "a", "a#", "b"]

    /// The pitch-class name for a MIDI pitch under a spelling preference. A
    /// `.natural` black key falls back to Impro-Visor's canonical spelling
    /// (flats, except `f#`), so generated notes always get a valid name.
    public static func pitchClassName(_ pitch: Int, spelling: Accidental) -> String {
        let pc = ((pitch % 12) + 12) % 12
        switch spelling {
        case .sharp: return sharpNames[pc]
        case .flat: return flatNames[pc]
        case .natural: return PitchClass.forMidi(pc).name
        }
    }

    /// Leadsheet pitch token without duration: name plus `+`/`-` octave marks
    /// relative to the middle-C octave (MIDI 60–71).
    public static func pitchToken(_ pitch: Int, spelling: Accidental) -> String {
        var out = pitchClassName(pitch, spelling: spelling)
        // Java: octave = pitch / 12 - 5 (middle C octave = 0).
        let octave = pitch / 12 - 5
        if octave > 0 { out += String(repeating: "+", count: octave) }
        if octave < 0 { out += String(repeating: "-", count: -octave) }
        return out
    }

    // MARK: Durations (Java Note.getDurationString)

    private struct Term { let slots: Int; let text: String; let exact: Bool }

    private static let plainFirst: [Term] = [
        Term(slots: 480, text: "1", exact: false),
        Term(slots: 240, text: "2", exact: false),
        Term(slots: 120, text: "4", exact: false),
        Term(slots: 96, text: "4/5", exact: true),
        Term(slots: 60, text: "8", exact: false),
        Term(slots: 48, text: "8/5", exact: true),
        Term(slots: 30, text: "16", exact: false),
        Term(slots: 24, text: "16/5", exact: true),
        Term(slots: 15, text: "32", exact: false),
        Term(slots: 12, text: "32/5", exact: true),
        Term(slots: 160, text: "2/3", exact: false),
        Term(slots: 80, text: "4/3", exact: false),
        Term(slots: 40, text: "8/3", exact: false),
        Term(slots: 20, text: "16/3", exact: false),
        Term(slots: 10, text: "32/3", exact: false),
        Term(slots: 8, text: "60", exact: false),
        Term(slots: 4, text: "120", exact: false),
        Term(slots: 2, text: "240", exact: false),
        Term(slots: 1, text: "480", exact: false)
    ]

    private static let tripletsFirst: [Term] = [
        Term(slots: 160, text: "2/3", exact: false),
        Term(slots: 80, text: "4/3", exact: false),
        Term(slots: 40, text: "8/3", exact: false),
        Term(slots: 20, text: "16/3", exact: false),
        Term(slots: 10, text: "32/3", exact: false),
        Term(slots: 480, text: "1", exact: false),
        Term(slots: 240, text: "2", exact: false),
        Term(slots: 120, text: "4", exact: false),
        Term(slots: 60, text: "8", exact: false),
        Term(slots: 30, text: "16", exact: false),
        Term(slots: 15, text: "32", exact: false),
        Term(slots: 8, text: "60", exact: false),
        Term(slots: 4, text: "120", exact: false),
        Term(slots: 2, text: "240", exact: false),
        Term(slots: 1, text: "480", exact: false)
    ]

    private static func decompose(_ value: Int, terms: [Term]) -> [String] {
        var remaining = value
        var parts: [String] = []
        for term in terms {
            if term.exact && remaining % term.slots != 0 { continue }
            while remaining >= term.slots {
                parts.append(term.text)
                remaining -= term.slots
            }
        }
        return parts
    }

    /// The `+`-joined duration string for a slot count (`""` for ≤ 0). Always
    /// exact: the residual terms 60/120/240/480 cover every integer.
    public static func durationString(_ slots: Int) -> String {
        guard slots > 0 else { return "" }
        let a = decompose(slots, terms: plainFirst).joined(separator: "+")
        let b = decompose(slots, terms: tripletsFirst).joined(separator: "+")
        return a.count <= b.count ? a : b
    }

    // MARK: Tokens

    /// One leadsheet token for a note or rest.
    public static func token(_ event: MusicEvent) -> String {
        switch event {
        case let .note(n):
            return pitchToken(n.pitch, spelling: n.spelling) + durationString(n.duration)
        case let .rest(r):
            return "r" + durationString(r.duration)
        }
    }

    /// All tokens of a melody part, in order.
    public static func tokens(_ part: MelodyPart) -> [String] {
        part.events.map(token)
    }

    /// Melody text with one line per measure's worth of events (a line breaks
    /// once the accumulated duration reaches a measure). Every line starts with a
    /// space, as the Java writer does.
    public static func melodyText(_ part: MelodyPart, slotsPerMeasure: Int) -> String {
        var lines: [String] = []
        var current: [String] = []
        var accumulated = 0
        for event in part.events {
            if slotsPerMeasure > 0, accumulated >= slotsPerMeasure, !current.isEmpty {
                lines.append(" " + current.joined(separator: " "))
                current = []
                accumulated -= slotsPerMeasure
                // Very long notes may span several measures.
                while accumulated >= slotsPerMeasure { accumulated -= slotsPerMeasure }
            }
            current.append(token(event))
            accumulated += event.duration
        }
        if !current.isEmpty { lines.append(" " + current.joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }
}
