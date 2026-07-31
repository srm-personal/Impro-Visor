//
//  VoicingDistanceCalculator.swift
//  ImprovisorEngine
//
//  Port of imp/voicing/VoicingDistanceCalculator (Daniel Scanteianu). Measures how
//  far apart two voicings are, for voice-leading analysis and tests.
//

import Foundation

public enum VoicingDistanceCalculator {

    /// The distance between two voicings: for each note in one voicing, the
    /// smallest semitone gap to any note in the other; summed in both directions,
    /// and the larger of the two directional sums is returned (a symmetric,
    /// insertion/deletion-aware metric). Empty voicings contribute 0.
    public static func distance(_ a: [Int], _ b: [Int]) -> Int {
        func directedSum(_ from: [Int], _ to: [Int]) -> Int {
            guard !to.isEmpty else { return 0 }
            return from.reduce(0) { sum, i in
                sum + (to.map { abs(i - $0) }.min() ?? 0)
            }
        }
        return max(directedSum(a, b), directedSum(b, a))
    }

    /// The number of notes in `a` that are not present (same MIDI value) in `b`.
    public static func notesChanged(_ a: [Int], _ b: [Int]) -> Int {
        a.reduce(0) { $0 + (b.contains($1) ? 0 : 1) }
    }
}
