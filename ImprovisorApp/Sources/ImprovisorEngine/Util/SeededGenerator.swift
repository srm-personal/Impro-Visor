//
//  SeededGenerator.swift
//  ImprovisorEngine
//
//  A small, fast, seedable PRNG (SplitMix64) conforming to
//  `RandomNumberGenerator`. Determinism matters here: given the same seed, the
//  accompaniment and solo generators must reproduce the same output, which is
//  what makes their behavior testable (and lets the UI "regenerate with seed").
//

import Foundation

public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid a zero state producing a degenerate stream.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Pick a weighted-random index given parallel weights. Returns `nil` if the
    /// weights are empty or sum to zero.
    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights.isEmpty ? nil : Int.random(in: 0..<weights.count, using: &self) }
        let threshold = Double.random(in: 0..<total, using: &self)
        var running = 0.0
        for (index, weight) in weights.enumerated() {
            running += weight
            if threshold < running { return index }
        }
        return weights.indices.last
    }
}
