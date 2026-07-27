//
//  Key.swift
//  ImprovisorEngine
//
//  A key signature, encoded the way leadsheets do: a signed integer on the
//  circle of fifths. 0 = C, positive = number of sharps (1 = G, 2 = D, …),
//  negative = number of flats (-1 = F, -2 = Bb, …). See imp/data/Key.java.
//

import Foundation

public struct Key: Equatable, Hashable, Sendable {
    /// Circle-of-fifths index: 0 = C, +n = n sharps, -n = n flats.
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    /// Number of sharps in the signature (0 if the key uses flats).
    public var sharps: Int { max(index, 0) }
    /// Number of flats in the signature (0 if the key uses sharps).
    public var flats: Int { max(-index, 0) }

    /// The tonic pitch class implied by the signature (major-key tonic).
    /// Each step clockwise on the circle of fifths adds 7 semitones.
    public var tonic: PitchClass {
        PitchClass.forMidi(((index * 7) % 12 + 12) % 12)
    }

    public static let cMajor = Key(index: 0)
}
