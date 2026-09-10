//
//  ChordTransposition.swift
//  ImprovisorEngine
//
//  Transposing chord symbols and progressions, re-spelling roots for the key
//  (flats in flat keys and C, sharps in sharp keys), plus the vocabulary's
//  list of chord types for autocomplete.
//

import Foundation

public extension PitchClass {
    private static let sharpSpellings = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatSpellings = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// Chord-root spelling for a semitone count under a spelling preference.
    static func chordSpelling(semitones: Int, preferSharp: Bool) -> String {
        let pc = ((semitones % 12) + 12) % 12
        return preferSharp ? sharpSpellings[pc] : flatSpellings[pc]
    }
}

public extension ChordSymbol {
    /// This chord moved by `semitones`, root and bass re-spelled for `key`
    /// (sharps when the key has sharps, otherwise flats). Resolved against
    /// `vocabulary` so the result carries its form.
    func transposed(by semitones: Int, key: Key, vocabulary: Vocabulary) -> ChordSymbol {
        guard !isNoChord else { return self }
        let preferSharp = key.index > 0
        let newRoot = PitchClass.chordSpelling(semitones: root.semitones + semitones, preferSharp: preferSharp)
        var newName = newRoot + type
        if bass != root {
            newName += "/" + PitchClass.chordSpelling(semitones: bass.semitones + semitones, preferSharp: preferSharp)
        }
        return ChordSymbol.parse(newName, vocabulary: vocabulary) ?? self
    }
}

public extension ChordPart {
    /// Every chord transposed; durations and sections unchanged.
    func transposed(by semitones: Int, key: Key, vocabulary: Vocabulary) -> ChordPart {
        var out = ChordPart(info: info)
        for e in entries {
            out.append(e.symbol.transposed(by: semitones, key: key, vocabulary: vocabulary), duration: e.duration)
        }
        return out
    }

    /// Only the chords overlapping `range` transposed (chords are split at the
    /// range edges so the rest of the progression is untouched).
    func transposed(range: Range<Int>, by semitones: Int, key: Key, vocabulary: Vocabulary) -> ChordPart {
        let inside = slice(range).transposed(by: semitones, key: key, vocabulary: vocabulary)
        return replacing(range: range, with: inside)
    }
}

public extension Vocabulary {
    /// All chord type suffixes the vocabulary knows (`""`, `7`, `m7`, `maj7`, …),
    /// including aliases, sorted for display.
    var chordTypes: [String] {
        var out = Set<String>()
        for name in allChordFormNames where name.hasPrefix("C") {
            out.insert(String(name.dropFirst()))
        }
        return out.sorted { a, b in a.count != b.count ? a.count < b.count : a < b }
    }
}

public extension ChordPart {
    /// This progression with `range` replaced by `new` (re-based at the range
    /// start, trimmed/padded to the range; empty `new` = hold the previous chord).
    func replacing(range: Range<Int>, with new: ChordPart) -> ChordPart {
        guard !range.isEmpty, size > 0 else { return self }
        var out = ChordPart(info: info)
        let clipped = range.lowerBound..<min(range.upperBound, size)
        // Before.
        for e in slice(0..<clipped.lowerBound).entries { out.append(e.symbol, duration: e.duration) }
        // Replacement.
        var filled = 0
        for e in new.entries where filled < clipped.count {
            let d = min(e.duration, clipped.count - filled)
            out.append(e.symbol, duration: d)
            filled += d
        }
        if filled < clipped.count {
            let hold = out.entries.last?.symbol ?? .noChord
            out.append(hold, duration: clipped.count - filled)
        }
        // After.
        for e in slice(clipped.upperBound..<size).entries { out.append(e.symbol, duration: e.duration) }
        return out.mergingRepeats()
    }

    /// Adjacent identical chords merged into one entry.
    func mergingRepeats() -> ChordPart {
        var out = ChordPart(info: info)
        for e in entries {
            if let last = out.entries.last, last.symbol == e.symbol {
                out.extendLast(by: e.duration)
            } else {
                out.append(e.symbol, duration: e.duration)
            }
        }
        return out
    }
}
