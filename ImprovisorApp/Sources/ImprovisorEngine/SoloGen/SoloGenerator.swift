//
//  SoloGenerator.swift
//  ImprovisorEngine
//
//  Grammar-based solo generation — a port of the essential behavior of
//  imp/lickgen (Grammar.run expansion + NoteChooser). Two stages:
//
//    1. Expand the grammar from `(startSymbol totalSlots)` by probabilistic
//       term rewriting, producing an ordered stream of abstract terminals:
//       abstract notes (C/L/A/S/H/X/Y/R + duration), slope contours, and
//       scale-degree specs.
//    2. Resolve each abstract terminal to a concrete pitch for the chord
//       sounding at that slot, honoring the pitch range and voice-leading
//       (nearest candidate of the right type, biased by the slope contour).
//
//  Faithful to the grammar/coloration model; the full expectancy/tension
//  scoring layer of the Java Scorer is intentionally deferred.
//

import Foundation

public struct SoloGenerator {
    let grammar: Grammar
    let parameters: SoloParameters
    private let nonterminalHeads: Set<String>
    /// Brick durations that have at least one expansion rule (so P only picks
    /// bricks that are grounded and make the recursion terminate).
    private let ruleArgs: [String: Set<Int>]

    public init(grammar: Grammar, parameters: SoloParameters? = nil) {
        self.grammar = grammar
        self.parameters = parameters ?? SoloParameters.from(grammar: grammar)
        self.nonterminalHeads = Set(grammar.rules.compactMap(\.head))
        var args: [String: Set<Int>] = [:]
        for rule in grammar.rules {
            guard let head = rule.head else { continue }
            if let n = rule.lhs.secondOrNil(), case let .long(v) = n {
                args[head, default: []].insert(v)
            }
        }
        self.ruleArgs = args
    }

    /// Generate a solo over `chords`. `seed` makes the result reproducible.
    public func generate(chords: ChordPart, seed: UInt64 = 0) -> MelodyPart {
        var rng = SeededGenerator(seed: seed)
        let terminals = expand(totalSlots: chords.size, &rng)
        return renderNotes(terminals, chords: chords, totalSlots: chords.size, &rng)
    }

    // MARK: - Stage 1: grammar expansion

    /// An abstract terminal produced by rewriting.
    enum Terminal {
        case note(type: Character, duration: Int)
        case slope(low: Int, high: Int, notes: [(type: Character, duration: Int)])
        case degree(degree: String, duration: Int)
    }

    private func expand(totalSlots: Int, _ rng: inout SeededGenerator) -> [Terminal] {
        guard totalSlots > 0 else { return [] }
        var terminals: [Terminal] = []

        // LIFO stack; RHS pushed reversed so the leftmost symbol pops first.
        var stack: [PolyValue] = [.list(.of([.symbol(grammar.startSymbol), .long(totalSlots)]))]
        var guardCounter = 0
        let guardLimit = 500_000
        var producedSlots = 0

        while let symbol = stack.popLast() {
            guardCounter += 1
            if guardCounter > guardLimit { break }
            // The cluster grammar overproduces; stop once we have enough
            // terminal duration to fill the form (it's truncated anyway).
            if producedSlots >= totalSlots { break }

            switch symbol {
            case let .symbol(s):
                // A bare symbol may be a nonterminal (e.g. Q3) or an abstract
                // note (e.g. C16, R2+8).
                if nonterminalHeads.contains(s) {
                    expandNonterminal(head: s, arg: 0, into: &stack, &rng)
                } else if let t = abstractNote(s) {
                    terminals.append(t); producedSlots += duration(of: t)
                }
            case let .list(list):
                guard let head = list.firstOrNil()?.symbolValue else { continue }
                if head == "slope", let slope = parseSlope(list) {
                    terminals.append(slope); producedSlots += duration(of: slope)
                } else if nonterminalHeads.contains(head) {
                    let arg = list.secondOrNil()?.intValue ?? 0
                    expandNonterminal(head: head, arg: arg, into: &stack, &rng)
                } else if let deg = parseDegree(list) {
                    terminals.append(deg); producedSlots += duration(of: deg)
                }
            default:
                break
            }
        }
        return terminals
    }

    /// Total slot duration a terminal contributes.
    private func duration(of terminal: Terminal) -> Int {
        switch terminal {
        case let .note(_, d): return d
        case let .degree(_, d): return d
        case let .slope(_, _, notes): return notes.reduce(0) { $0 + $1.duration }
        }
    }

    /// Expand a nonterminal by choosing a rule and pushing its substituted RHS
    /// (reversed, so the leftmost symbol is processed first). No matching rule
    /// means the nonterminal terminates (drops).
    private func expandNonterminal(head: String, arg: Int, into stack: inout [PolyValue],
                                   _ rng: inout SeededGenerator) {
        guard let rule = chooseRule(head: head, arg: arg, &rng) else { return }
        let bindings = binding(for: rule, arg: arg)
        for item in rule.rhs.toArray().reversed() {
            stack.append(substitute(item, bindings))
        }
    }

    /// Parse an abstract-note symbol like `C16`, `L8`, `R4`, `A2+8`.
    private func abstractNote(_ s: String) -> Terminal? {
        guard let first = s.first, "ACHLRSXY".contains(first) else { return nil }
        let durText = String(s.dropFirst())
        guard let d = durText.first, d.isNumber else { return nil }
        return .note(type: first, duration: Duration.slots(durText))
    }

    private func parseSlope(_ list: Polylist) -> Terminal? {
        let items = list.rest().toArray()
        guard items.count >= 3,
              let low = items[0].intValue, let high = items[1].intValue else { return nil }
        var notes: [(Character, Int)] = []
        for item in items.dropFirst(2) {
            if case let .symbol(s) = item, case let .note(t, d)? = abstractNote(s) {
                notes.append((t, d))
            }
        }
        guard !notes.isEmpty else { return nil }
        return .slope(low: low, high: high, notes: notes)
    }

    /// Parse a scale-degree spec `(X degree duration)`. The degree may be a
    /// plain number (`1`, `5`) or carry accidentals (`b2`, `#7`).
    private func parseDegree(_ list: Polylist) -> Terminal? {
        let items = list.toArray()
        guard items.count == 3 else { return nil }
        let degree = items[1].description  // "b2", "#7", "1", …
        let dur: Int
        if let d = items[2].intValue { dur = Duration.slots(String(d)) }
        else if let s = items[2].symbolValue { dur = Duration.slots(s) }
        else { return nil }
        guard degreeSemitone(degree) != nil else { return nil }
        return .degree(degree: degree, duration: dur)
    }

    /// Semitone offset of a scale-degree token from the chord root.
    /// e.g. `1`→0, `b3`→3, `5`→7, `#5`→8, `b7`→10, `7`→11, `9`→14.
    private func degreeSemitone(_ token: String) -> Int? {
        var accidental = 0
        var chars = Array(token)
        while let c = chars.first, c == "b" || c == "#" {
            accidental += (c == "#") ? 1 : -1
            chars.removeFirst()
        }
        guard let number = Int(String(chars)), number >= 1 else { return nil }
        let major = [0, 2, 4, 5, 7, 9, 11]                 // scale degrees 1..7
        let base = ((number - 1) / 7) * 12 + major[(number - 1) % 7]
        return base + accidental
    }

    // MARK: Rule matching & substitution

    private func chooseRule(head: String, arg: Int, _ rng: inout SeededGenerator) -> GrammarRule? {
        var candidates: [GrammarRule] = []
        for rule in grammar.rules where rule.head == head {
            guard let param = rule.lhs.secondOrNil() else {
                candidates.append(rule); continue           // headonly rule
            }
            if case let .long(literal) = param {
                if literal == arg { candidates.append(rule) } // literal match
            } else if param.symbolValue != nil {
                if isViable(rule, arg: arg) { candidates.append(rule) } // variable
            }
        }
        guard let idx = rng.weightedIndex(candidates.map(\.weight)) else { return nil }
        return candidates[idx]
    }

    /// A variable-parameter rule (e.g. `(P Y)`) is viable only if every
    /// grounded nonterminal it calls fits within `arg` and has its own rule —
    /// this both prevents gaps and guarantees the P/BRICK recursion terminates.
    private func isViable(_ rule: GrammarRule, arg: Int) -> Bool {
        guard arg > 0 else { return false }
        for item in rule.rhs.toArray() {
            guard case let .list(call) = item,
                  let head = call.firstOrNil()?.symbolValue,
                  nonterminalHeads.contains(head) else { continue }
            // A literal-arg call must reference a real rule and fit.
            if case let .long(n) = call.secondOrNil() {
                if n > arg { return false }
                if let known = ruleArgs[head], !known.contains(n) { return false }
            }
        }
        return true
    }

    private func binding(for rule: GrammarRule, arg: Int) -> [String: Int] {
        if let param = rule.lhs.secondOrNil(), let name = param.symbolValue {
            return [name: arg]
        }
        return [:]
    }

    /// Substitute bound variables and evaluate arithmetic within an RHS item.
    private func substitute(_ value: PolyValue, _ bindings: [String: Int]) -> PolyValue {
        switch value {
        case let .symbol(s):
            return bindings[s].map { PolyValue.long($0) } ?? value
        case .long, .double:
            return value
        case let .list(list):
            if let op = list.firstOrNil()?.symbolValue, "+-*/".contains(op), op.count == 1 {
                return .long(evaluate(value, bindings))
            }
            return .list(.of(list.toArray().map { substitute($0, bindings) }))
        }
    }

    private func evaluate(_ value: PolyValue, _ bindings: [String: Int]) -> Int {
        switch value {
        case let .long(v): return v
        case let .double(v): return Int(v)
        case let .symbol(s): return bindings[s] ?? 0
        case let .list(list):
            guard let op = list.firstOrNil()?.symbolValue else { return 0 }
            let a = list.secondOrNil().map { evaluate($0, bindings) } ?? 0
            let b = list.thirdOrNil().map { evaluate($0, bindings) } ?? 0
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/": return b != 0 ? a / b : 0
            default: return 0
            }
        }
    }

    // MARK: - Stage 2: note choosing

    private func renderNotes(_ terminals: [Terminal], chords: ChordPart, totalSlots: Int,
                             _ rng: inout SeededGenerator) -> MelodyPart {
        var melody = MelodyPart()
        var slot = 0
        // Seed the previous pitch near the middle of the allowed range.
        var previous = (parameters.minPitch + parameters.maxPitch) / 2

        for terminal in terminals {
            // Truncate to the form length (the grammar overproduces; Java's
            // truncateAbstractMelody does the same).
            if slot >= totalSlots { break }
            switch terminal {
            case let .note(type, duration):
                appendNote(type: type, duration: duration, target: nil,
                           chords: chords, slot: &slot, previous: &previous,
                           into: &melody, &rng)
            case let .degree(degree, duration):
                appendDegree(degree: degree, duration: duration,
                             chords: chords, slot: &slot, previous: &previous,
                             into: &melody)
            case let .slope(low, high, notes):
                // Distribute a contour of `displacement` semitones across the group.
                let lo = min(low, high), hi = max(low, high)
                let displacement = lo + Int(rng.next() % UInt64(hi - lo + 1))
                let base = previous
                for (i, note) in notes.enumerated() {
                    let fraction = Double(i + 1) / Double(notes.count)
                    let target = base + Int((Double(displacement) * fraction).rounded())
                    appendNote(type: note.type, duration: note.duration, target: target,
                               chords: chords, slot: &slot, previous: &previous,
                               into: &melody, &rng)
                }
            }
        }
        return melody
    }

    private func appendNote(type: Character, duration: Int, target: Int?,
                            chords: ChordPart, slot: inout Int, previous: inout Int,
                            into melody: inout MelodyPart, _ rng: inout SeededGenerator) {
        defer { slot += duration }

        // Rests: explicit R.
        if type == "R" {
            melody.append(.rest(Rest(duration: duration)))
            return
        }

        let chord = chords.chord(at: slot)
        let ideal = target ?? previous
        let pitch = choosePitch(type: type, chord: chord, ideal: ideal, &rng)
        melody.append(.note(Note(pitch: pitch, duration: duration)))
        previous = pitch
    }

    /// Append a note at a specific scale degree relative to the chord root
    /// (the `(X degree dur)` terminal), placed nearest the previous note.
    private func appendDegree(degree: String, duration: Int, chords: ChordPart,
                              slot: inout Int, previous: inout Int, into melody: inout MelodyPart) {
        defer { slot += duration }
        let chord = chords.chord(at: slot)
        let root = chord?.root.semitones ?? 0
        let offset = degreeSemitone(degree) ?? 0
        let pc = ((root + offset) % 12 + 12) % 12
        let pitch = nearestPitch(pitchClass: pc, to: previous)
        melody.append(.note(Note(pitch: pitch, duration: duration)))
        previous = pitch
    }

    /// The MIDI pitch of `pitchClass` nearest `reference`, clamped to range.
    private func nearestPitch(pitchClass pc: Int, to reference: Int) -> Int {
        var best = parameters.minPitch, bestDist = Int.max
        var m = ((pc - parameters.minPitch) % 12 + 12) % 12 + parameters.minPitch
        while m <= parameters.maxPitch {
            let dist = abs(m - reference)
            if dist < bestDist { bestDist = dist; best = m }
            m += 12
        }
        return max(parameters.minPitch, min(parameters.maxPitch, best))
    }

    /// Choose a concrete MIDI pitch of the requested abstract type for `chord`,
    /// as close as possible to `ideal`, within the pitch range.
    private func choosePitch(type: Character, chord: ChordSymbol?, ideal: Int,
                             _ rng: inout SeededGenerator) -> Int {
        let candidates = candidatePitchClasses(type: type, chord: chord)
        let pcs = candidates.isEmpty ? [((ideal % 12) + 12) % 12] : candidates

        // Enumerate every octave of every candidate pitch class within range,
        // then take the one nearest the ideal (ties broken low-to-high).
        var best = parameters.minPitch
        var bestDist = Int.max
        for pc in pcs {
            var m = ((pc - parameters.minPitch) % 12 + 12) % 12 + parameters.minPitch
            while m <= parameters.maxPitch {
                let dist = abs(m - ideal)
                if dist < bestDist { bestDist = dist; best = m }
                m += 12
            }
        }
        return max(parameters.minPitch, min(parameters.maxPitch, best))
    }

    /// The candidate pitch classes (0–11) for an abstract note type.
    private func candidatePitchClasses(type: Character, chord: ChordSymbol?) -> [Int] {
        guard let chord, chord.form != nil else {
            // No chord context: fall back to a C-major-ish scale.
            return [0, 2, 4, 5, 7, 9, 11]
        }
        let chordPCs = chord.chordTones.map(\.semitones)
        let colorPCs = chord.colorTones.map(\.semitones)
        let scalePCs = Array(Set(chordPCs + colorPCs)).sorted()

        switch type {
        case "C": return chordPCs
        case "L": return colorPCs.isEmpty ? chordPCs : colorPCs
        case "H": return Array(Set(chordPCs + colorPCs))
        case "S":
            return scalePCs.isEmpty ? chordPCs : scalePCs
        case "A":
            // Chromatic approach tones: a half step around each chord tone.
            return chordPCs.flatMap { [($0 + 1) % 12, ($0 + 11) % 12] }
        case "X", "Y":
            return Array(Set(chordPCs + colorPCs)) // arbitrary/outside → usable tones
        default:
            return chordPCs
        }
    }
}
