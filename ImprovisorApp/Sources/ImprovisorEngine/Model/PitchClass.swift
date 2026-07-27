//
//  PitchClass.swift
//  ImprovisorEngine
//
//  Port of imp/data/PitchClass.java (the parts the engine needs). A pitch class
//  is one of the named notes (c, c#, db, … b#), each carrying its number of
//  semitones above C (0–11) and a preferred enharmonic spelling for display.
//

import Foundation

/// A named pitch class (letter + optional accidental), e.g. `c`, `f#`, `bb`.
/// Equality and MIDI math are by semitone; the name is retained for spelling.
public struct PitchClass: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// Canonical lower-case name as written in the data (`"c"`, `"f#"`, `"bb"`).
    public let name: String
    /// Semitones above C, 0–11.
    public let semitones: Int
    /// Preferred display spelling (`"C"`, `"F#"`, `"Bb"`).
    public let spelling: String

    public var description: String { spelling }

    // MARK: Table (from PitchClass.java, name -> semitonesAboveC, spelling)

    private static let table: [(name: String, semitones: Int, spelling: String)] = [
        ("fb", 4, "E"), ("cb", 11, "B"), ("gb", 6, "Gb"), ("db", 1, "Db"),
        ("ab", 8, "Ab"), ("eb", 3, "Eb"), ("bb", 10, "Bb"),
        ("f", 5, "F"), ("c", 0, "C"), ("g", 7, "G"), ("d", 2, "D"),
        ("a", 9, "A"), ("e", 4, "E"), ("b", 11, "B"),
        ("f#", 6, "F#"), ("c#", 1, "C#"), ("g#", 8, "Ab"), ("d#", 3, "Eb"),
        ("a#", 10, "Bb"), ("e#", 5, "F"), ("b#", 0, "C")
    ]

    private static let byName: [String: PitchClass] = {
        var map: [String: PitchClass] = [:]
        for entry in table {
            map[entry.name] = PitchClass(name: entry.name,
                                         semitones: entry.semitones,
                                         spelling: entry.spelling)
        }
        return map
    }()

    /// Canonical pitch classes for the 12 semitones (used when no spelling
    /// preference is known), preferring flats as Impro-Visor generally does.
    private static let bySemitone: [PitchClass] = {
        let names = ["c", "db", "d", "eb", "e", "f", "f#", "g", "ab", "a", "bb", "b"]
        return names.map { byName[$0]! }
    }()

    // MARK: Lookups

    /// Look up a pitch class by name (case-insensitive). Returns `nil` if the
    /// name is not a recognized pitch class.
    public static func named(_ name: String) -> PitchClass? {
        byName[name.lowercased()]
    }

    /// The canonical pitch class for a MIDI note number (0–11 reduction).
    public static func forMidi(_ midi: Int) -> PitchClass {
        bySemitone[((midi % 12) + 12) % 12]
    }

    /// Parse the pitch class from the start of a token, ignoring any trailing
    /// octave markers or duration (e.g. `"eb8"` -> `Eb`, `"f#"` -> `F#`). Used
    /// to read chord `spell`/`color` note lists from the vocabulary.
    public static func parse(_ token: String) -> PitchClass? {
        let chars = Array(token.lowercased())
        guard let first = chars.first, isValidPitchStart(first) else { return nil }
        var base = String(first)
        if chars.count > 1 {
            let second = chars[1]
            if second == "#" || second == "b" || second == "s" {
                base.append(second == "s" ? "#" : second)
            }
        }
        return named(base)
    }

    /// Whether `c` can begin a pitch name (a–g, A–G).
    public static func isValidPitchStart(_ c: Character) -> Bool {
        let lower = Character(c.lowercased())
        return lower >= "a" && lower <= "g"
    }

    // MARK: Transposition

    /// This pitch class transposed by `semitones` (result uses canonical
    /// spelling for the target semitone).
    public func transposed(by semitones: Int) -> PitchClass {
        PitchClass.forMidi(self.semitones + semitones)
    }
}
