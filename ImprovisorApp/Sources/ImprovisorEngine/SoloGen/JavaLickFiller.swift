//
//  JavaLickFiller.swift
//  ImprovisorEngine
//
//  Stage 2 of solo generation, ported from the Java original: turn an abstract
//  melody (from JavaGrammarExpander) into notes.
//
//    imp/lickgen/LickGen.java     fillProbs, fillMelody, fillPartOfMelody,
//                                 fillMelodyHelper, addNote, chooseNote,
//                                 getNoteTypes, checkNote, getRandomNote,
//                                 makeRelativeNote, calcSection, the triadic
//                                 helpers (getBase, makeTriad …)
//    imp/lickgen/NoteChooser.java getNote
//
//  Random numbers come from one `JavaRandom` in Java's order. Behaviour that
//  looks odd is Java's and is kept on purpose (marked "Java:").
//
//  Not ported, because no shipped grammar reaches them: syncopation matching,
//  expectancy terminals (`E…`), soloist outlines.
//

import Foundation

/// A note or rest of a generated lick.
struct LickUnit: Equatable {
    /// MIDI pitch, or `nil` for a rest.
    var pitch: Int?
    var duration: Int
}

/// Java throws (and sometimes catches and retries) in places the port has to
/// follow; this is that exception.
private struct FillAbort: Error {}

struct JavaLickFiller {
    // LickGen note-type codes, kept as Java's numbers because they are stored
    // in a note's pitch field and compared there.
    static let NOTE = 1000, CHORD = 1001, SCALE = 1002, COLOR = 1003, APPROACH = 1004
    static let RANDOM = 1005, BASS = 1006, GOAL = 1007, OUTSIDE = 1008
    static let melodyGenLimit = 15
    static let noteGenLimit = 100
    static let repeatProb = 1.0 / 512.0
    static let minJumpUpperBound = 6
    static let firstScale = "Use_First_Scale"

    struct Parameters {
        var minPitch = 58, maxPitch = 82
        var minInterval = 0, maxInterval = 6
        var leapProb = 0.01
        var chordToneWeight = 0.7, colorToneWeight = 0.2, scaleToneWeight = 0.1
        var chordToneDecay = 0.0
        var avoidRepeats = true
        var rectify = true
        var scaleRoot = "C", scaleType = JavaLickFiller.firstScale

        /// `LickGen.getParameter`: the FIRST `(parameter (name value))` form wins.
        init(grammar: Grammar) {
            func value(_ name: String) -> PolyValue? {
                for form in grammar.forms where form.firstOrNil() == .symbol("parameter") {
                    if case let .list(pair)? = form.secondOrNil(), pair.firstOrNil() == .symbol(name) {
                        return pair.secondOrNil()
                    }
                }
                return nil
            }
            if let v = value("min-pitch")?.intValue { minPitch = v }
            if let v = value("max-pitch")?.intValue { maxPitch = v }
            if let v = value("min-interval")?.intValue { minInterval = v }
            if let v = value("max-interval")?.intValue { maxInterval = v }
            if let v = value("leap-prob")?.doubleValue { leapProb = v }
            if let v = value("chord-tone-weight")?.doubleValue { chordToneWeight = v }
            if let v = value("color-tone-weight")?.doubleValue { colorToneWeight = v }
            if let v = value("scale-tone-weight")?.doubleValue { scaleToneWeight = v }
            if let v = value("chord-tone-decay")?.doubleValue { chordToneDecay = v }
            if let v = value("avoid-repeats")?.symbolValue { avoidRepeats = v == "true" }
            if let v = value("rectify")?.symbolValue { rectify = v == "true" }
            if let v = value("scale-root")?.description { scaleRoot = v }
            if let v = value("scale-type")?.description { scaleType = v }
        }
    }

    let chords: ChordPart
    let vocabulary: Vocabulary?
    var parameters: Parameters

    // LickGen instance state.
    private var probs: [[Double]] = []
    private var pitchUsed = [Double](repeating: 1, count: 128)
    private var chordUsed: [String] = []
    private var chordUsedSection: [Int] = []
    private var position = 0
    private var oldPitch = 0
    private var oldOldPitch = 0
    /// The last unit added (Java `prevNote`), for merging rests and repeats.
    private var prevNote: LickUnit?

    // Triadic state.
    private var recentRoots = [Int?](repeating: nil, count: 6)
    private var recentTypes = [Int](repeating: 0, count: 7)
    private var rootCounter = 0
    private var maxTriadicPitch = 70, minTriadicPitch = 50
    private var lastInversion = 0
    private let mMinPitch = 60, mMaxPitch = 82      // Java: only set on the outline path

    init(chords: ChordPart, parameters: Parameters, vocabulary: Vocabulary? = nil) {
        self.chords = chords
        self.parameters = parameters
        self.vocabulary = vocabulary
    }

    // MARK: Chord access (ChordPart)

    private func entryIndex(at slot: Int) -> Int? {
        guard slot >= 0, slot < chords.size else { return nil }
        return chords.entries.firstIndex { slot >= $0.start && slot < $0.end }
    }

    private func currentChord(_ slot: Int) -> ChordSymbol? {
        entryIndex(at: slot).map { chords.entries[$0].symbol }
    }

    /// `ChordPart.getNextUniqueChordIndex`: start slot of the next chord with a
    /// different name, or -1.
    private func nextUniqueChordIndex(_ slot: Int) -> Int {
        guard let i = entryIndex(at: slot) else { return -1 }
        let name = chords.entries[i].symbol.name
        for entry in chords.entries[(i + 1)...] where entry.symbol.name != name { return entry.start }
        return -1
    }

    private func pcs(_ notes: [Int], rise: Int) -> [Int] { notes.map { JavaPitch.pc($0 + rise) } }

    private func spellPCs(_ c: ChordSymbol) -> [Int] {
        guard let f = c.form else { return [] }
        return pcs(f.spellNotes, rise: JavaPitch.rise(c.root))
    }

    private func colorPCs(_ c: ChordSymbol) -> [Int] {
        guard let f = c.form else { return [] }
        return pcs(f.colorNotes, rise: JavaPitch.rise(c.root))
    }

    private func priorityPCs(_ c: ChordSymbol) -> [Int] {
        guard !c.isNoChord, let f = c.form else { return [] }
        return pcs(f.priorityNotes, rise: JavaPitch.rise(c.root))
    }

    /// The scale tones the "preferred scale" setting selects for a chord
    /// (`nil` = no restriction).
    private func preferredScalePCs(_ c: ChordSymbol) -> [Int]? {
        let type = parameters.scaleType
        if type == "None" { return nil }
        if type == Self.firstScale {
            guard !c.isNoChord, let f = c.form, let scale = f.firstScaleSpell else { return [] }
            return pcs(scale, rise: JavaPitch.rise(c.root))
        }
        guard let root = PitchClass.named(parameters.scaleRoot.lowercased()),
              let notes = vocabulary?.scaleNotes(named: type) else { return [] }
        return pcs(notes, rise: JavaPitch.rise(root))
    }

    // MARK: LickGen.fillProbs

    /// Pitch-class weights per distinct chord, in order of first appearance.
    mutating func fillProbs(start: Int, length: Int) {
        probs = []
        chordUsed = []
        var next = start
        while next < start + length && next != -1 {
            if let chord = currentChord(next) {
                if chordUsed.contains(chord.name) {
                    next = nextUniqueChordIndex(next)
                    continue
                }
                chordUsed.append(chord.name)
                var p = [Double](repeating: 0, count: 12)
                // Scale first, then chord, then color: later ones add on top.
                if let scale = preferredScalePCs(chord) {
                    for pc in scale { p[pc] += parameters.scaleToneWeight }
                }
                for pc in priorityPCs(chord) { p[pc] += parameters.chordToneWeight }
                if !chord.isNoChord { for pc in colorPCs(chord) { p[pc] += parameters.colorToneWeight } }
                probs.append(p)
            }
            next = nextUniqueChordIndex(next)
        }
    }

    // MARK: Random helpers

    private func bernoulli(_ prob: Double, _ rng: inout JavaRandom) -> Bool { rng.nextDouble() > 1.0 - prob }

    private func randomNote(_ min: Int, _ max: Int, _ rng: inout JavaRandom) -> Int {
        Int(Double(min) + Double(max - min) * rng.nextDouble())
    }

    private func rand(_ min: Int, _ max: Int, _ rng: inout JavaRandom) -> Int {
        min + Int(rng.nextDouble() * Double(max - min + 1))
    }

    private func pitchWasUsed(_ pitch: Int) -> Double {
        pitch >= 0 && pitch < pitchUsed.count ? pitchUsed[pitch] : 1
    }

    private mutating func setPitchUsed(_ pitch: Int, _ value: Double) {
        if pitch >= 0 && pitch < pitchUsed.count { pitchUsed[pitch] = value }
    }

    // MARK: LickGen.fillMelody

    /// Fill the whole abstract melody starting at `start`. Returns the lick.
    mutating func fillMelody(_ abstract: [PolyValue], start: Int, rng: inout JavaRandom) -> [LickUnit] {
        oldPitch = 0
        // Java regroups the abstract melody into one section, splicing in any
        // list that is not a slope, a triadic or a scale degree.
        var items: [PolyValue] = []
        for item in abstract {
            if case let .list(l) = item {
                let head = l.firstOrNil()?.symbolValue
                if head == "slope" || head == "triadic" || head == "X" { items.append(item) }
                else { items.append(contentsOf: l.toArray()) }
            } else {
                items.append(item)
            }
        }
        guard !items.isEmpty else { return [] }

        var melody: [LickUnit] = []
        // Java retries the whole fill when a NullPointerException escapes.
        for _ in 0..<Self.melodyGenLimit {
            do {
                melody += try fillPart(items, start: start, &rng)
                break
            } catch {
                continue
            }
        }
        return melody
    }

    private static func range(_ lick: [LickUnit]) -> (low: Int, high: Int) {
        // MelodyPart.lowestPitch / highestPitch start at 127 / 0.
        var low = 127, high = 0
        for unit in lick {
            if let p = unit.pitch {
                low = min(low, p)
                high = max(high, p)
            }
        }
        return (low, high)
    }

    /// `fillPartOfMelody`: up to 15 attempts to stay within the pitch bounds.
    private mutating func fillPart(_ items: [PolyValue], start: Int, _ rng: inout JavaRandom) throws -> [LickUnit] {
        var lick: [LickUnit] = []
        let previousPitch = oldPitch
        for attempt in 0..<Self.melodyGenLimit {
            lick = []
            position = start
            oldPitch = previousPitch
            var tracked: (low: Int, high: Int) = (127, 0)
            try fillHelper(&lick, items, attempt: attempt, &rng, tracked: &tracked)
            if tracked.low >= parameters.minPitch - 1 && tracked.high <= parameters.maxPitch + 1 { return lick }
        }
        return lick
    }

    // MARK: LickGen.addNote

    private mutating func addNote(_ unit: LickUnit, to lick: inout [LickUnit],
                                  tracked: inout (low: Int, high: Int)) {
        position += unit.duration
        guard unit.duration > 0 else { return }          // Part.addUnit ignores these
        if unit.pitch == nil {
            if let prev = prevNote, prev.pitch == nil, !lick.isEmpty {
                lick[lick.count - 1].duration += unit.duration      // merge rests
                prevNote?.duration += unit.duration
            } else {
                lick.append(unit)
                prevNote = unit
            }
            return
        }
        if parameters.avoidRepeats, let prev = prevNote, let pp = prev.pitch, pp == unit.pitch, !lick.isEmpty {
            lick[lick.count - 1].duration += unit.duration          // merge a repeated pitch
            prevNote?.duration += unit.duration
        } else {
            setPitchUsed(unit.pitch!, Self.repeatProb)
            oldPitch = unit.pitch!
            lick.append(unit)
            prevNote = unit
            tracked.low = min(tracked.low, unit.pitch!)
            tracked.high = max(tracked.high, unit.pitch!)
        }
    }

    /// `parseNote`: the note type and duration of an abstract note such as `C8`.
    private func parse(_ s: String) -> (type: Int?, duration: Int) {
        let duration = Duration.slots(String(s.dropFirst()))
        switch s.first {
        case "H": return (Self.NOTE, duration)
        case "C": return (Self.CHORD, duration)
        case "S": return (Self.SCALE, duration)
        case "L": return (Self.COLOR, duration)
        case "A": return (Self.APPROACH, duration)
        case "X": return (Self.RANDOM, duration)
        case "Y": return (Self.OUTSIDE, duration)
        case "B": return (Self.BASS, duration)
        case "G": return (Self.GOAL, duration)
        case "R": return (nil, duration)
        default: return (Self.NOTE, duration)
        }
    }

    // MARK: LickGen.fillMelodyHelper

    private mutating func fillHelper(_ lick: inout [LickUnit], _ items: [PolyValue], attempt: Int,
                                     _ rng: inout JavaRandom, tracked: inout (low: Int, high: Int)) throws {
        let p = parameters
        prevNote = nil
        var section = 0
        chordUsed = []
        chordUsedSection = []

        var pitch = oldPitch
        if oldPitch == 0 {
            pitch = getRandomNote((p.maxPitch + p.minPitch) / 2, section: section, &rng)
        }
        oldPitch = pitch
        pitchUsed = [Double](repeating: 1, count: 128)

        guard let first = currentChord(position) else { throw FillAbort() }
        chordUsed.append(first.name)
        chordUsedSection.append(section)
        let index = nextUniqueChordIndex(position)       // Java: never updated afterwards

        var n = 0
        while n < items.count {
            let item = items[n]
            n += 1
            section = try calcSection(position, index, section)
            for i in pitchUsed.indices { pitchUsed[i] = pitchUsed[i] < 1 ? pitchUsed[i] * 2 : 1 }

            if JavaGrammarExpander.isScaleDegree(item) {
                guard let chord = currentChord(position) else { throw FillAbort() }
                guard let note = Self.relativeNote(item, chord) else { throw FillAbort() }
                addNote(note, to: &lick, tracked: &tracked)
                continue
            }

            if case let .list(inner) = item {
                guard inner.nonEmpty else { continue }
                if inner.first() == .symbol("slope") {
                    try fillSlope(inner.rest(), &lick, &pitch, attempt: attempt, &rng, tracked: &tracked)
                } else if inner.first() == .symbol("triadic") {
                    fillTriadic(inner, &lick, &rng, tracked: &tracked)
                }
                continue
            }

            guard case let .symbol(text) = item else { continue }
            let (type, duration) = parse(text)
            guard let type else {
                addNote(LickUnit(pitch: nil, duration: duration), to: &lick, tracked: &tracked)
                continue
            }

            switch type {
            case Self.BASS:
                guard let chord = currentChord(position) else { throw FillAbort() }
                addNote(LickUnit(pitch: chord.root.semitones + 48, duration: duration), to: &lick, tracked: &tracked)

            case Self.APPROACH:
                var hasNext = false
                if n < items.count, case .symbol = items[n] { hasNext = true }
                if hasNext, case let .symbol(nextText) = items[n] {
                    let nextDuration = parse(nextText).duration
                    var nextPitch = pitch
                    section = try calcSection(position, index, section)
                    for _ in 0..<Self.noteGenLimit {
                        nextPitch = getRandomNote(oldPitch, section: section, &rng)
                        let valid = checkNote(position, nextPitch, Self.CHORD)
                        // Java tests the PREVIOUS `pitch` for reuse here, not nextPitch.
                        if (!p.avoidRepeats || bernoulli(pitchWasUsed(pitch), &rng)) && valid { break }
                    }
                    setPitchUsed(nextPitch, Self.repeatProb)
                    var approach: Int
                    if nextPitch + 1 == oldPitch { approach = nextPitch - 1 }
                    else if nextPitch - 1 == oldPitch { approach = nextPitch + 1 }
                    else { approach = bernoulli(0.5, &rng) ? nextPitch + 1 : nextPitch - 1 }
                    oldOldPitch = oldPitch
                    oldPitch = nextPitch
                    addNote(LickUnit(pitch: approach, duration: duration), to: &lick, tracked: &tracked)
                    n += 1
                    addNote(LickUnit(pitch: nextPitch, duration: nextDuration), to: &lick, tracked: &tracked)
                } else {
                    pitch = getRandomNote(oldPitch, section: section, &rng)
                    oldOldPitch = oldPitch
                    oldPitch = pitch
                    addNote(LickUnit(pitch: pitch, duration: duration), to: &lick, tracked: &tracked)
                }

            case Self.RANDOM:
                let low = max(p.minPitch, oldPitch - p.maxInterval)
                let high = min(p.maxPitch, oldPitch + p.maxInterval)
                var guardCount = 0
                while true {
                    pitch = randomNote(low, high, &rng)
                    if !(pitch > oldPitch - p.minInterval && pitch < oldPitch + p.minInterval) { break }
                    guardCount += 1
                    if guardCount > 100_000 { break }     // Java would spin forever
                }
                oldOldPitch = oldPitch
                oldPitch = pitch
                addNote(LickUnit(pitch: pitch, duration: duration), to: &lick, tracked: &tracked)

            default:
                // Chord, color, scale, "helpful" and outside notes.
                if type == Self.OUTSIDE { oldOldPitch = oldPitch }
                if bernoulli(p.leapProb, &rng) {
                    if abs(oldPitch - p.maxPitch) > abs(oldPitch - p.minPitch) {
                        oldPitch = min(oldPitch + 12, p.maxPitch)
                    } else {
                        oldPitch = max(oldPitch - 12, p.minPitch)
                    }
                }
                for _ in 0..<Self.noteGenLimit {
                    pitch = getRandomNote(oldPitch, section: section, &rng)
                    let valid = checkNote(position, pitch, type)
                    if (!p.avoidRepeats || bernoulli(pitchWasUsed(pitch), &rng)) && valid { break }
                }
                if type == Self.OUTSIDE { pitch += 1 }     // a semitone off the choice
                addNote(LickUnit(pitch: pitch, duration: duration), to: &lick, tracked: &tracked)
            }
        }
    }

    /// `(slope min max notes…)`: each note within [min, max] semitones of the last.
    private mutating func fillSlope(_ body: Polylist, _ lick: inout [LickUnit], _ pitch: inout Int,
                                    attempt: Int, _ rng: inout JavaRandom,
                                    tracked: inout (low: Int, high: Int)) throws {
        guard body.length >= 2, case let .long(lower) = body.first(), case let .long(upper) = body.second()
        else { return }
        let notes = body.rest().rest().toArray()
        var i = 0
        while i < notes.count {
            guard case let .symbol(text) = notes[i] else { break }     // Java would not advance
            let (type, duration) = parse(text)
            if let type {
                if type == Self.APPROACH {
                    if i + 1 < notes.count {
                        i += 1
                        let (nextType, nextDuration) = parse(notes[i].description)
                        let nextPitch = try chooseNote(position + duration, oldPitch + lower, oldPitch + upper,
                                                       nextType ?? -1, oldPitch, attempt, &rng)
                        var approach: Int
                        if nextPitch + 1 == oldPitch { approach = nextPitch - 1 }
                        else if nextPitch - 1 == oldPitch { approach = nextPitch + 1 }
                        else if lower == 0 || upper == 0 {
                            approach = Self.APPROACH        // Java leaves the placeholder if neither applies
                            if upper > 0 { approach = nextPitch - 1 }
                            if lower < 0 { approach = nextPitch + 1 }
                        } else if lower > 0 { approach = nextPitch - 1 }
                        else if upper < 0 { approach = nextPitch + 1 }
                        else { approach = nextPitch - 1 }
                        addNote(LickUnit(pitch: approach, duration: duration), to: &lick, tracked: &tracked)
                        addNote(LickUnit(pitch: nextPitch, duration: nextDuration), to: &lick, tracked: &tracked)
                        pitch = nextPitch
                    } else {
                        pitch = try chooseNote(position, oldPitch + lower, oldPitch + upper, Self.SCALE,
                                               oldPitch, attempt, &rng)
                        addNote(LickUnit(pitch: pitch, duration: duration), to: &lick, tracked: &tracked)
                    }
                } else {
                    pitch = try chooseNote(position, oldPitch + lower, oldPitch + upper, type, oldPitch,
                                           attempt, &rng)
                    addNote(LickUnit(pitch: pitch, duration: duration), to: &lick, tracked: &tracked)
                }
            } else {
                addNote(LickUnit(pitch: nil, duration: duration), to: &lick, tracked: &tracked)
            }
            oldOldPitch = oldPitch
            oldPitch = pitch
            i += 1
        }
    }

    // MARK: calcSection / checkNote / getRandomNote

    private mutating func calcSection(_ pos: Int, _ index: Int, _ old: Int) throws -> Int {
        guard pos >= index && index != -1 else { return old }
        guard let chord = currentChord(pos) else { throw FillAbort() }
        if let i = chordUsed.firstIndex(of: chord.name), i < chordUsedSection.count {
            return chordUsedSection[i]
        }
        let section = chordUsedSection.count
        chordUsed.append(chord.name)
        chordUsedSection.append(section)
        return section
    }

    private func checkNote(_ pos: Int, _ pitch: Int, _ type: Int) -> Bool {
        guard let chord = currentChord(pos), !chord.isNoChord, let form = chord.form, !form.scales.isEmpty
        else { return true }
        let pc = pitch % 12
        switch type {
        case Self.NOTE: return true
        case Self.BASS: return JavaPitch.pc(pitch) == chord.root.semitones
        case Self.CHORD: return spellPCs(chord).contains(pc)
        case Self.SCALE:
            guard let scale = preferredScalePCs(chord) else { return true }
            return scale.contains(pc)
        case Self.COLOR: return colorPCs(chord).contains(pc)
        default: return false
        }
    }

    /// A pitch within the interval limits of `pitch`, weighted by the current
    /// section's pitch-class weights. Always draws once.
    private func getRandomNote(_ pitch: Int, section s: Int, _ rng: inout JavaRandom) -> Int {
        let p = parameters
        var avail: [(pitch: Int, prob: Double)] = []
        var sum = 0.0
        let section = s >= probs.count ? probs.count - 1 : s
        if section >= 0 {
            for i in 0..<12 where probs[section][i] != 0 {
                var candidate = (p.minPitch / 12) * 12 + i
                while candidate <= p.maxPitch {
                    if candidate >= p.minPitch
                        && ((candidate >= pitch - p.maxInterval && candidate <= pitch - p.minInterval)
                            || (candidate >= pitch + p.minInterval && candidate <= pitch + p.maxInterval)) {
                        avail.append((candidate, probs[section][i]))
                        sum += probs[section][i]
                    }
                    candidate += 12
                }
            }
        }
        let rand = rng.nextDouble()
        var offset = 0.0
        for a in avail {
            let prob = a.prob / sum
            if rand >= offset && rand < offset + prob { return a.pitch }
            offset += prob
        }
        return pitch
    }

    // MARK: chooseNote / NoteChooser

    /// NoteChooser's table: (wanted, haveChord, haveColor, haveRandom) →
    /// percentages for choosing a chord, color, random or scale tone.
    private static let chooserTable: [[Int]: [Int]] = [
        [0, 1, 1, 1]: [100, 0, 0, 0], [0, 1, 1, 0]: [100, 0, 0, 0], [0, 1, 0, 1]: [100, 0, 0, 0],
        [0, 1, 0, 0]: [100, 0, 0, 0], [0, 0, 1, 1]: [0, 100, 0, 0], [0, 0, 1, 0]: [0, 100, 0, 0],
        [0, 0, 0, 1]: [0, 0, 100, 0],
        [1, 1, 1, 1]: [0, 100, 0, 0], [1, 1, 1, 0]: [10, 90, 0, 0], [1, 1, 0, 1]: [85, 0, 15, 0],
        [1, 1, 0, 0]: [100, 0, 0, 0], [1, 0, 1, 1]: [0, 100, 0, 0], [1, 0, 1, 0]: [0, 100, 0, 0],
        [1, 0, 0, 1]: [0, 0, 100, 0],
        [3, 1, 1, 1]: [0, 0, 0, 100], [3, 1, 1, 0]: [0, 0, 0, 100], [3, 1, 0, 1]: [0, 0, 0, 100],
        [3, 1, 0, 0]: [0, 0, 0, 100], [3, 0, 1, 1]: [0, 0, 0, 100], [3, 0, 1, 0]: [0, 0, 0, 100],
        [3, 0, 0, 1]: [0, 0, 100, 0],
        [2, 1, 1, 1]: [50, 25, 25, 0], [2, 1, 1, 0]: [80, 20, 0, 0], [2, 1, 0, 1]: [50, 0, 50, 0],
        [2, 1, 0, 0]: [100, 0, 0, 0], [2, 0, 1, 1]: [0, 50, 50, 0], [2, 0, 1, 0]: [0, 100, 0, 0],
        [2, 0, 0, 1]: [0, 0, 100, 0],
    ]

    private func chooseNote(_ pos: Int, _ lowIn: Int, _ highIn: Int, _ typeIn: Int, _ lastPitch: Int,
                            _ attempt: Int, _ rng: inout JavaRandom) throws -> Int {
        var low = lowIn, high = highIn, type = typeIn
        _ = rng.nextInt(100)                 // goal-note roll; GOAL_PROB is 0

        if low == high {                     // relax a constant interval
            if low != oldPitch + 1 { low -= 1 }
            if high != oldPitch - 1 { high += 1 }
        }
        if low - lastPitch >= Self.minJumpUpperBound { low -= Self.minJumpUpperBound / 2 }
        if high - lastPitch <= -Self.minJumpUpperBound { high += Self.minJumpUpperBound / 2 }
        if low > high && low > lastPitch { low = high }
        if high < low && high < lastPitch { high = low }
        if type == Self.NOTE { type = Self.SCALE }

        var chord = currentChord(pos)
        if chord == nil { type = Self.RANDOM }
        else if chord!.isNoChord {
            let next = nextUniqueChordIndex(pos)
            chord = next < 0 ? nil : currentChord(next)
        }
        if chord == nil || chord!.isNoChord { type = Self.RANDOM }

        var numTypes = [0, 0, 0, 0]
        var noteTypes: [Int] = []
        var j = 0
        while j == 0 || (type == Self.CHORD && j < 3 && numTypes[0] == 0) {
            guard high >= low else { throw FillAbort() }
            noteTypes = (low...high).map { pitch in
                if checkNote(pos, pitch, Self.CHORD) { return Self.CHORD }
                if checkNote(pos, pitch, Self.COLOR) { return Self.COLOR }
                return Self.RANDOM
            }
            // Java: the counts are NOT reset between widenings.
            for t in noteTypes {
                switch t {
                case Self.CHORD: numTypes[0] += 1; numTypes[3] += 1
                case Self.COLOR: numTypes[1] += 1; numTypes[3] += 1
                default: numTypes[2] += 1
                }
            }
            if type == Self.CHORD && numTypes[0] == 0 {
                if low != oldPitch + 1 { low -= 1 }
                if high != oldPitch - 1 { high += 1 }
            }
            j += 1
        }

        // NoteChooser.getNote
        let wanted: Int
        switch type {
        case Self.CHORD: wanted = 0
        case Self.COLOR: wanted = 1
        case Self.RANDOM: wanted = 2
        case Self.SCALE: wanted = 3
        default: throw FillAbort()           // Java: no table row → NullPointerException
        }
        let key = [wanted, numTypes[0] != 0 ? 1 : 0, numTypes[1] != 0 ? 1 : 0, numTypes[2] != 0 ? 1 : 0]
        guard let percentages = Self.chooserTable[key] else { throw FillAbort() }

        var randNum = rng.nextInt(100) + 1
        var newType = 0
        for (i, percent) in percentages.enumerated() {
            randNum -= percent
            if randNum <= 0 { newType = i; break }
        }
        guard numTypes[newType] > 0 else { throw FillAbort() }
        randNum = rng.nextInt(numTypes[newType]) + 1
        let typeMap = [Self.CHORD, Self.COLOR, Self.RANDOM, Self.SCALE]
        var pitchDiff = 0
        for (i, t) in noteTypes.enumerated() {
            if t == typeMap[newType] || (newType == 3 && (t == Self.CHORD || t == Self.COLOR)) { randNum -= 1 }
            if randNum <= 0 { pitchDiff = i; break }
        }
        var finalPitch = low + pitchDiff
        if attempt >= Self.melodyGenLimit - 1 {
            while finalPitch > parameters.maxPitch { finalPitch -= 12 }
            while finalPitch < parameters.minPitch { finalPitch += 12 }
        }
        return finalPitch
    }

    // MARK: makeRelativeNote

    /// `(X degree duration)`: a scale degree over the chord's root in the
    /// middle-C octave, by chord family.
    static func relativeNote(_ item: PolyValue, _ chord: ChordSymbol) -> LickUnit? {
        guard case let .list(l) = item, l.length == 3 else { return nil }
        var pitch = chord.root.semitones + 60
        var degree = 1
        switch l.second() {
        case let .long(v): degree = v
        case let .symbol(s):
            var text = Substring(s)
            while let c = text.first, c == "b" || c == "#" {
                pitch += c == "b" ? -1 : 1
                text = text.dropFirst()
            }
            guard let v = Int(text) else { return nil }
            degree = v
        default: break
        }
        var octave = 0
        while degree < 0 { octave -= 1; degree += 8 }       // Java: 8 going down, 7 going up
        while degree > 7 { octave += 1; degree -= 7 }

        let family = chord.form?.family ?? "other"
        let steps: [Int]        // offsets for degrees 2…7
        switch family {
        case "minor": steps = [2, 3, 5, 7, 9, 11]            // Java: natural 6 and 7
        case "minor7", "half-diminished": steps = [2, 3, 5, 7, 9, 10]
        case "dominant": steps = [2, 4, 5, 7, 9, 10]
        case "diminished": steps = [2, 3, 5, 6, 8, 9]
        case "augmented": steps = [2, 4, 5, 8, 9, 10]
        default: steps = [2, 4, 5, 7, 9, 11]
        }
        if degree >= 2 && degree <= 7 { pitch += steps[degree - 2] }
        pitch += octave * 12
        let duration = Duration.slots(l.third().description)
        guard duration != 0 else { return nil }
        return LickUnit(pitch: pitch, duration: duration)
    }

    // MARK: Triadic (`(triadic duration unit)`)

    private mutating func fillTriadic(_ inner: Polylist, _ lick: inout [LickUnit], _ rng: inout JavaRandom,
                                      tracked: inout (low: Int, high: Int)) {
        let length = Duration.slots(inner.second().description)
        var noteIn = prevNote?.pitch
        if noteIn == nil || noteIn! > mMaxPitch || noteIn! < mMinPitch {
            noteIn = mMinPitch + (mMaxPitch - mMinPitch) / 2
        }
        recentRoots = [Int?](repeating: nil, count: 6)
        recentTypes = [Int](repeating: 0, count: 7)
        var base = getBase(noteIn!, &rng)
        lastInversion = rand(0, 4, &rng)
        let unit: Int, count: Int, remainder: Int
        switch inner.third().description {
        case "16" where length % 30 == 0: (unit, count, remainder) = (30, length / 90, (length / 90) % max(1, length / 30))
        case "16/3" where length % 20 == 0: (unit, count, remainder) = (20, length / 60, (length / 60) % max(1, length / 20))
        case "8" where length % 60 == 0: (unit, count, remainder) = (60, length / 180, (length / 180) % max(1, length / 60))
        case "8/3" where length % 40 == 0: (unit, count, remainder) = (40, length / 120, (length / 120) % max(1, length / 40))
        default: return
        }
        for _ in 0..<count {
            adjustTriadicPitch(base)
            let triad = makeTriad(base, lastInversion, &rng)
            for pitch in triad { addNote(LickUnit(pitch: pitch, duration: unit), to: &lick, tracked: &tracked) }
            base = getBase(triad[2], &rng)
        }
        if remainder == 1 || remainder == 2 {
            let triad = makeTriad(base, lastInversion, &rng)
            for pitch in triad.prefix(remainder) {
                addNote(LickUnit(pitch: pitch, duration: unit), to: &lick, tracked: &tracked)
            }
        }
    }

    private mutating func getBase(_ noteIn: Int, _ rng: inout JavaRandom) -> Int {
        let randNum = rand(0, 19, &rng)
        var out = noteIn
        if randNum <= 8 {
            out = noteIn - 1 >= minTriadicPitch ? noteIn - 1 : noteIn + 1
        } else if randNum <= 17 {
            out = noteIn + 1 <= maxTriadicPitch ? noteIn + 1 : noteIn - 1
            _ = rand(0, 17, &rng)             // Java draws again here and discards it
        }
        return out
    }

    private mutating func adjustTriadicPitch(_ pitch: Int) {
        maxTriadicPitch = pitch + 12 <= mMaxPitch ? pitch + 12 : mMaxPitch
        minTriadicPitch = pitch - 12 >= mMinPitch ? pitch - 12 : mMinPitch
    }

    private func trueRoot(_ base: Int, _ inversion: Int) -> Int {
        switch inversion {
        case 2: return base + 5
        case 1: return recentTypes[6] == 5 ? base + 8 : base + 9
        default: return base
        }
    }

    private func putInRange(_ pitch: Int) -> Int {
        if pitch > maxTriadicPitch { return maxTriadicPitch - (12 - ((pitch - maxTriadicPitch) % 12)) }
        if pitch < minTriadicPitch { return minTriadicPitch + (12 - ((minTriadicPitch - pitch) % 12)) }
        return pitch
    }

    private mutating func makeTriad(_ base: Int, _ inversion: Int, _ rng: inout JavaRandom) -> [Int] {
        var newInversion = 11
        var guardCount = 0
        repeat {
            let pick = rand(0, 10, &rng)
            switch pick {
            case 0...8:
                newInversion = pick / 3
                recentTypes[6] = rand(0, 1, &rng) == 0 ? 5 : 6
            case 9:
                newInversion = 3
                recentTypes[6] = 7
            default:
                newInversion = 4
                recentTypes[6] = 8
            }
            guardCount += 1
        } while (newInversion == inversion || recentRoots.indices.contains { i in
            recentRoots[i] != nil && trueRoot(base, newInversion) == recentRoots[i]! && recentTypes[6] == recentTypes[i]
        }) && guardCount < 10_000

        var triad = [base, base, base]
        let major = recentTypes[6] == 5
        switch newInversion {
        case 4: triad[1] = base + 4; triad[2] = base + 8
        case 3: triad[1] = base + 3; triad[2] = base + 6
        case 2: triad[1] = base + 5; triad[2] = major ? base + 9 : base + 8
        case 1: triad[1] = major ? base + 3 : base + 4; triad[2] = major ? base + 8 : base + 9
        default: triad[2] = base + 7; triad[1] = major ? base + 4 : base + 3
        }
        recentRoots[rootCounter] = trueRoot(base, newInversion)
        recentTypes[rootCounter] = recentTypes[6]
        rootCounter = (rootCounter + 1) % 6
        lastInversion = newInversion

        if rand(0, 1, &rng) == 0 { triad.swapAt(1, 2) }
        if rand(0, 1, &rng) == 0 { triad[1] -= 12 }
        if triad[0] - triad[1] == 4 || triad[1] - triad[0] == 4 {
            if rand(0, 1, &rng) == 0 { triad[2] -= 12 }
        } else if triad[0] - triad[1] <= 3 || triad[1] - triad[0] <= 3 {
            if triad[0] > triad[1] && triad[2] > triad[1] { triad[2] -= 12 }
            else if triad[0] < triad[1] && triad[2] < triad[1] { triad[2] += 12 }
        } else {
            if triad[0] < triad[1] && triad[1] < triad[2] { triad[2] -= 12 }
            else if triad[0] > triad[1] && triad[2] < triad[1] { triad[2] += 12 }
        }
        return triad.map(putInRange)
    }
}
