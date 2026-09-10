//
//  Harmony.swift
//  ImprovisorEngine
//
//  Pitch snapping for "harmonic entry": move a rough pitch (from a mouse
//  position) to the nearest chord tone / color tone / scale tone of the chord
//  sounding there, plus approach tones and diatonic stepping within a key.
//

import Foundation

public enum ToneMode: String, Equatable, Sendable, CaseIterable {
    /// Any pitch (simple entry).
    case chromatic
    case chordTones
    case chordAndColor
    case scale
}

public enum Harmony {

    /// Pitch classes allowed by `mode` over `chord` (empty = anything goes).
    public static func pitchClasses(for chord: ChordSymbol?, mode: ToneMode) -> [Int] {
        guard let chord, !chord.isNoChord else { return [] }
        switch mode {
        case .chromatic: return []
        case .chordTones: return chord.chordTones.map(\.semitones)
        case .chordAndColor: return (chord.chordTones + chord.colorTones).map(\.semitones)
        case .scale:
            let s = chord.scaleTones.map(\.semitones)
            return s.isEmpty ? (chord.chordTones + chord.colorTones).map(\.semitones) : s
        }
    }

    /// Approach tones: a semitone above or below each chord tone.
    public static func approachPitchClasses(for chord: ChordSymbol?) -> [Int] {
        guard let chord, !chord.isNoChord else { return [] }
        let tones = Set(chord.chordTones.map(\.semitones))
        var out = Set<Int>()
        for t in tones { out.insert((t + 1) % 12); out.insert((t + 11) % 12) }
        return out.subtracting(tones).sorted()
    }

    /// The pitch nearest `pitch` whose class is in `classes` (ties go up when
    /// `preferUp`). Returns `pitch` when `classes` is empty.
    public static func nearest(_ pitch: Int, in classes: [Int], preferUp: Bool = true) -> Int {
        guard !classes.isEmpty else { return pitch }
        let set = Set(classes.map { (($0 % 12) + 12) % 12 })
        if set.contains(((pitch % 12) + 12) % 12) { return pitch }
        for delta in 1...11 {
            let up = pitch + delta, down = pitch - delta
            let upOK = set.contains(((up % 12) + 12) % 12), downOK = set.contains(((down % 12) + 12) % 12)
            if upOK && downOK { return preferUp ? up : down }
            if upOK { return up }
            if downOK { return down }
        }
        return pitch
    }

    /// Snap `pitch` to `mode` over `chord`.
    public static func snap(_ pitch: Int, chord: ChordSymbol?, mode: ToneMode, preferUp: Bool = true) -> Int {
        nearest(pitch, in: pitchClasses(for: chord, mode: mode), preferUp: preferUp)
    }

    /// Move `pitch` by `steps` diatonic steps within the major scale of `key`
    /// (positive = up). Pitches outside the scale step to the next scale tone.
    public static func step(_ pitch: Int, by steps: Int, key: Key) -> Int {
        guard steps != 0 else { return pitch }
        let tonic = key.tonic.semitones
        let scale = Set([0, 2, 4, 5, 7, 9, 11].map { ($0 + tonic) % 12 })
        var p = pitch
        var remaining = abs(steps)
        let dir = steps > 0 ? 1 : -1
        while remaining > 0 {
            p += dir
            while !scale.contains(((p % 12) + 12) % 12) { p += dir }
            remaining -= 1
        }
        return max(0, min(127, p))
    }

    /// The MIDI pitch of a letter (0–6 = C…B) in `octave` (C4 = 60), as spelled
    /// by `key` (F in G major is F#), or natural when `natural` is forced.
    public static func pitch(letter: Int, octave: Int, key: Key, natural: Bool = false) -> Int {
        let base = [0, 2, 4, 5, 7, 9, 11][((letter % 7) + 7) % 7]
        var acc = 0
        if !natural {
            let sharps = [3, 0, 4, 1, 5, 2, 6], flats = [6, 2, 5, 1, 4, 0, 3]
            if key.index > 0, sharps.prefix(min(7, key.index)).contains(letter) { acc = 1 }
            if key.index < 0, flats.prefix(min(7, -key.index)).contains(letter) { acc = -1 }
        }
        return (octave + 1) * 12 + base + acc
    }
}
