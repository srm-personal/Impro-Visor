//
//  VoicingGenerator.swift
//  ImprovisorEngine
//
//  Port of imp/voicing/VoicingGenerator (Daniel Scanteianu). Builds a chord
//  voicing from scratch by weighting every MIDI pitch and drawing notes at random
//  in proportion to their weight, hand by hand.
//
//  How it works: `allMidiValues[0...127]` holds a weight per pitch. Chord priority
//  and color tones are given weight in every octave; the previous voicing's notes
//  and their half/whole-step neighbours are boosted for voice-leading. For each
//  hand, a weighted-random pick is made from the pitches in that hand's range;
//  once chosen, that pitch is zeroed and its neighbours/octave-mates are reduced so
//  the next pick spreads out. Repeats until each hand has its note quota.
//
//  Determinism divergence: Java uses Math.random(); here every draw comes from the
//  caller's SeededGenerator so a seed reproduces the voicing (Java is not
//  deterministic). The `invertM9` flag is a no-op — the Java `invertM9th` method
//  builds new lists but never writes them back to the hands, so it has no effect on
//  the output; we preserve that behaviour.
//

import Foundation

/// The from-scratch algorithmic voicer. Configure with a `VoicingSettings` and,
/// per chord, the color/priority pitch classes, root, hand bounds + note counts
/// (from `HandManager`), and the previous voicing; then `calculate` and read
/// `chord`.
public struct VoicingGenerator {
    // Settings (from VoicingSettings).
    public var leftColorPriority = 0
    public var rightColorPriority = 0
    public var maxPriority = 6
    public var previousVoicingMultiplier = 1.0
    public var halfStepAwayMultiplier = 1.0
    public var fullStepAwayMultiplier = 1.0
    public var priorityMultiplier = 0.0
    public var repeatMultiplier = 1.0
    public var halfStepReducer = 0.0
    public var fullStepReducer = 1.0
    public var invertM9 = false
    public var voiceAll = false
    public var rootless = false
    public var leftMinInterval = 0
    public var rightMinInterval = 0

    // Hand geometry + quotas (from HandManager, per chord).
    public var lowerLeftBound = 0
    public var upperLeftBound = 0
    public var lowerRightBound = 0
    public var upperRightBound = 0
    public var numNotesLeft = 0
    public var numNotesRight = 0

    // Per-chord inputs. color/priority are MIDI values (reduced mod-12 internally).
    public var root = 0
    public var color: [Int] = []
    public var priority: [Int] = []
    public var previousVoicing: [Int]? = nil

    // Working state.
    private var allMidiValues = [Int](repeating: 0, count: 128)
    private var leftHand: [Int] = []
    private var rightHand: [Int] = []

    public init() {}

    /// Copy the non-geometry parameters out of a parsed preset.
    public mutating func apply(settings s: VoicingSettings) {
        leftColorPriority = s.leftColorPriority
        rightColorPriority = s.rightColorPriority
        maxPriority = s.maxPriority
        previousVoicingMultiplier = s.previousVoicingMultiplier
        halfStepAwayMultiplier = s.halfStepAwayMultiplier
        fullStepAwayMultiplier = s.fullStepAwayMultiplier
        priorityMultiplier = s.priorityMultiplier
        repeatMultiplier = s.repeatMultiplier
        halfStepReducer = s.halfStepReducer
        fullStepReducer = s.fullStepReducer
        invertM9 = s.invertM9
        voiceAll = s.voiceAll
        rootless = s.rootless
        leftMinInterval = s.leftMinInterval
        rightMinInterval = s.rightMinInterval
    }

    /// Copy the current hand bounds out of a `HandManager` and draw fresh
    /// per-hand note counts from the RNG (mirrors Java's `getHandSettings`).
    public mutating func apply(hand hm: inout HandManager, rng: inout SeededGenerator) {
        lowerLeftBound = hm.leftLowerBound
        upperLeftBound = hm.leftUpperBound
        lowerRightBound = hm.rightLowerBound
        upperRightBound = hm.rightUpperBound
        numNotesLeft = hm.numLeftNotes(rng: &rng)
        numNotesRight = hm.numRightNotes(rng: &rng)
    }

    /// The generated voicing: left-hand notes followed by right-hand notes.
    public var chord: [Int] { leftHand + rightHand }

    // MARK: - The algorithm

    public mutating func calculate(rng: inout SeededGenerator) {
        allMidiValues = [Int](repeating: 0, count: 128)
        leftHand = []
        rightHand = []
        var start = 0

        if voiceAll {
            // Pre-pass: guarantee every priority note appears, by voicing exactly
            // priority.count notes across the two hands.
            for i in allMidiValues.indices { allMidiValues[i] = 0 }
            for p in priority.indices {
                setupNote(priority[p], Int(Double(maxPriority) * 10 - Double(p) * 10 * priorityMultiplier))
            }
            if rootless { setupNote(root, 0) }

            for _ in priority.indices {
                let leftValues = valuesInRange(lowerLeftBound, upperLeftBound)
                if let noteToAdd = pick(leftValues, rng: &rng) {
                    leftHand.append(noteToAdd)
                    zero(noteToAdd)
                    if scaled(noteToAdd + 1, halfStepReducer) > 0 { scale(noteToAdd + 1, halfStepReducer) }
                    if scaled(noteToAdd - 1, halfStepReducer) > 0 { scale(noteToAdd - 1, halfStepReducer) }
                    if scaled(noteToAdd + 2, halfStepReducer) > 0 { scale(noteToAdd + 2, halfStepReducer) }
                    if scaled(noteToAdd - 2, halfStepReducer) > 0 { scale(noteToAdd - 2, halfStepReducer) }
                    multiplyNotes(noteToAdd, 0)
                }
                let rightValues = valuesInRange(lowerRightBound, upperRightBound)
                if let noteToAdd = pick(rightValues, rng: &rng) {
                    rightHand.append(noteToAdd)
                    zero(noteToAdd)
                    if scaled(noteToAdd + 1, halfStepReducer) > 0 { scale(noteToAdd + 1, halfStepReducer) }
                    if scaled(noteToAdd - 1, halfStepReducer) > 0 { scale(noteToAdd - 1, halfStepReducer) }
                    if scaled(noteToAdd + 2, halfStepReducer) > 0 { scale(noteToAdd + 2, halfStepReducer) }
                    if scaled(noteToAdd - 2, halfStepReducer) > 0 { scale(noteToAdd - 2, halfStepReducer) }
                    multiplyNotes(noteToAdd, 0)
                }
            }
            start = min(leftHand.count, rightHand.count)
        }

        // Normal algorithm: re-weight everything (color + priority), suppress the
        // notes already chosen, then boost around the previous voicing.
        initAllMidiValues()
        if rootless { setupNote(root, 0) }
        for i in leftHand { zero(i) }
        for i in rightHand { zero(i) }
        if previousVoicing != nil { weightPreviousVoicing() }

        var i = start
        while i < numNotesLeft || i < numNotesRight {
            let leftValues = valuesInRange(lowerLeftBound, upperLeftBound)
            if !leftValues.isEmpty, leftHand.count < numNotesLeft,
               let noteToAdd = pick(leftValues, rng: &rng) {
                leftHand.append(noteToAdd)
                zero(noteToAdd)
                scale(noteToAdd + 1, halfStepReducer)
                scale(noteToAdd - 1, halfStepReducer)
                scale(noteToAdd + 2, fullStepReducer)
                scale(noteToAdd - 2, fullStepReducer)
                multiplyNotes(noteToAdd, repeatMultiplier)
                for j in 0..<max(0, leftMinInterval) {
                    zero(noteToAdd + j)
                    zero(noteToAdd - j)
                }
            }
            let rightValues = valuesInRange(lowerRightBound, upperRightBound)
            if !rightValues.isEmpty, rightHand.count < numNotesRight,
               let noteToAdd = pick(rightValues, rng: &rng) {
                rightHand.append(noteToAdd)
                zero(noteToAdd)
                scale(noteToAdd + 1, halfStepReducer)
                scale(noteToAdd - 1, halfStepReducer)
                scale(noteToAdd + 2, fullStepReducer)
                scale(noteToAdd - 2, fullStepReducer)
                multiplyNotes(noteToAdd, repeatMultiplier)
                for j in 0..<max(0, rightMinInterval) {
                    zero(noteToAdd + j)
                    zero(noteToAdd - j)
                }
            }
            // invertM9 intentionally has no effect (see file header).
            i += 1
        }
    }

    // MARK: - Helpers (bounds-guarded where Java would index out of range)

    /// Set every octave of a pitch class to `weight`.
    private mutating func setupNote(_ midiValue: Int, _ weight: Int) {
        let pc = ((midiValue % 12) + 12) % 12
        var i = pc
        while i < 128 { allMidiValues[i] = weight; i += 12 }
    }

    /// Set every octave of a pitch class at or above `start` to `weight`.
    private mutating func setupNote(_ midiValue: Int, _ weight: Int, from start: Int) {
        let pc = ((midiValue % 12) + 12) % 12
        for i in max(0, start)..<128 where i % 12 == pc { allMidiValues[i] = weight }
    }

    /// Weight color tones (both hands) and priority tones for a fresh chord.
    private mutating func initAllMidiValues() {
        for i in allMidiValues.indices { allMidiValues[i] = 0 }
        for c in color { setupNote(c, leftColorPriority * 10) }
        for c in color { setupNote(c, rightColorPriority * 10, from: lowerRightBound) }
        for p in priority.indices {
            setupNote(priority[p], Int(Double(maxPriority) * 10 - Double(p) * 10 * priorityMultiplier))
        }
    }

    /// Boost the previous voicing's notes and their half/whole-step neighbours.
    private mutating func weightPreviousVoicing() {
        guard let prev = previousVoicing else { return }
        for n in prev { scale(n, previousVoicingMultiplier) }
        for n in prev { scale(n + 1, halfStepAwayMultiplier) }
        for n in prev { scale(n - 1, halfStepAwayMultiplier) }
        for n in prev { scale(n - 2, fullStepAwayMultiplier) }
        for n in prev { scale(n + 2, fullStepAwayMultiplier) }
    }

    /// Expand the weighted pitches in `[lower, upper]` into a multiset of indices.
    private func valuesInRange(_ lower: Int, _ upper: Int) -> [Int] {
        var values: [Int] = []
        let lo = max(0, lower)
        let hi = min(127, upper)
        guard lo <= hi else { return values }
        for i in lo...hi {
            let w = allMidiValues[i]
            if w > 0 { values.append(contentsOf: repeatElement(i, count: w)) }
        }
        return values
    }

    /// Weighted-random pick from a multiset (uniform over the expanded list).
    private func pick(_ values: [Int], rng: inout SeededGenerator) -> Int? {
        guard !values.isEmpty else { return nil }
        return values[Int.random(in: 0..<values.count, using: &rng)]
    }

    private mutating func zero(_ index: Int) {
        guard index >= 0, index < 128 else { return }
        allMidiValues[index] = 0
    }

    /// `allMidiValues[index] *= factor` (integer-truncating), guarded.
    private mutating func scale(_ index: Int, _ factor: Double) {
        guard index >= 0, index < 128 else { return }
        allMidiValues[index] = Int(Double(allMidiValues[index]) * factor)
    }

    /// The value `allMidiValues[index]` would take after scaling, without writing.
    private func scaled(_ index: Int, _ factor: Double) -> Int {
        guard index >= 0, index < 128 else { return 0 }
        return Int(Double(allMidiValues[index]) * factor)
    }

    /// Multiply every octave of a pitch class by `multiplier` (integer-truncating).
    private mutating func multiplyNotes(_ midiValue: Int, _ multiplier: Double) {
        let pc = ((midiValue % 12) + 12) % 12
        var i = pc
        while i < 128 { allMidiValues[i] = Int(Double(allMidiValues[i]) * multiplier); i += 12 }
    }
}
