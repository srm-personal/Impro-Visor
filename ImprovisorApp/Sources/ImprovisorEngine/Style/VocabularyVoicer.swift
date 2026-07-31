//
//  VocabularyVoicer.swift
//  ImprovisorEngine
//
//  Port of the vocabulary branch of imp/style/stylePatterns/ChordPattern
//  (findVoicing / getVoicingAndExtensionList / chooseVoicings / placeVoicing /
//  averageLeap) plus imp/data/ChordForm.getVoicings / generateVoicings.
//
//  Given a chord, the style's voicing-type, the chord register, and the previous
//  chord's voicing, it selects one of the vocabulary's named voicings — placed
//  near the previous chord and within range, minimizing average voice-leading
//  motion — or, if none fit, synthesizes one from the chord's priority tones.
//
//  Approximation: ChordForm.generateVoicings uses Key/enharmonic spelling to drop
//  the root; here we drop the root pitch class and stack priority pitch classes.
//  This fallback is only reached when no authored voicing fits the register.
//

import Foundation

public enum VocabularyVoicer {

    /// The `type` value from `ChordForm.getVoicings`' wildcard.
    private static let wildcard = "any"
    private static let priorityPrefixMax = 5

    /// A voicing plus its extension, as absolute MIDI.
    private struct Candidate { var notes: [Int]; var ext: [Int] }

    /// Choose and place a voicing for `chord`. `previous` is the prior chord's
    /// voicing (empty for the first chord). Returns the combined, sorted MIDI
    /// notes (voicing + extension), or `nil` if nothing fits the register.
    public static func findVoicing(chord: ChordSymbol, previous: [Int],
                                   low: Int, high: Int, type: String,
                                   rng: inout SeededGenerator) -> [Int]? {
        var chosen = chooseVoicings(previous, getVoicings(chord, type: type), low, high)
        if chosen.isEmpty {
            chosen = chooseVoicings(previous, generateVoicings(chord), low, high)
        }
        guard !chosen.isEmpty else { return nil }
        let pick = chosen[Int.random(in: 0..<chosen.count, using: &rng)]
        return (pick.notes + pick.ext).sorted()
    }

    // MARK: - Candidate sources

    /// The chord's authored voicings, transposed to its root and filtered by the
    /// style's voicing-type (`any` / `""` are wildcards). Port of
    /// `ChordForm.getVoicings`.
    private static func getVoicings(_ chord: ChordSymbol, type: String) -> [Candidate] {
        guard let form = chord.form else { return [] }
        return form.voicings(root: chord.root)
            .filter { type.isEmpty || $0.type == type || type == wildcard }
            .map { Candidate(notes: $0.notes, ext: $0.ext) }
    }

    /// Synthesize voicings from the chord's priority tones (root dropped), each a
    /// permutation stacked ascending. Port of `ChordForm.generateVoicings`.
    private static func generateVoicings(_ chord: ChordSymbol) -> [Candidate] {
        var tones = chord.form?.priorityTones(root: chord.root) ?? []
        if tones.isEmpty { tones = chord.chordTones }
        guard !tones.isEmpty else { return [] }
        // Drop the root pitch class (enhDrop), keep at most PRIORITY_PREFIX_MAX.
        let rootSemis = chord.root.semitones
        var seen = Set<Int>()
        var semis: [Int] = []
        for t in tones where t.semitones != rootSemis {
            if seen.insert(t.semitones).inserted { semis.append(t.semitones) }
        }
        if semis.isEmpty { semis = tones.map(\.semitones) }
        semis = Array(semis.prefix(priorityPrefixMax))

        var candidates: [Candidate] = []
        for perm in permutations(semis) {
            var voicing: [Int] = []
            var last = Constants.CMIDI + perm[0]
            voicing.append(last)
            for pc in perm.dropFirst() {
                var note = Constants.CMIDI + pc
                while note < last { note += 12 }
                last = note
                voicing.append(note)
            }
            candidates.append(Candidate(notes: voicing, ext: []))
        }
        return candidates
    }

    // MARK: - Choosing / placing (port of ChordPattern)

    /// Keep the voicings with the smallest average leap from `lastChord`, placed
    /// within range. Faithfully preserves Java's quirk: when a new minimum leap is
    /// found the already-appended (larger-leap) voicings are *not* removed.
    private static func chooseVoicings(_ lastChord: [Int], _ candidates: [Candidate],
                                       _ low: Int, _ high: Int) -> [Candidate] {
        var good: [Candidate] = []
        var smallest = 127
        for candidate in candidates {
            guard let placed = placeVoicing(lastChord, candidate.notes, candidate.ext, low, high)
            else { continue }
            let leap = averageLeap(placed.notes + placed.ext, lastChord)
            if leap < smallest {
                smallest = leap
                good.append(placed)
            } else if leap == smallest {
                good.append(placed)
            }
        }
        return good
    }

    /// Place `voicing` (and its `extension`) near `lastChord` and within range,
    /// shifting the extension by the same amount. `nil` if it can't fit.
    private static func placeVoicing(_ lastChord: [Int], _ voicing: [Int], _ ext: [Int],
                                     _ low: Int, _ high: Int) -> Candidate? {
        guard let oldFirst = voicing.first else { return nil }
        guard let placed = placeVoicing(lastChord, voicing, low, high) else { return nil }
        let diff = placed[0] - oldFirst
        return Candidate(notes: placed, ext: ext.map { $0 + diff })
    }

    private static func placeVoicing(_ lastChord: [Int], _ voicing: [Int],
                                     _ low: Int, _ high: Int) -> [Int]? {
        let last = lastChord.isEmpty ? [low, high] : lastChord
        guard let lastNote = last.first, let voicingNote = voicing.first else { return nil }

        // Pitch-class ascending distance from lastNote to voicingNote, in [1,12].
        var dist = ((voicingNote - lastNote) % 12 + 12) % 12
        if dist == 0 { dist = 12 }
        var v = dist >= 6 ? placeBelow(lastNote, voicing) : placeAbove(lastNote, voicing)

        var lowest = v.min() ?? 0
        var highest = v.max() ?? 0
        while lowest < low {
            v = v.map { $0 + 12 }
            lowest = v.min() ?? 0
            highest = v.max() ?? 0
            if highest > high { return nil }
        }
        while highest > high {
            v = v.map { $0 - 12 }
            lowest = v.min() ?? 0
            highest = v.max() ?? 0
            if lowest < low { return nil }
        }
        return v
    }

    /// Place `voicing` just above `lastNote` (its first note). Port of
    /// `placeVoicingAbove`.
    private static func placeAbove(_ lastNote: Int, _ voicing: [Int]) -> [Int] {
        let difference = lastNote - voicing[0]
        if difference > 0 {
            let octaves = difference / 12 + 1
            return voicing.map { $0 + 12 * octaves }
        } else if difference <= -12 {
            let octaves = difference / 12   // negative; Swift & Java truncate toward 0
            return voicing.map { $0 + 12 * octaves }
        }
        return voicing
    }

    /// Place `voicing` just below `lastNote`. Port of `placeVoicingBelow`.
    private static func placeBelow(_ lastNote: Int, _ voicing: [Int]) -> [Int] {
        let difference = lastNote - voicing[0]
        if difference < 0 {
            let octaves = difference / 12 - 1
            return voicing.map { $0 + 12 * octaves }
        } else if difference >= 12 {
            let octaves = difference / 12
            return voicing.map { $0 + 12 * octaves }
        }
        return voicing
    }

    /// Average smallest leap from each note of `chord2` to `chord1`. Reference
    /// (`chord2`) empty → 0 (matches Java's 0/0 → 0 on the first chord).
    private static func averageLeap(_ chord1: [Int], _ chord2: [Int]) -> Int {
        guard !chord2.isEmpty else { return 0 }
        let sum = chord2.reduce(0) { $0 + smallestLeap(chord1, $1) }
        return sum / chord2.count
    }

    private static func smallestLeap(_ chord: [Int], _ note: Int) -> Int {
        chord.map { abs($0 - note) }.min() ?? 127
    }

    // MARK: - Permutations

    private static func permutations(_ items: [Int]) -> [[Int]] {
        guard items.count > 1 else { return [items] }
        var result: [[Int]] = []
        for (i, item) in items.enumerated() {
            var rest = items
            rest.remove(at: i)
            for tail in permutations(rest) { result.append([item] + tail) }
        }
        return result
    }
}
