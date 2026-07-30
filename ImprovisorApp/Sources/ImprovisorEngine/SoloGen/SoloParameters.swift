//
//  SoloParameters.swift
//  ImprovisorEngine
//
//  Tunable inputs to the grammar solo generator, mirroring the `parameter`
//  entries a `.grammar` file carries (min-pitch, max-pitch, rest-prob, and the
//  tone-weight biases).
//

import Foundation

public struct SoloParameters: Equatable, Sendable {
    /// Lowest MIDI pitch the solo may use.
    public var minPitch: Int
    /// Highest MIDI pitch the solo may use.
    public var maxPitch: Int
    /// Probability [0,1] that an eligible note is replaced by a rest.
    public var restProbability: Double
    /// Relative likelihood biases when a note type is left open.
    public var chordToneWeight: Double
    public var colorToneWeight: Double
    public var scaleToneWeight: Double
    /// Largest melodic leap (semitones) preferred between consecutive notes.
    public var maxInterval: Int

    public init(minPitch: Int = 58, maxPitch: Int = 82, restProbability: Double = 0.1,
                chordToneWeight: Double = 0.7, colorToneWeight: Double = 0.2,
                scaleToneWeight: Double = 0.1, maxInterval: Int = 6) {
        self.minPitch = minPitch
        self.maxPitch = maxPitch
        self.restProbability = restProbability
        self.chordToneWeight = chordToneWeight
        self.colorToneWeight = colorToneWeight
        self.scaleToneWeight = scaleToneWeight
        self.maxInterval = maxInterval
    }

    /// Read parameters from a grammar's `parameter` entries, falling back to
    /// the defaults for anything absent.
    public static func from(grammar: Grammar) -> SoloParameters {
        var p = SoloParameters()
        if let v = grammar.int("min-pitch") { p.minPitch = v }
        if let v = grammar.int("max-pitch") { p.maxPitch = v }
        if let v = grammar.number("rest-prob") { p.restProbability = v }
        if let v = grammar.number("chord-tone-weight") { p.chordToneWeight = v }
        if let v = grammar.number("color-tone-weight") { p.colorToneWeight = v }
        if let v = grammar.number("scale-tone-weight") { p.scaleToneWeight = v }
        if let v = grammar.int("max-interval") { p.maxInterval = v }
        return p
    }
}
