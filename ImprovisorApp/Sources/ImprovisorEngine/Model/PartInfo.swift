//
//  PartInfo.swift
//  ImprovisorEngine
//
//  Per-part metadata carried by a leadsheet `(part …)` header: the fields the
//  Java `Part` class saves (`title`, `composer`, `instrument`, `volume`, `key`)
//  plus the melody part's `stave` type. Kept on `ChordPart` / `MelodyPart` so
//  that reading a `.ls` file and writing it back is lossless.
//

import Foundation

/// How a melody part is displayed (Java `StaveType`).
public enum StaveType: String, Equatable, Sendable, CaseIterable {
    case treble, bass, grand, auto, none
}

public struct PartInfo: Equatable, Sendable {
    public var title: String
    public var composer: String
    /// General MIDI program number (0–127).
    public var instrument: Int
    /// MIDI volume (0–127).
    public var volume: Int
    /// Key signature of the part: +n sharps, -n flats.
    public var key: Int
    /// Stave type (only meaningful, and only written, for melody parts).
    public var stave: StaveType

    public init(title: String = "", composer: String = "", instrument: Int = 0,
                volume: Int = 100, key: Int = 0, stave: StaveType = .treble) {
        self.title = title
        self.composer = composer
        self.instrument = instrument
        self.volume = volume
        self.key = key
        self.stave = stave
    }

    /// Defaults for a chord part: piano.
    public static let defaultChords = PartInfo(instrument: 0, volume: 65)
    /// Defaults for a melody part: flute (matches the shipped leadsheets).
    public static let defaultMelody = PartInfo(instrument: 73, volume: 85, stave: .treble)
}
