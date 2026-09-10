//
//  ChordGuesser.swift
//  ImprovisorEngine
//
//  Names a chord from a set of sounding pitches (MIDI keyboard chord entry):
//  tries every root and every vocabulary form, preferring exact spellings and
//  the lowest sounding note as root.
//

import Foundation

public enum ChordGuesser {
    private static func canonicalTypeLength(_ form: ChordForm) -> Int { max(0, form.name.count - 1) }

    /// The best chord name for `pitches`, or nil when nothing matches.
    public static func name(forPitches pitches: [Int], vocabulary: Vocabulary, preferSharp: Bool = false) -> String? {
        let classes = Set(pitches.map { (($0 % 12) + 12) % 12 })
        guard classes.count >= 2, let lowest = pitches.min() else { return nil }
        let lowestClass = ((lowest % 12) + 12) % 12

        struct Candidate { let name: String; let score: Int }
        var best: Candidate?
        for root in 0..<12 {
            let rootName = PitchClass.chordSpelling(semitones: root, preferSharp: preferSharp)
            for type in vocabulary.chordTypes {
                guard let form = vocabulary.chordForm(named: "C" + type) else { continue }
                let spell = Set(form.spell.map { ($0.semitones + root) % 12 })
                guard spell == classes else { continue }
                // Prefer: the lowest note is the root, then shorter names (canonical spellings).
                var score = 0
                if root == lowestClass { score += 10 }
                score -= canonicalTypeLength(form)
                // Report the canonical form name (e.g. m7 rather than the alias -).
                var canonicalType = form.name.hasPrefix("C") ? String(form.name.dropFirst()) : type
                if canonicalType == "M" { canonicalType = "" }   // a major triad is written as its bare root
                if best == nil || score > best!.score { best = Candidate(name: rootName + canonicalType, score: score) }
            }
        }
        return best?.name
    }
}
