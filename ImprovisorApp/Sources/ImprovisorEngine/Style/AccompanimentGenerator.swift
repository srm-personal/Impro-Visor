//
//  AccompanimentGenerator.swift
//  ImprovisorEngine
//
//  Turns a chord progression + a Style into scheduled MIDI notes for bass,
//  chord comping, and drums. Ports the rendering logic of imp/style/Style
//  (addToBassline, addToChordPart-style comping, and drum applyRules) plus the
//  weighted pattern selection of Style.getPattern.
//
//  Pattern rule tokens are `<letter><suffix>` where the letter selects a note
//  type and the suffix is a duration (for note/rest tokens) or a number
//  (for `V` velocity tokens):
//    Bass:  B/X/= root · C chord tone · S scale/step tone · A approach ·
//           N next root · R rest · V velocity
//    Chord: X strike voicing · R rest · V velocity
//    Drums: X strike · R rest · V velocity
//
//  Swing feel is NOT applied here — events carry straight slot positions and
//  the audio scheduler (Step 7) applies the style's swing ratio.
//

import Foundation

/// The generated accompaniment: scheduled notes per track.
public struct Accompaniment: Equatable, Sendable {
    public var bass: [ScheduledNote]
    public var chords: [ScheduledNote]
    public var drums: [ScheduledNote]

    public init(bass: [ScheduledNote], chords: [ScheduledNote], drums: [ScheduledNote]) {
        self.bass = bass
        self.chords = chords
        self.drums = drums
    }

    public var allNotes: [ScheduledNote] { bass + chords + drums }

    public var bassEvents: [MIDIEvent] { bass.toMIDIEvents() }
    public var chordEvents: [MIDIEvent] { chords.toMIDIEvents() }
    public var drumEvents: [MIDIEvent] { drums.toMIDIEvents() }
    public var allEvents: [MIDIEvent] { allNotes.toMIDIEvents() }
}

public struct AccompanimentGenerator {
    public static let bassChannel: UInt8 = 0
    public static let chordChannel: UInt8 = 1

    let style: Style

    // Resolved register bounds (MIDI).
    private let bassLow: Int
    private let bassHigh: Int
    private let bassBase: Int
    private let chordLow: Int
    private let chordHigh: Int

    public init(style: Style) {
        self.style = style
        self.bassLow = Register.midi(ofNoteName: style.bassLow, fallback: 43)
        self.bassHigh = Register.midi(ofNoteName: style.bassHigh, fallback: 60)
        self.bassBase = Register.midi(ofNoteName: style.bassBase, fallback: 43)
        self.chordLow = Register.midi(ofNoteName: style.chordLow, fallback: 55)
        self.chordHigh = Register.midi(ofNoteName: style.chordHigh, fallback: 72)
    }

    /// Generate accompaniment for a chord progression. `seed` makes the
    /// (otherwise random) pattern/tone choices reproducible.
    public func generate(chordPart: ChordPart, seed: UInt64 = 0) -> Accompaniment {
        var rng = SeededGenerator(seed: seed)
        let bass = generateBass(chordPart, &rng)
        let chords = generateChords(chordPart, &rng)
        let drums = generateDrums(totalSlots: chordPart.size, &rng)
        return Accompaniment(bass: bass, chords: chords, drums: drums)
    }

    // MARK: Bass

    private func generateBass(_ chordPart: ChordPart, _ rng: inout SeededGenerator) -> [ScheduledNote] {
        var notes: [ScheduledNote] = []
        var previous = bassBase
        let entries = chordPart.entries

        for (i, entry) in entries.enumerated() {
            let chord = entry.symbol
            let next = i + 1 < entries.count ? entries[i + 1].symbol : chord
            var t = entry.start
            var remaining = entry.duration

            while remaining > 0 {
                guard let pattern = selectPattern(style.bassPatterns, fitting: remaining, &rng) else {
                    // No pattern fits: hold the root for the rest of the chord.
                    let midi = Register.place(pitchClass: chord.bass.semitones,
                                              near: previous, low: bassLow, high: bassHigh)
                    notes.append(ScheduledNote(pitch: midi, velocity: 85, startTick: t,
                                               duration: remaining, channel: Self.bassChannel))
                    previous = midi
                    break
                }

                var volume = 85
                for token in pattern.rules {
                    let (letter, suffix) = splitToken(token)
                    if letter == "V" || letter == "v" {
                        volume = Int(suffix) ?? volume
                        continue
                    }
                    let dur = Duration.slots(suffix)
                    if letter == "R" || letter == "r" {
                        t += dur
                        continue
                    }
                    guard let pc = bassPitchClass(for: letter, chord: chord, next: next,
                                                  previous: previous, &rng) else {
                        t += dur
                        continue
                    }
                    let midi = Register.place(pitchClass: pc, near: previous,
                                              low: bassLow, high: bassHigh)
                    notes.append(ScheduledNote(pitch: midi, velocity: volume, startTick: t,
                                               duration: dur, channel: Self.bassChannel))
                    previous = midi
                    t += dur
                }
                remaining -= patternDuration(pattern)
            }
        }
        return notes
    }

    /// Resolve a bass rule letter to a pitch class (0–11), or `nil` for a rest.
    private func bassPitchClass(for letter: Character, chord: ChordSymbol, next: ChordSymbol,
                                previous: Int, _ rng: inout SeededGenerator) -> Int? {
        switch letter {
        case "B", "b", "X", "x", "=":
            return chord.bass.semitones
        case "N", "n":
            return next.bass.semitones
        case "C", "c", "S", "s":
            // Chord tone (S approximates a scale tone with a chord tone for now).
            let tones = chord.chordTones.map(\.semitones)
            guard !tones.isEmpty else { return chord.bass.semitones }
            return tones[Int.random(in: 0..<tones.count, using: &rng)]
        case "A", "a":
            // Chromatic approach to the next chord's bass: pick the ±1 whose
            // placement is closest to the previous note.
            let target = next.bass.semitones
            let up = Register.place(pitchClass: target + 1, near: previous, low: bassLow, high: bassHigh)
            let down = Register.place(pitchClass: target - 1, near: previous, low: bassLow, high: bassHigh)
            return abs(up - previous) <= abs(down - previous) ? (target + 1) % 12 : ((target - 1) % 12 + 12) % 12
        default:
            return chord.bass.semitones
        }
    }

    // MARK: Chords (comping)

    private func generateChords(_ chordPart: ChordPart, _ rng: inout SeededGenerator) -> [ScheduledNote] {
        var notes: [ScheduledNote] = []

        for entry in chordPart.entries {
            let chord = entry.symbol
            let voicing = buildVoicing(chord)
            var t = entry.start
            var remaining = entry.duration

            while remaining > 0 {
                guard let pattern = selectPattern(style.chordPatterns, fitting: remaining, &rng) else {
                    strike(voicing, at: t, duration: remaining, velocity: 75, into: &notes)
                    break
                }
                var volume = 75
                for token in pattern.rules {
                    let (letter, suffix) = splitToken(token)
                    if letter == "V" || letter == "v" {
                        volume = Int(suffix) ?? volume
                        continue
                    }
                    let dur = Duration.slots(suffix)
                    if letter == "X" || letter == "x" {
                        strike(voicing, at: t, duration: dur, velocity: volume, into: &notes)
                    }
                    // X, R, P (push/prefix) all advance the clock.
                    t += dur
                }
                remaining -= patternDuration(pattern)
            }
        }
        return notes
    }

    /// A simple closed voicing: the chord tones stacked ascending from the
    /// bottom of the chord register. (Step 6's voicing engine refines this.)
    func buildVoicing(_ chord: ChordSymbol) -> [Int] {
        let tones = chord.chordTones.map(\.semitones)
        guard !tones.isEmpty else { return [] }
        var voicing: [Int] = []
        var floor = chordLow
        for pc in tones {
            var m = ((pc - floor) % 12 + 12) % 12 + floor
            if m > chordHigh { m -= 12 }
            voicing.append(max(0, min(127, m)))
            floor = m + 1
        }
        return voicing
    }

    private func strike(_ voicing: [Int], at tick: Int, duration: Int, velocity: Int,
                        into notes: inout [ScheduledNote]) {
        for pitch in voicing {
            notes.append(ScheduledNote(pitch: pitch, velocity: velocity, startTick: tick,
                                       duration: duration, channel: Self.chordChannel))
        }
    }

    // MARK: Drums

    private func generateDrums(totalSlots: Int, _ rng: inout SeededGenerator) -> [ScheduledNote] {
        var notes: [ScheduledNote] = []
        guard totalSlots > 0, !style.drumPatterns.isEmpty else { return notes }
        var t = 0

        while t < totalSlots {
            let remaining = totalSlots - t
            guard let pattern = selectDrumPattern(fitting: remaining, &rng) else { break }
            for voice in pattern.voices {
                guard let drum = DrumBank.midi(for: voice.name) else { continue }
                var vt = t
                var volume = 100
                for token in voice.hits {
                    let (letter, suffix) = splitToken(token)
                    switch letter {
                    case "V", "v":
                        volume = Int(suffix) ?? volume
                    case "X", "x":
                        let dur = Duration.slots(suffix)
                        notes.append(ScheduledNote(pitch: drum, velocity: volume, startTick: vt,
                                                   duration: dur, channel: Constants.DRUM_CHANNEL))
                        vt += dur
                    default: // R and anything else advances the clock
                        vt += Duration.slots(suffix)
                    }
                }
            }
            t += drumPatternDuration(pattern)
        }
        return notes
    }

    // MARK: Pattern selection (port of Style.getPattern)

    /// Choose a weighted-random pattern whose duration is the largest that still
    /// fits within `remaining`. Returns `nil` if every pattern is longer.
    private func selectPattern(_ patterns: [Pattern], fitting remaining: Int,
                               _ rng: inout SeededGenerator) -> Pattern? {
        let durations = patterns.map(patternDuration)
        let largest = zip(patterns, durations)
            .filter { $0.1 > 0 && $0.1 <= remaining }
            .map(\.1).max()
        guard let largest else { return nil }
        let candidates = zip(patterns, durations).filter { $0.1 == largest }.map(\.0)
        guard let idx = rng.weightedIndex(candidates.map(\.weight)) else { return nil }
        return candidates[idx]
    }

    private func selectDrumPattern(fitting remaining: Int,
                                   _ rng: inout SeededGenerator) -> DrumPattern? {
        let durations = style.drumPatterns.map(drumPatternDuration)
        let largest = zip(style.drumPatterns, durations)
            .filter { $0.1 > 0 && $0.1 <= remaining }
            .map(\.1).max()
        // If nothing fits (e.g. a short tail), fall back to the shortest pattern.
        let target = largest ?? durations.filter { $0 > 0 }.min()
        guard let target else { return nil }
        let candidates = zip(style.drumPatterns, durations).filter { $0.1 == target }.map(\.0)
        guard let idx = rng.weightedIndex(candidates.map(\.weight)) else { return nil }
        return candidates[idx]
    }

    // MARK: Durations

    /// Total slot duration of a bass/chord pattern (V tokens carry no time).
    func patternDuration(_ pattern: Pattern) -> Int {
        pattern.rules.reduce(0) { sum, token in
            let (letter, suffix) = splitToken(token)
            return (letter == "V" || letter == "v") ? sum : sum + Duration.slots(suffix)
        }
    }

    /// Total slot duration of a drum pattern (the longest voice).
    func drumPatternDuration(_ pattern: DrumPattern) -> Int {
        pattern.voices.map { voice in
            voice.hits.reduce(0) { sum, token in
                let (letter, suffix) = splitToken(token)
                return (letter == "V" || letter == "v") ? sum : sum + Duration.slots(suffix)
            }
        }.max() ?? 0
    }

    // MARK: Token splitting

    /// Split a rule token into its leading letter and the remaining suffix,
    /// e.g. `"B4"` -> (`B`, `"4"`), `"V90"` -> (`V`, `"90"`), `"R4+8"` -> (`R`, `"4+8"`).
    func splitToken(_ token: String) -> (Character, String) {
        guard let first = token.first else { return (" ", "") }
        return (first, String(token.dropFirst()))
    }
}
