//
//  HandManager.swift
//  ImprovisorEngine
//
//  Port of imp/voicing/HandManager (Daniel Scanteianu). Moves the two "hands"
//  between chords within their lower/upper limits, honoring a preferred motion
//  direction and a random jitter, and picks a random note count per hand.
//
//  Determinism divergence: the Java original uses Math.random(); here every
//  random draw comes from the caller's SeededGenerator, so a given seed
//  reproduces the same voicing sequence (the Java engine is non-deterministic).
//

import Foundation

/// Tracks each hand's lowest note as chords progress. The playable range of a
/// hand is `[lowestNote, lowestNote + spread]`.
public struct HandManager {
    public var leftHandLowerLimit = 0
    public var rightHandLowerLimit = 0
    public var leftHandUpperLimit = 0
    public var rightHandUpperLimit = 0
    public var leftHandSpread = 0
    public var rightHandSpread = 0
    public var leftHandMinNotes = 0
    public var leftHandMaxNotes = 0
    public var rightHandMinNotes = 0
    public var rightHandMaxNotes = 0
    public var preferredMotion = 0
    public var preferredMotionRange = 0

    public private(set) var leftHandLowestNote = 0
    public private(set) var rightHandLowestNote = 0

    public init() { resetHands() }

    /// Copy the geometry/motion parameters out of a parsed preset.
    public init(settings s: VoicingSettings) {
        leftHandLowerLimit = s.leftHandLowerLimit
        rightHandLowerLimit = s.rightHandLowerLimit
        leftHandUpperLimit = s.leftHandUpperLimit
        rightHandUpperLimit = s.rightHandUpperLimit
        leftHandSpread = s.leftHandSpread
        rightHandSpread = s.rightHandSpread
        leftHandMinNotes = s.leftHandMinNotes
        leftHandMaxNotes = s.leftHandMaxNotes
        rightHandMinNotes = s.rightHandMinNotes
        rightHandMaxNotes = s.rightHandMaxNotes
        preferredMotion = s.preferredMotion
        preferredMotionRange = s.preferredMotionRange
        resetHands()
    }

    public var leftLowerBound: Int { leftHandLowestNote }
    public var leftUpperBound: Int { leftHandLowestNote + leftHandSpread }
    public var rightLowerBound: Int { rightHandLowestNote }
    public var rightUpperBound: Int { rightHandLowestNote + rightHandSpread }

    /// A random note count for the left hand within `[min, max]`.
    public mutating func numLeftNotes(rng: inout SeededGenerator) -> Int {
        rounded(Double.random(in: 0..<1, using: &rng) * Double(leftHandMaxNotes - leftHandMinNotes)) + leftHandMinNotes
    }

    /// A random note count for the right hand within `[min, max]`.
    public mutating func numRightNotes(rng: inout SeededGenerator) -> Int {
        rounded(Double.random(in: 0..<1, using: &rng) * Double(rightHandMaxNotes - rightHandMinNotes)) + rightHandMinNotes
    }

    /// Advance both hands to their position for the next chord.
    public mutating func repositionHands(rng: inout SeededGenerator) {
        let leftJitter = Double.random(in: 0..<1, using: &rng) * 2.0 * Double(preferredMotionRange) - Double(preferredMotionRange)
        leftHandLowestNote = rounded(Double(leftHandLowestNote) + leftJitter + Double(preferredMotion))
        let rightJitter = Double.random(in: 0..<1, using: &rng) * 2.0 * Double(preferredMotionRange) - Double(preferredMotionRange)
        rightHandLowestNote = rounded(Double(rightHandLowestNote) + rightJitter + Double(preferredMotion))

        if leftHandLowestNote < leftHandLowerLimit { resetLH() }
        if rightHandLowestNote < rightHandLowerLimit { resetRH() }
        if leftHandLowestNote + leftHandSpread > leftHandUpperLimit { resetLH() }
        if rightHandLowestNote + rightHandSpread > rightHandUpperLimit { resetRH() }
    }

    public mutating func resetHands() { resetLH(); resetRH() }

    public mutating func resetLH() {
        if preferredMotion > 0 {
            leftHandLowestNote = leftHandLowerLimit
        } else if preferredMotion < 0 {
            leftHandLowestNote = leftHandUpperLimit - leftHandSpread
        } else {
            leftHandLowestNote = (leftHandUpperLimit - leftHandSpread + leftHandLowerLimit) / 2
        }
    }

    public mutating func resetRH() {
        if preferredMotion > 0 {
            rightHandLowestNote = rightHandLowerLimit
        } else if preferredMotion < 0 {
            rightHandLowestNote = rightHandUpperLimit - rightHandSpread
        } else {
            rightHandLowestNote = (rightHandUpperLimit - rightHandSpread + rightHandLowerLimit) / 2
        }
    }

    /// Java's `Math.round`: `floor(x + 0.5)` (round half toward +infinity).
    private func rounded(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
}
