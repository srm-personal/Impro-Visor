//
//  Style.swift
//  ImprovisorEngine
//
//  The data model for an accompaniment style, loaded from a `.sty` file. Ports
//  the fields of imp/style/Style and its Pattern subclasses. This type only
//  *holds* the parsed patterns; turning them into MIDI events is the job of the
//  accompaniment engine (Step 4). Pattern rule tokens (`B4`, `S4`, `X8`, `V90`,
//  `R4`, …) are kept as raw strings here and interpreted there.
//

import Foundation

/// A weighted bass or chord comping pattern: a sequence of rule tokens.
public struct Pattern: Equatable, Sendable {
    /// Rule tokens, e.g. `["B4", "S4", "C4", "V90", "A4"]`.
    public let rules: [String]
    /// Selection weight (higher = more likely).
    public let weight: Double
    /// Optional anticipation ("push") duration string, e.g. `8/3`.
    public let push: String?

    public init(rules: [String], weight: Double, push: String? = nil) {
        self.rules = rules
        self.weight = weight
        self.push = push
    }
}

/// A single drum voice within a drum pattern: an instrument name and its hits.
public struct DrumVoice: Equatable, Sendable {
    /// Instrument name as written, e.g. `Ride_Cymbal_1`, `Closed_Hi-Hat`.
    public let name: String
    /// Rhythm tokens for this voice, e.g. `["X4", "X8", "X8", "X4"]`.
    public let hits: [String]

    public init(name: String, hits: [String]) {
        self.name = name
        self.hits = hits
    }
}

/// A weighted drum pattern: several drum voices sounding together.
public struct DrumPattern: Equatable, Sendable {
    public let voices: [DrumVoice]
    public let weight: Double

    public init(voices: [DrumVoice], weight: Double) {
        self.voices = voices
        self.weight = weight
    }
}

/// An accompaniment style.
public struct Style: Equatable, Sendable {
    public var name: String
    public var swing: Double
    public var compSwing: Double
    public var voicingType: String
    /// Name of the `.fv` preset in `voicings/` used by the algorithmic voicer when
    /// `voicingType == "custom"`. Defaults to `default.fv`.
    public var voicingFileName: String

    /// Register bounds, as pitch-class/octave note names (e.g. `c`, `g--`, `d-`).
    public var bassHigh: String
    public var bassLow: String
    public var bassBase: String
    public var chordHigh: String
    public var chordLow: String

    public var bassPatterns: [Pattern]
    public var chordPatterns: [Pattern]
    public var drumPatterns: [DrumPattern]

    public init(
        name: String = "",
        swing: Double = 0.5,
        compSwing: Double = 0.5,
        voicingType: String = "closed",
        voicingFileName: String = "default.fv",
        bassHigh: String = "c",
        bassLow: String = "g--",
        bassBase: String = "e--",
        chordHigh: String = "a",
        chordLow: String = "d-",
        bassPatterns: [Pattern] = [],
        chordPatterns: [Pattern] = [],
        drumPatterns: [DrumPattern] = []
    ) {
        self.name = name
        self.swing = swing
        self.compSwing = compSwing
        self.voicingType = voicingType
        self.voicingFileName = voicingFileName
        self.bassHigh = bassHigh
        self.bassLow = bassLow
        self.bassBase = bassBase
        self.chordHigh = chordHigh
        self.chordLow = chordLow
        self.bassPatterns = bassPatterns
        self.chordPatterns = chordPatterns
        self.drumPatterns = drumPatterns
    }
}

extension Style {
    /// This style with a leadsheet's inline parameter overrides applied — the
    /// `(swing 0.55) (bass-low g--) …` forms that follow the style name in a
    /// `.ls` header (`Score.styleOverride`). Mirrors Java's `style.load(param)`.
    public func applying(override: Polylist?) -> Style {
        guard let override, override.nonEmpty else { return self }
        var copy = self
        for param in override {
            StyleParser.apply(param, to: &copy)
        }
        return copy
    }
}
