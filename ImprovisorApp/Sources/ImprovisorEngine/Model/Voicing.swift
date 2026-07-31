//
//  Voicing.swift
//  ImprovisorEngine
//
//  Port of imp/data/Voicing: a named voicing of a chord type as stored in the
//  vocabulary (vocab/My.voc), e.g.
//
//      (left-hand-A (type closed) (notes e-8 g-8 c8) (extension))
//
//  `notes` and `extension` are absolute MIDI pitches for the C-rooted chord; the
//  voicer transposes them to the actual root. Octave markers (`-`, `+`) in the
//  note tokens are handled by `NoteSymbol.parse`.
//

import Foundation

/// A named, C-rooted voicing loaded from the vocabulary.
public struct Voicing: Equatable, Sendable {
    /// The voicing's id, e.g. `left-hand-A`, `open-A`.
    public let name: String
    /// `closed`, `open`, or another type label; matched against the style's
    /// `voicing-type` (with `any` as a wildcard).
    public let type: String
    /// The voicing's notes as absolute MIDI pitches (C-rooted).
    public let notes: [Int]
    /// Extension notes as absolute MIDI pitches (C-rooted); usually empty.
    public let ext: [Int]

    public init(name: String, type: String, notes: [Int], ext: [Int]) {
        self.name = name
        self.type = type
        self.notes = notes
        self.ext = ext
    }

    /// This voicing's notes and extension transposed by `semitones`.
    public func transposed(by semitones: Int) -> Voicing {
        Voicing(name: name, type: type,
                notes: notes.map { $0 + semitones },
                ext: ext.map { $0 + semitones })
    }
}
