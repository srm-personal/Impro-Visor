//
//  Register.swift
//  ImprovisorEngine
//
//  Helpers for placing a pitch class at a concrete MIDI octave within a register
//  and near a reference note (voice leading). Style register bounds are written
//  as note names (e.g. `g--`, `c`, `d-`) which parse via NoteSymbol.
//

import Foundation

public enum Register {
    /// The MIDI number a style register-bound note name denotes (e.g. `"g--"`).
    /// Falls back to `fallback` if the name doesn't parse.
    public static func midi(ofNoteName name: String, fallback: Int) -> Int {
        NoteSymbol.parse(name)?.note?.pitch ?? fallback
    }

    /// Place `pitchClass` (0–11) at the MIDI octave that lands within
    /// `[low, high]` and is closest to `reference`. If no octave fits the
    /// register, the nearest-to-register candidate is clamped in.
    public static func place(pitchClass: Int, near reference: Int, low: Int, high: Int) -> Int {
        let pc = ((pitchClass % 12) + 12) % 12

        // Start from the octave nearest the reference.
        var best = pc + 12 * Int((Double(reference - pc) / 12.0).rounded())

        // If out of register, shift by octaves to get inside.
        while best < low { best += 12 }
        while best > high { best -= 12 }

        // If shifting overshot below `low` (register narrower than an octave),
        // choose whichever bound-adjacent candidate is closest to the reference.
        if best < low {
            let up = best + 12
            best = abs(up - reference) <= abs(best - reference) && up <= high ? up : best
        }
        return max(0, min(127, best))
    }
}
