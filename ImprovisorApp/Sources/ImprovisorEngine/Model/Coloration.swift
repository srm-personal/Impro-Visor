//
//  Coloration.swift
//  ImprovisorEngine
//
//  Classifies a note against a chord as a chord tone, color tone, approach
//  tone, or foreign (outside) tone. Ports the classification of
//  imp/data/Coloration (categories from Constants.java).
//

import Foundation

/// The harmonic role of a note relative to a chord.
public enum NoteColor: Int, Equatable {
    case chord = 0      // CHORD_TONE
    case color = 1      // COLOR_TONE
    case approach = 2   // APPROACH_TONE
    case foreign = 3    // FOREIGN_TONE
}

public enum Coloration {
    /// Classify `pitch` (MIDI) against `chord`. A foreign tone is reclassified
    /// as an approach tone when `isApproach` is true (i.e. it resolves by a
    /// half/whole step into the next chord/color tone), matching Coloration's
    /// `isApproach` handling.
    public static func classify(pitch: Int, chord: ChordSymbol, isApproach: Bool = false) -> NoteColor {
        let pc = ((pitch % 12) + 12) % 12
        if chord.chordTones.contains(where: { $0.semitones == pc }) {
            return .chord
        }
        if chord.colorTones.contains(where: { $0.semitones == pc }) {
            return .color
        }
        return isApproach ? .approach : .foreign
    }
}
