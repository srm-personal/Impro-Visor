//
//  StyleRenderer.swift
//  ImprovisorEngine
//
//  A faithful port of the accompaniment rendering in the Java original:
//
//    imp/style/Style.java            render, makeDrumline, makeChordline,
//                                    addToBassline, getPattern, getChordPattern
//    imp/style/stylePatterns/        BassPattern, ChordPattern, DrumPattern,
//                                    DrumRuleRep (applyRules, getDuration, …)
//    imp/data/Part.java              makeSwing, the slot/unit model
//
//  The goal is event-for-event identity with Java for the same seed (see
//  ImprovisorApp/Testing), so this follows the Java control flow closely and
//  draws random numbers from ONE `JavaRandom` in exactly Java's order — also
//  where a draw's result cannot change anything. Java behaviour that looks odd
//  is reproduced on purpose and marked "Java:".
//
//  Positions and durations are in slots (120 per beat). Java renders at 480
//  ticks per beat = 4 ticks per slot with integer arithmetic, so nothing is
//  lost by staying in slots.
//

import Foundation

// MARK: - Slot part (imp.data.Part)

/// The part of Java's `Part` that rendering needs: an array of slots, each
/// either empty or the start of a unit (note or rest).
struct SlotPart {
    struct Unit {
        /// MIDI pitch, or `nil` for a rest.
        var pitch: Int?
        var duration: Int
        var volume: Int
    }

    private(set) var slots: [Unit?] = []
    /// Java keeps a separate count that goes stale when swing overwrites a
    /// unit; iteration is bounded by it, so it is kept the same way.
    private(set) var unitCount = 0

    var size: Int { slots.count }

    /// `Part.addUnit`: append at the end. Units of duration ≤ 0 are ignored.
    mutating func add(pitch: Int?, duration: Int, volume: Int = 127) {
        guard duration > 0 else { return }
        slots.append(Unit(pitch: pitch, duration: duration, volume: volume))
        slots.append(contentsOf: [Unit?](repeating: nil, count: duration - 1))
        unitCount += 1
    }

    /// `Part.getUnitRhythmValue`: distance to the next unit, or to the end.
    private func rhythmValue(at index: Int) -> Int {
        var i = index + 1
        while i < slots.count {
            if slots[i] != nil { return i - index }
            i += 1
        }
        return slots.count - index
    }

    /// `Part.makeSwing()` with one swing value, or `Part.makeSwing(SectionInfo)`
    /// when `swingAt` supplies the value per beat.
    ///
    /// For every beat: if nothing starts on the second sixteenth and a unit
    /// starts on the off-beat eighth lasting at least an eighth, that unit is
    /// moved to `int(beatValue * swing)`. Afterwards EVERY unit's duration is
    /// reset to the gap up to the next unit.
    mutating func makeSwing(beatValue: Int = Constants.BEAT, swingAt: (Int) -> Double) {
        guard beatValue >= 4 else { return }
        var i = 0
        while i + beatValue - 1 < slots.count {
            let swing = swingAt(i)
            let unit1 = slots[i + beatValue / 4]
            if unit1 == nil, let unit2 = slots[i + beatValue / 2], unit2.duration >= beatValue / 2 {
                let offset = Int(Double(beatValue) * swing)
                if i + offset < slots.count {
                    slots[i + beatValue / 2] = nil
                    slots[i + offset] = unit2     // Java: may overwrite a unit already there
                }
            }
            i += beatValue
        }
        for index in unitIndices() {
            let value = rhythmValue(at: index)
            slots[index]?.duration = value
        }
    }

    mutating func makeSwing(_ swing: Double) {
        makeSwing(swingAt: { _ in swing })
    }

    /// Slot indices of the units, in `PartIterator` order: at most `unitCount`.
    func unitIndices() -> [Int] {
        var out: [Int] = []
        var index = 0
        while out.count < unitCount && index < slots.count {
            out.append(index)
            var next = index + 1
            while next < slots.count && slots[next] == nil { next += 1 }
            index = next
        }
        return out
    }

    /// The units in iteration order.
    func units() -> [Unit] {
        unitIndices().compactMap { slots[$0] }
    }

    /// `MelodyPart.render`: lay the units end to end from `start`; rests only
    /// advance time. Returns the notes and the end time.
    func render(from start: Int, channel: UInt8) -> (notes: [ScheduledNote], end: Int) {
        var time = start
        var notes: [ScheduledNote] = []
        for unit in units() {
            if let pitch = unit.pitch {
                // Note.render clamps to MIN_PITCH…MAX_PITCH.
                notes.append(ScheduledNote(pitch: max(0, min(127, pitch)), velocity: unit.volume,
                                           startTick: time, duration: unit.duration, channel: channel))
            }
            time += unit.duration
        }
        return (notes, time)
    }
}

// MARK: - Compiled patterns

/// A style prepared for rendering: patterns parsed into Java's rule tables.
struct CompiledStyle {
    // BassPattern.ruleTypes indices.
    static let bassRuleTypes = ["X", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10",
                                "B", "C", "S", "A", "N", "R", "=", "U", "D", "V"]
    static let PITCH = 0, BASS = 11, CHORD = 12, SCALE = 13, APPROACH = 14, NEXT = 15
    static let REST = 16, EQUAL = 17, VOLUME = 20
    static let FLATTEN = 100, SHARPEN = 200

    struct BassPattern {
        var rules: [Int] = []
        var durations: [String] = []
        var modifiers: [String] = []
        var weight: Double
        /// `BassPattern.getDuration`: getDuration0 of every non-volume rule.
        var duration: Int {
            zip(rules, durations).reduce(0) { $1.0 == CompiledStyle.VOLUME ? $0 : $0 + Duration.slots0($1.1) }
        }
    }

    enum ChordRule {
        case strike(Int)
        case rest(Int)
        case volume(Int)
        case degree(Int, Int)          // scale degree, slots
        var slots: Int {
            switch self {
            case let .strike(s), let .rest(s), let .degree(_, s): return s
            case .volume: return 0
            }
        }
    }

    struct ChordPattern {
        var rules: [ChordRule] = []
        var weight: Double
        var push = 0
        var duration: Int { rules.reduce(0) { $0 + $1.slots } }

        /// `ChordPattern.splitChordPattern`: the first `desired` slots, and the rest.
        func split(_ desired: Int) -> (prefix: ChordPattern, suffix: ChordPattern) {
            var prefix = ChordPattern(weight: Double(StyleParser.defaultWeight))
            var suffix = ChordPattern(weight: Double(StyleParser.defaultWeight))
            var accumulated = 0
            var difference = accumulated - desired
            var index = 0
            while index < rules.count && difference < 0 {
                let rule = rules[index]
                index += 1
                if case .volume = rule {
                    prefix.rules.append(rule)
                    continue
                }
                let slots = rule.slots
                accumulated += slots
                difference = accumulated - desired
                if difference <= 0 {
                    prefix.rules.append(rule)
                } else {
                    prefix.rules.append(rule.withSlots(slots - difference))
                    suffix.rules.append(rule.withSlots(difference))
                }
            }
            suffix.rules.append(contentsOf: rules[index...])
            return (prefix, suffix)
        }
    }

    struct DrumRule {
        var instrument: Int
        /// (type, suffix) pairs, e.g. ("X", "8").
        var elements: [(type: Character, suffix: String)] = []
        /// `DrumRuleRep.getDuration`: strikes and rests only.
        var duration: Int {
            elements.reduce(0) { ($1.type == "X" || $1.type == "R") ? $0 + Duration.slots($1.suffix) : $0 }
        }
    }

    struct DrumPattern {
        var drums: [DrumRule] = []
        var weight: Double
        /// `DrumPattern.getDuration`: the longest drum, or 480 with no drums.
        var duration: Int { drums.isEmpty ? 480 : (drums.map(\.duration).max() ?? 0) }
    }

    let style: Style
    let bassLow: Int, bassHigh: Int, chordLow: Int, chordHigh: Int
    let bass: [BassPattern]
    let chord: [ChordPattern]
    let drums: [DrumPattern]

    init(_ style: Style) {
        self.style = style
        // Java defaults: chord c-…a, bass g---…g- (Style.java:167-193).
        bassLow = Register.midi(ofNoteName: style.bassLow, fallback: 31)
        bassHigh = Register.midi(ofNoteName: style.bassHigh, fallback: 55)
        chordLow = Register.midi(ofNoteName: style.chordLow, fallback: 48)
        chordHigh = Register.midi(ofNoteName: style.chordHigh, fallback: 69)
        bass = style.bassPatterns.map(Self.compileBass)
        chord = style.chordPatterns.map(Self.compileChord)
        drums = style.drumPatterns.map(Self.compileDrums)
    }

    /// The parts of a list rule `(X a b [c])`, as Java's `toString()` of each.
    private static func listParts(_ token: String) -> [String]? {
        guard token.hasPrefix("("), case let .list(list)? = PolyaParser.parse(token) else { return nil }
        return list.toArray().map(\.description)
    }

    private static func lookup(_ rule: String) -> Int {
        bassRuleTypes.firstIndex(of: rule) ?? -1
    }

    /// `BassPattern.addRule`.
    private static func addBassRule(_ p: inout BassPattern, _ rule: String, _ duration: String, _ modifier: String) {
        if rule.count == 2 {                          // e.g. b5, #4 — and, in Java, "10"
            let prefix = String(rule.prefix(1)), rest = String(rule.dropFirst())
            if prefix == "b" { p.rules.append(lookup(rest) + FLATTEN) }
            else if prefix == "#" { p.rules.append(lookup(rest) + SHARPEN) }
            else { return }                           // Java: "Unknown bass rule", rule dropped
        } else {
            p.rules.append(lookup(rule))
        }
        p.durations.append(duration)
        p.modifiers.append(modifier)
    }

    static func compileBass(_ pattern: Pattern) -> BassPattern {
        var p = BassPattern(weight: pattern.weight)
        for token in pattern.rules {
            if let parts = listParts(token) {
                guard parts.count >= 3 else { continue }
                addBassRule(&p, parts[1], parts[2], parts.count == 4 ? parts[3] : "")
            } else if token == "U" || token == "D" {
                addBassRule(&p, token, "", "")
            } else if !token.isEmpty {
                addBassRule(&p, String(token.prefix(1)), String(token.dropFirst()), "")
            }
        }
        return p
    }

    static func compileChord(_ pattern: Pattern) -> ChordPattern {
        var p = ChordPattern(weight: pattern.weight)
        if let push = pattern.push { p.push = Duration.slots(push) }
        for token in pattern.rules {
            if let parts = listParts(token) {
                guard parts.count >= 3 else { continue }
                // Java stores the degree text as the rule; applyRules parses it.
                switch parts[1] {
                case "X": p.rules.append(.strike(Duration.slots(parts[2])))
                case "R": p.rules.append(.rest(Duration.slots(parts[2])))
                case "V": p.rules.append(.volume(Int(parts[2]) ?? 127))
                default:
                    if let degree = Int(parts[1]) { p.rules.append(.degree(degree, Duration.slots(parts[2]))) }
                }
            } else if let letter = token.first {
                let suffix = String(token.dropFirst())
                switch letter {
                case "X": p.rules.append(.strike(Duration.slots(suffix)))
                case "R": p.rules.append(.rest(Duration.slots(suffix)))
                case "V": p.rules.append(.volume(Int(suffix) ?? 127))
                default: break
                }
            }
        }
        return p
    }

    static func compileDrums(_ pattern: ImprovisorEngine.DrumPattern) -> DrumPattern {
        var p = DrumPattern(weight: pattern.weight)
        for voice in pattern.voices {
            var rule = DrumRule(instrument: DrumBank.number(for: voice.name))
            for hit in voice.hits {
                guard let type = hit.first else { continue }
                rule.elements.append((type, String(hit.dropFirst())))
            }
            p.drums.append(rule)
        }
        return p
    }
}

extension CompiledStyle.ChordRule {
    func withSlots(_ slots: Int) -> CompiledStyle.ChordRule {
        switch self {
        case .strike: return .strike(slots)
        case .rest: return .rest(slots)
        case let .degree(d, _): return .degree(d, slots)
        case .volume: return self
        }
    }
}

// MARK: - Renderer

/// Output of rendering one section.
struct SectionRender {
    var bass: [ScheduledNote] = []
    var chords: [ScheduledNote] = []
    var drums: [ScheduledNote] = []
}

struct StyleRenderer {
    let cs: CompiledStyle
    let bassChannel: UInt8
    let chordChannel: UInt8
    /// Swing applied to the accompaniment (`Style.accompanimentSwing`).
    let swing: Double

    /// `Style.residualChordPattern`: what is left of a chord pattern that was
    /// cut at a chord change, carried to the next chord of the section.
    private var residual: CompiledStyle.ChordPattern?

    init(_ cs: CompiledStyle, bassChannel: UInt8, chordChannel: UInt8, applySwing: Bool = true) {
        self.cs = cs
        self.bassChannel = bassChannel
        self.chordChannel = chordChannel
        self.swing = applySwing ? cs.style.compSwing : 0.5
    }

    // MARK: Style.getPattern

    /// Choose among the longest patterns that fit `duration`, by weight. When
    /// none fits, Java takes the SHORTEST pattern that is at least as long and
    /// plays it whole.
    private func pickPattern(durations: [Int], weights: [Double], duration: Int,
                             _ rng: inout JavaRandom) -> Int? {
        var largest = 0
        for d in durations where d > largest && d <= duration { largest = d }
        if largest == 0 {
            var shortest = Int.max
            var choice: Int?
            for (i, d) in durations.enumerated() where d >= duration && d < shortest {
                shortest = d
                choice = i
            }
            return choice
        }
        var sum = 0.0
        var good: [Int] = []
        for (i, d) in durations.enumerated() where d == largest {
            sum += weights[i]
            good.append(i)
        }
        guard Int(sum) > 0 else { return nil }     // Java: nextInt(0) throws
        let random = rng.nextInt(Int(sum))
        var running = 0.0
        for i in good {
            running += weights[i]
            if Double(random) < running { return i }
        }
        return nil
    }

    // MARK: Style.getChordPattern

    private mutating func setResidual(_ pattern: CompiledStyle.ChordPattern?) {
        residual = (pattern?.duration ?? 0) == 0 ? nil : pattern
    }

    private mutating func chordPattern(_ desired: Int, _ rng: inout JavaRandom) -> CompiledStyle.ChordPattern? {
        if let r = residual {
            if r.duration <= desired {
                setResidual(nil)
                return r
            }
            let parts = r.split(desired)
            setResidual(parts.suffix)
            return parts.prefix
        }
        var good: [CompiledStyle.ChordPattern] = []
        var goodSum = 0.0, allSum = 0.0
        for p in cs.chord {
            allSum += p.weight
            if p.duration > desired {
                good.append(p)
                goodSum += p.weight
            }
        }
        var weights = 0.0
        if goodSum > 0 {
            guard Int(goodSum) > 0 else { return nil }
            let random = rng.nextInt(Int(goodSum))
            for p in good {
                weights += p.weight
                if Double(random) <= weights {
                    if p.duration == desired { return p }
                    let parts = p.split(desired)
                    setResidual(parts.suffix)
                    return parts.prefix
                }
            }
        } else {
            if allSum == 0 { return nil }
            guard Int(allSum) > 0 else { return nil }
            let random = rng.nextInt(Int(allSum))
            for p in cs.chord {
                weights += p.weight
                if Double(random) <= weights {
                    if p.duration <= desired { return p }
                    let parts = p.split(desired)
                    setResidual(parts.suffix)
                    return parts.prefix
                }
            }
        }
        return nil
    }

    // MARK: Style.render

    /// Render slots `startIndex..<endIndex` of `chordPart` starting at `time`.
    /// Returns the time after the section.
    mutating func render(chordPart: ChordPart, startIndex: Int, endIndex: Int, time startTime: Int,
                         useDrums: Bool = true, rng: inout JavaRandom,
                         into out: inout SectionRender) -> Int {
        setResidual(nil)
        var time = startTime
        let entries = chordPart.entries
        if cs.style.noStyle {
            return renderNoStyle(chordPart: chordPart, startIndex: startIndex, endIndex: endIndex,
                                 time: startTime, rng: &rng, into: &out)
        }

        if useDrums && !cs.drums.isEmpty {
            makeDrumline(time: startTime, duration: endIndex - startIndex, &rng, &out)
        }

        // The chord in force at startIndex (ChordPart.getCurrentChordIndex).
        var i = entries.lastIndex { $0.start <= startIndex } ?? 0
        var next: ChordPart.Entry?
        var index = startIndex
        var bassline: [BassItem] = []
        var previousBassNote = (cs.bassHigh + cs.bassLow) / 2
        var previousChord: [Int] = []

        while i < entries.count || next != nil {
            if next == nil {
                index = entries[i].start
                next = entries[i]
                i += 1
            }
            guard let current = next else { break }
            var rhythmValue = current.duration
            if startIndex > index { rhythmValue -= startIndex - index }
            if i < entries.count {
                index = entries[i].start
                next = entries[i]
                i += 1
            } else {
                next = nil
                index = chordPart.size
            }
            if endIndex <= index { rhythmValue -= index - endIndex }

            let chord = current.symbol
            let silent = chord.isNoChord || chord.form == nil
            let nextChord: ChordSymbol
            if let n = next, !n.symbol.isNoChord { nextChord = n.symbol } else { nextChord = chord }

            if !silent {
                previousChord = makeChordline(time: time, chord: chord, previousChord: previousChord,
                                              duration: rhythmValue, &rng, &out)
            }

            // Adjust the bass octave between chords only, one octave at most.
            if previousBassNote > cs.bassHigh { previousBassNote -= 12 }
            else if cs.bassLow > previousBassNote { previousBassNote += 12 }

            if !silent {
                addToBassline(&bassline, chord: chord, nextChord: nextChord,
                              previousNote: previousBassNote, duration: rhythmValue, &rng)
                for item in bassline.reversed() {
                    if case let .note(pitch?, _) = item {
                        previousBassNote = pitch
                        break
                    }
                }
            } else {
                bassline.append(.note(nil, rhythmValue))
            }

            time += rhythmValue
            if endIndex <= index { break }
        }

        if !bassline.isEmpty {
            // A trailing "next" rule has no following note to merge into.
            if case let .next(_, pitch, duration) = bassline[bassline.count - 1] {
                bassline[bassline.count - 1] = .note(pitch, duration)
            }
            var part = SlotPart()
            var volume = 127          // Java: a running value across the whole section
            for item in bassline {
                switch item {
                case let .note(pitch, duration): part.add(pitch: pitch, duration: duration, volume: volume)
                case let .volume(v): volume = v
                case .next: break     // Java: silently skipped (assert false)
                }
            }
            part.makeSwing(swing)
            out.bass += part.render(from: startTime, channel: bassChannel).notes
        }
        return time
    }

    // MARK: no-style (Style.render's !hasStyle branch, Chord.render)

    /// Voicings already chosen for a chord (Java stores them on the Chord
    /// object, so a later chorus reuses them without a new random draw).
    /// Keyed by the chord's start slot.
    var noStyleVoicings: [Int: [Int]] = [:]

    /// A `(no-style)` section: every chord is sounded once, as its voicing plus
    /// the bass note in the octave of C2; no bass line and no drums.
    ///
    /// Java quirk (Q-03), reproduced: `Chord.render` is handed the running time
    /// in TICKS but computes the note-off as
    /// `min(endLimitIndex, time + rhythmValue) * ticksPerSlot`, i.e. it treats
    /// that tick count as slots. The result is also returned as the new time,
    /// so after the first chord the chords start late, last too long, and from
    /// the point where `time` passes the form's length they all pile up at
    /// `formSlots * 4` with zero length.
    private mutating func renderNoStyle(chordPart: ChordPart, startIndex: Int, endIndex: Int,
                                        time startTime: Int, rng: inout JavaRandom,
                                        into out: inout SectionRender) -> Int {
        let entries = chordPart.entries
        let endLimitIndex = chordPart.size            // Score.render(ppqn, transposition)
        var ticks = startTime * 4
        var i = entries.lastIndex { $0.start <= startIndex } ?? 0
        var next: ChordPart.Entry?
        var index = startIndex
        let base = cs.style.chordBase.map { Register.midi(ofNoteName: $0, fallback: 48) }

        while i < entries.count || next != nil {
            if next == nil {
                index = entries[i].start
                next = entries[i]
                i += 1
            }
            guard let current = next else { break }
            var rhythmValue = current.duration
            if startIndex > index { rhythmValue -= startIndex - index }
            if i < entries.count {
                index = entries[i].start
                next = entries[i]
                i += 1
            } else {
                next = nil
                index = chordPart.size
            }
            if endIndex <= index { rhythmValue -= index - endIndex }

            let offTicks = min(endLimitIndex, ticks + rhythmValue) * 4
            let chord = current.symbol
            if !chord.isNoChord, chord.form != nil {
                var voicing = noStyleVoicings[current.start]
                if voicing == nil {
                    voicing = findVoicing(form: chord.form, root: chord.root, lastChord: base, &rng)
                    noStyleVoicings[current.start] = voicing
                }
                if let voicing {
                    let bass = 36 + chord.bass.semitones       // Key.makeNote(bass, C2, 0)
                    for pitch in voicing + [bass] {
                        out.chords.append(ScheduledNote(pitch: max(0, min(127, pitch)), velocity: 127,
                                                        startTick: ticks / 4, duration: (offTicks - ticks) / 4,
                                                        channel: chordChannel))
                    }
                }
            }
            ticks = offTicks
            if endIndex <= index { break }
        }
        return ticks / 4
    }

    // MARK: Drums (Style.makeDrumline, DrumPattern.applyRules)

    private func makeDrumline(time start: Int, duration total: Int, _ rng: inout JavaRandom,
                              _ out: inout SectionRender) {
        var time = start
        var duration = total
        let durations = cs.drums.map(\.duration)
        let weights = cs.drums.map(\.weight)
        while duration > 0 {
            guard let choice = pickPattern(durations: durations, weights: weights, duration: duration, &rng)
            else { break }
            let pattern = cs.drums[choice]
            let patternDuration = durations[choice]
            duration -= patternDuration
            for drum in pattern.drums {
                var part = SlotPart()
                var volume = 127
                for element in drum.elements {
                    switch element.type {
                    case "X": part.add(pitch: drum.instrument, duration: Duration.slots(element.suffix), volume: volume)
                    case "R": part.add(pitch: nil, duration: Duration.slots(element.suffix))
                    case "V": volume = Int(element.suffix) ?? volume
                    default: break
                    }
                }
                part.makeSwing(swing)
                // An unknown drum name is -1 in Java, which is also its rest pitch.
                guard drum.instrument >= 0 else { continue }
                out.drums += part.render(from: time, channel: Constants.DRUM_CHANNEL).notes
            }
            if patternDuration <= 0 { break }
            time += patternDuration
        }
    }

    // MARK: Chords (Style.makeChordline, ChordPattern.applyRules)

    /// One entry of a voiced pattern: `nil` notes = nothing to play (Java null),
    /// otherwise the voicing (possibly empty for a rest) and the volume in
    /// force when it was created.
    private struct Voiced {
        var volume: Int?
        var notes: [Int]?
    }

    private mutating func makeChordline(time start: Int, chord: ChordSymbol, previousChord previous: [Int],
                                        duration total: Int, _ rng: inout JavaRandom,
                                        _ out: inout SectionRender) -> [Int] {
        var time = start
        var duration = total
        var previousChord = previous
        var beginning = true

        while duration > 0 {
            var voiced: [Voiced] = []
            var durationMelody = SlotPart()

            if let pattern = chordPattern(duration, &rng) {
                if beginning {
                    // "Pushing" the first chord: start early by the push amount.
                    var deltaT = pattern.push
                    time -= deltaT
                    if time < 0 {
                        time = 0
                        deltaT = 0
                    }
                    duration -= deltaT + pattern.duration
                } else {
                    duration -= pattern.duration
                }
                // ChordPattern.applyRules
                var lastChord = previousChord
                var volume = 127
                for rule in pattern.rules {
                    switch rule {
                    case let .strike(slots):
                        durationMelody.add(pitch: nil, duration: slots)
                        let voicing = findVoicing(form: chord.form, root: chord.root, lastChord: lastChord, &rng) ?? []
                        voiced.append(Voiced(volume: volume, notes: voicing))
                        lastChord = voicing
                    case let .rest(slots):
                        durationMelody.add(pitch: nil, duration: slots)
                        voiced.append(Voiced(volume: nil, notes: []))
                    case let .volume(v):
                        volume = v
                    case let .degree(degree, slots):
                        durationMelody.add(pitch: nil, duration: slots)
                        var voicing: [Int] = []
                        if let form = chord.form, let scale = form.firstScaleSpell, scale.count > 1 {
                            let rise = JavaPitch.rise(chord.root)
                            let tones = Array(scale.map { $0 + rise }.dropLast())
                            let note = Self.interval(degree, tones)
                            let root = PitchClass.forMidi(note)
                            voicing = findVoicing(form: form.noteForm?.form, root: root,
                                                  lastChord: lastChord, &rng) ?? []
                        }
                        voiced.append(Voiced(volume: volume, notes: voicing))
                        lastChord = voicing
                    }
                }
            } else {
                // No pattern: sound the chord once for the whole duration.
                if !beginning { break }
                let voicing = findVoicing(form: chord.form, root: chord.root, lastChord: previousChord, &rng)
                durationMelody.add(pitch: nil, duration: duration)
                duration = 0
                voiced.append(Voiced(volume: nil, notes: voicing))
            }

            durationMelody.makeSwing(swing)
            let units = durationMelody.units()
            var volume = 127
            for (n, entry) in voiced.enumerated() {
                guard n < units.count else { break }   // Java: iterator would throw
                let dur = units[n].duration
                let offTime = time + dur
                if let notes = entry.notes {
                    if let v = entry.volume { volume = v }
                    for pitch in notes {
                        out.chords.append(ScheduledNote(pitch: max(0, min(127, pitch)), velocity: volume,
                                                        startTick: time, duration: dur, channel: chordChannel))
                    }
                    previousChord = notes        // Java: a rest resets this to empty
                }
                time = offTime
            }
            beginning = false
        }
        return previousChord
    }

    // MARK: Voicings (ChordPattern.findVoicing …, ChordForm.getVoicings/generateVoicings)

    private typealias Candidate = (notes: [Int], ext: [Int])

    /// `ChordPattern.findVoicing`: voicing followed by its extension, in the
    /// vocabulary's note order (NOT sorted — placement keys on the first note).
    private func findVoicing(form: ChordForm?, root: PitchClass, lastChord: [Int],
                             _ rng: inout JavaRandom) -> [Int]? {
        guard let form else { return nil }
        let rise = JavaPitch.rise(root)
        let type = cs.style.voicingType
        // File order: addVoicing conses, and makeChordForm reverses at the end.
        var candidates: [Candidate] = form.voicings
            .filter { type.isEmpty || $0.type == type || type == "any" }
            .map { ($0.notes.map { $0 + rise }, $0.ext.map { $0 + rise }) }
        candidates = chooseVoicings(lastChord, candidates)
        if candidates.isEmpty {
            let generated = generateVoicings(form: form, root: root, rise: rise)
            if generated.isEmpty { return nil }
            let preferred = chooseVoicings(lastChord, generated)
            candidates = preferred.isEmpty ? generated : preferred
        }
        // BassPattern.getRandomItem: always draws, even for a single candidate.
        let pick = candidates[rng.nextInt(candidates.count)]
        return pick.notes + pick.ext
    }

    /// `ChordForm.generateVoicings`: permutations of the priority tones (root
    /// dropped, at most 5), each stacked upward.
    private func generateVoicings(form: ChordForm, root: PitchClass, rise: Int) -> [Candidate] {
        var spell = form.priorityNotes.map { $0 + rise }
        spell = JavaPitch.enhDrop(spell, root.semitones)
        spell = Array(spell.prefix(5))
        return Self.permutations(spell).map { perm in
            var voicing = [perm[0]]
            var last = perm[0]
            for var note in perm.dropFirst() {
                while note < last { note += 12 }
                last = note
                voicing.append(note)
            }
            return (voicing, [])
        }
    }

    /// `ChordForm.permutations`, in Java's order.
    static func permutations(_ list: [Int]) -> [[Int]] {
        if list.isEmpty { return [] }
        if list.count == 1 { return [list] }
        let first = list[0]
        let rest = permutations(Array(list.dropFirst()))
        var permutes: [[Int]] = []
        for sub in rest {
            for j in 0...sub.count {
                var new = sub
                new.insert(first, at: j)
                permutes.insert(new, at: 0)       // cons
            }
        }
        return permutes
    }

    /// `ChordPattern.chooseVoicings`. Java does not discard the candidates it
    /// accepted before finding a smaller leap; kept as is.
    private func chooseVoicings(_ lastChord: [Int], _ voicings: [Candidate]) -> [Candidate] {
        var good: [Candidate] = []
        var smallest = 127
        for voicing in voicings {
            guard let placed = placeVoicing(lastChord, voicing) else { continue }
            let all = placed.notes + placed.ext
            // One direction only: how far each note of the last chord is from
            // this voicing. (The symmetric half is commented out in Java.)
            let leap = Self.averageLeap(all, lastChord)
            if leap < smallest {
                smallest = leap
                good.append(placed)
            } else if leap == smallest {
                good.append(placed)
            }
        }
        return good
    }

    private func placeVoicing(_ lastChord: [Int], _ voicing: Candidate) -> Candidate? {
        guard let oldNote = voicing.notes.first,
              let placed = placeVoicing(lastChord, voicing.notes) else { return nil }
        let diff = placed[0] - oldNote
        return (placed, voicing.ext.map { $0 + diff })
    }

    private func placeVoicing(_ last: [Int], _ voicing: [Int]) -> [Int]? {
        let lastChord = last.isEmpty ? [cs.chordLow, cs.chordHigh] : last
        let lastNote = lastChord[0]
        let semitones = JavaPitch.semitonesAbove(lastNote, voicing[0])
        let difference = lastNote - voicing[0]
        var v = voicing
        if semitones >= 6 {
            // placeVoicingBelow
            if difference < 0 { v = v.map { $0 + 12 * (difference / 12 - 1) } }
            else if difference >= 12 { v = v.map { $0 + 12 * (difference / 12) } }
        } else {
            // placeVoicingAbove
            if difference > 0 { v = v.map { $0 + 12 * (difference / 12 + 1) } }
            else if difference <= -12 { v = v.map { $0 + 12 * (difference / 12) } }
        }
        while (v.min() ?? 0) < cs.chordLow {
            v = v.map { $0 + 12 }
            if (v.max() ?? 0) > cs.chordHigh { return nil }
        }
        while (v.max() ?? 0) > cs.chordHigh {
            v = v.map { $0 - 12 }
            if (v.min() ?? 0) < cs.chordLow { return nil }
        }
        return v
    }

    /// `(int)((double)sum / num)`: with no notes in `chord2` this is NaN → 0.
    private static func averageLeap(_ chord1: [Int], _ chord2: [Int]) -> Int {
        guard !chord2.isEmpty else { return 0 }
        let sum = chord2.reduce(0) { total, note in
            total + (chord1.map { abs($0 - note) }.min().map { min($0, 127) } ?? 127)
        }
        return Int(Double(sum) / Double(chord2.count))
    }

    // MARK: Bass (Style.addToBassline, BassPattern.applyRules)

    enum BassItem {
        /// A note (`nil` pitch = rest) and its duration.
        case note(Int?, Int)
        case volume(Int)
        /// Java's `(duration, NoteSymbol)` pair left by an `N` rule: the
        /// duration string, the next chord's bass, and that note's own duration.
        case next(String, Int, Int)
    }

    private func addToBassline(_ bassline: inout [BassItem], chord: ChordSymbol, nextChord: ChordSymbol,
                               previousNote previous: Int, duration total: Int, _ rng: inout JavaRandom) {
        var duration = total
        var previousNote = previous
        let durations = cs.bass.map(\.duration)
        let weights = cs.bass.map(\.weight)
        while duration > 0 {
            guard let choice = pickPattern(durations: durations, weights: weights, duration: duration, &rng)
            else { break }
            duration -= durations[choice]
            var segment = applyBassRules(cs.bass[choice], chord: chord,
                                         nextChord: duration > 0 ? chord : nextChord,
                                         lastNote: previousNote, &rng)
            for item in segment.reversed() {
                if case let .note(pitch?, _) = item {
                    previousNote = pitch
                    break
                }
            }
            // An `N` rule left hanging merges into the first note that follows:
            // its own pitch is dropped and its duration added to that note.
            if let last = bassline.last, case let .next(dur, _, _) = last,
               let first = segment.first, case let .note(pitch, noteDuration) = first {
                bassline.removeLast()
                segment[0] = .note(pitch, Duration.slots0(dur) + noteDuration)
            }
            bassline.append(contentsOf: segment)
            if durations[choice] <= 0 { break }
        }
    }

    private func applyBassRules(_ pattern: CompiledStyle.BassPattern, chord: ChordSymbol,
                                nextChord: ChordSymbol, lastNote last: Int,
                                _ rng: inout JavaRandom) -> [BassItem] {
        typealias C = CompiledStyle
        var segment: [BassItem] = []
        var lastNote = last
        guard let form = chord.form else { return segment }
        let rise = JavaPitch.rise(chord.root)
        let bassNote = Constants.CMIDI + chord.bass.semitones      // new NoteSymbol(pitchClass): octave 0
        let nextBass = Constants.CMIDI + nextChord.bass.semitones

        func randomItem(_ list: [Int]) -> Int? {
            guard !list.isEmpty else { return nil }                 // Java: nextInt(0) throws
            return list[rng.nextInt(list.count)]
        }
        func chordTone() -> Int? {
            var tones = form.spellNotes.map { $0 + rise }
            if tones.count > 1 { tones = JavaPitch.enhDrop(tones, lastNote) }
            return randomItem(tones)
        }
        /// The first scale, transposed to the chord, without its last note.
        func scaleTones() -> [Int]? {
            guard let scale = form.firstScaleSpell, !scale.isEmpty else { return nil }
            return Array(scale.map { $0 + rise }.dropLast())
        }

        for n in pattern.rules.indices {
            var rule = pattern.rules[n]
            let duration = pattern.durations[n]
            let modifier = pattern.modifiers[n]
            var pitch: Int?
            var isRest = false

            switch rule {
            case C.VOLUME:
                let v = Int(duration).map { max(0, min(127, $0)) } ?? 127
                segment.append(.volume(v))
                continue
            case C.PITCH, C.BASS:
                pitch = bassNote
            case C.NEXT:
                let hasNext = n + 1 < pattern.rules.count
                segment.append(.next(duration, nextBass, hasNext ? Constants.BEAT / 2 : Duration.slots0(duration)))
                return segment                                       // Java: the rest of the pattern is not applied
            case C.CHORD:
                pitch = chordTone()
            case C.SCALE:
                if let tones = scaleTones(), !tones.isEmpty {
                    var choices = Self.intervals(2, tones, lastNote) + Self.intervals(3, tones, lastNote)
                    if choices.count > 1 { choices = JavaPitch.enhDrop(choices, lastNote) }
                    pitch = randomItem(choices)
                } else {
                    pitch = chordTone()
                }
            case C.APPROACH:
                var approach = [nextBass + 1, nextBass - 1]
                approach = JavaPitch.enhDrop(approach, lastNote)
                pitch = randomItem(approach)
            case C.REST:
                isRest = true
            case C.EQUAL:
                pitch = lastNote
            default:
                if (rule > 0 && rule < 11) || rule > 99 {
                    if let tones = scaleTones(), !tones.isEmpty {
                        if rule > C.FLATTEN && rule < C.FLATTEN + 11 {
                            rule -= C.FLATTEN
                            pitch = Self.interval(rule, tones) - 1
                        } else if rule > C.SHARPEN && rule < C.SHARPEN + 11 {
                            rule -= C.SHARPEN
                            pitch = Self.interval(rule, tones) + 1
                        } else {
                            pitch = Self.interval(rule, tones)
                        }
                    } else {
                        pitch = chordTone()
                    }
                } else {
                    pitch = bassNote
                }
            }

            if isRest {
                segment.append(.note(nil, Duration.slots0(duration)))
                continue
            }
            guard var note = pitch else { continue }
            if rule != C.EQUAL {
                note -= 24
                switch modifier {
                case "U": note = Self.placeAbove(note, lastNote)
                case "D": note = Self.placeBelow(note, lastNote)
                case "DD": note = Self.placeBelow(note, lastNote) - 12
                default:
                    note = placeNear(note, lastNote, &rng)
                    note = pressure(note, &rng)
                }
            }
            segment.append(.note(note, Duration.slots0(duration)))
            lastNote = note
        }
        return segment
    }

    /// `BassPattern.getInterval`.
    static func interval(_ degree: Int, _ notes: [Int]) -> Int {
        var interval = degree
        if interval > 10 { interval -= 10 }
        interval = (interval % 11 - 1) % notes.count
        if interval < 0 { interval = 0 }
        return notes[interval]
    }

    /// `BassPattern.getIntervals`: the scale tones `interval` steps below and
    /// above the tone enharmonic to `root` (in that order).
    static func intervals(_ interval: Int, _ notes: [Int], _ root: Int) -> [Int] {
        let step = interval % 7 - 1
        let rootPos = notes.firstIndex { JavaPitch.enharmonic($0, root) } ?? -1
        let count = notes.count
        let above = ((rootPos + step) % count + count) % count
        let below = ((rootPos - step + count) % count + count) % count
        return [notes[below], notes[above]]
    }

    static func placeAbove(_ pitch: Int, _ base: Int) -> Int {
        base + JavaPitch.semitonesAbove(base, pitch)
    }

    static func placeBelow(_ pitch: Int, _ base: Int) -> Int {
        base - JavaPitch.semitonesAbove(pitch, base)
    }

    /// `BassPattern.placePitchNear`: move by octaves to within 11 semitones of
    /// the last note. Java draws a random number on every step although both
    /// outcomes do the same thing; the draw is kept for stream alignment.
    private func placeNear(_ p: Int, _ base: Int, _ rng: inout JavaRandom) -> Int {
        var pitch = p
        let margin = 11
        while pitch > base + margin || pitch < base - margin {
            _ = rng.nextDouble()
            if pitch > base + margin { pitch -= 12 }
            else if pitch < base - margin { pitch += 12 }
        }
        return pitch
    }

    /// `BassPattern.pressure`: beyond a soft margin around the register centre,
    /// drop or raise an octave with probability rising toward the hard limit.
    private func pressure(_ p: Int, _ rng: inout JavaRandom) -> Int {
        let low = cs.bassLow, high = cs.bassHigh
        let hardmargin = JavaPitch.semitonesAbove(high, low)
        let center = low + hardmargin
        let softHigh = center + 6, softLow = center - 6
        var pitch = p
        if pitch > softHigh {
            var prob = Double(pitch - softHigh) / Double(high - softHigh)
            prob = prob * prob * prob * prob
            if prob > rng.nextDouble() { pitch -= 12 }
        } else if pitch < softLow {
            var prob = Double(softLow - pitch) / Double(softLow - low)
            prob = prob * prob * prob * prob
            if prob > rng.nextDouble() { pitch += 12 }
        }
        return pitch
    }
}
