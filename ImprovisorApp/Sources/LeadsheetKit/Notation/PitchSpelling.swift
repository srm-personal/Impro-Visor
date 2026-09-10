//
//  PitchSpelling.swift
//  LeadsheetKit
//
//  Chooses the letter name / accidental for a MIDI pitch (honoring a note's
//  own enharmonic spelling, else the key), and describes key signatures.
//

import Foundation
import ImprovisorEngine

/// A pitch spelled as letter + accidental + octave.
public struct SpelledPitch: Equatable, Sendable {
    /// 0–6 = C D E F G A B.
    public var letter: Int
    /// Semitone offset of the accidental: -1 flat, 0 natural, +1 sharp.
    public var accidental: Int
    /// Scientific octave (C4 = middle C).
    public var octave: Int

    public var diatonic: Int { Diatonic.index(letter: letter, octave: octave) }
    public var letterName: Character { Diatonic.letterNames[letter] }
    public var midi: Int { (octave + 1) * 12 + PitchSpelling.letterSemitones[letter] + accidental }
}

public enum PitchSpelling {
    static let letterSemitones = [0, 2, 4, 5, 7, 9, 11]
    /// Letter of each white-key pitch class (nil for black keys).
    static let whiteLetter: [Int?] = [0, nil, 1, nil, 2, 3, nil, 4, nil, 5, nil, 6]

    /// Spell a MIDI pitch. Black keys use sharps when `preferSharp`, else flats.
    public static func spell(_ pitch: Int, preferSharp: Bool) -> SpelledPitch {
        let pc = ((pitch % 12) + 12) % 12
        let octave = Int((Double(pitch) / 12).rounded(.down)) - 1
        if let letter = whiteLetter[pc] {
            return SpelledPitch(letter: letter, accidental: 0, octave: octave)
        }
        if preferSharp {
            return SpelledPitch(letter: whiteLetter[pc - 1]!, accidental: 1, octave: octave)
        }
        return SpelledPitch(letter: whiteLetter[pc + 1]!, accidental: -1, octave: octave)
    }

    /// Spell a note: its own spelling wins; otherwise sharps in sharp keys and
    /// flats elsewhere (Impro-Visor's default).
    public static func spell(_ note: Note, key: Key) -> SpelledPitch {
        spell(note.pitch, preferSharp: preferSharp(for: note, key: key))
    }

    public static func preferSharp(for note: Note, key: Key) -> Bool {
        switch note.spelling {
        case .sharp: return true
        case .flat: return false
        case .natural: return key.index > 0
        }
    }

    // MARK: Key signatures

    /// Letters in sharp order F C G D A E B (as letter indexes).
    static let sharpOrder = [3, 0, 4, 1, 5, 2, 6]
    /// Letters in flat order B E A D G C F.
    static let flatOrder = [6, 2, 5, 1, 4, 0, 3]

    /// The accidental (−1/0/+1) the key signature applies to each letter 0–6.
    public static func keyAccidentals(_ key: Key) -> [Int] {
        var acc = [Int](repeating: 0, count: 7)
        if key.index > 0 { for l in sharpOrder.prefix(min(7, key.index)) { acc[l] = 1 } }
        if key.index < 0 { for l in flatOrder.prefix(min(7, -key.index)) { acc[l] = -1 } }
        return acc
    }

    /// Standard treble-staff positions (diatonic) of key-signature accidentals.
    static let trebleSharpPositions = [38, 35, 39, 36, 33, 37, 34]   // F5 C5 G5 D5 A4 E5 B4
    static let trebleFlatPositions = [34, 37, 33, 36, 32, 35, 31]    // B4 E5 A4 D5 G4 C5 F4

    /// Key-signature glyphs for a clef: (diatonic position, accidental).
    public static func keySignature(_ key: Key, clef: Clef) -> [(diatonic: Int, accidental: Int)] {
        let shift = clef == .treble ? 0 : -14
        if key.index > 0 {
            return trebleSharpPositions.prefix(min(7, key.index)).map { ($0 + shift, 1) }
        }
        if key.index < 0 {
            return trebleFlatPositions.prefix(min(7, -key.index)).map { ($0 + shift, -1) }
        }
        return []
    }
}
