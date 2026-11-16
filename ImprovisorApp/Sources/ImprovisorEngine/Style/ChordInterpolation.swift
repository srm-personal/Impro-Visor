//
//  ChordInterpolation.swift
//  ImprovisorEngine
//
//  Port of the passing-chord interpolation and chord substitution a style can
//  ask for with `(interpolate …)`, `(interpolable …)` and `(substitute …)`:
//
//    imp/style/Style.java            createInterpolatedChordPart, mapPC, getPC,
//                                    getTargetAndRoot, choosePC, chooseMultiPC,
//                                    substituteChords, checkSubChords,
//                                    setSubChords
//    imp/style/Interpolate.java      willInterpolate
//    imp/style/stylePatterns/        Interpolant, Interpolable, Substitution
//    imp/data/PitchClass.java        transpose (the spelling tables), findRise
//
//  Before a section is rendered, Java rewrites the WHOLE chord progression:
//  each chord may get passing chords squeezed in before the next one, then runs
//  of chords may be replaced by substitutes. All of it is random and drawn from
//  the same stream as the rest of the accompaniment.
//
//  Several things here look like mistakes in Java and are reproduced as they
//  are (see "Java:" notes), because the goal is identical output.
//

import Foundation

struct InterpolationRules {
    struct Interpolant {
        var chords: [String] = []
        var divideCount = 0
        var weight: Float = 0
        var minSlots = 0
    }

    struct Substitution {
        var originals: [String] = []
        var subs: [String] = []
        var weight: Float = 0
        var minSlots = 0
    }

    /// In Java's list order: each definition is consed on, so the LAST one in
    /// the file comes first.
    var interpolants: [Interpolant] = []
    var substitutions: [Substitution] = []
    /// `interpolables.first().getPROBABILITY()`.
    var probability: Float?

    var isEmpty: Bool { interpolants.isEmpty && substitutions.isEmpty }

    init(style: Style) {
        func strings(_ list: Polylist?) -> [String] {
            guard let list, case let .list(inner)? = list.secondOrNil() else { return [] }
            return inner.toArray().map(\.description)
        }
        func number(_ list: Polylist?) -> Float? {
            list?.secondOrNil()?.doubleValue.map { Float($0) }
        }
        func slots(_ list: Polylist?) -> Int? {
            list?.secondOrNil().map { Duration.slots($0.description) }
        }
        for body in style.interpolations.reversed() {
            var i = Interpolant()
            i.chords = strings(body.assoc("chords"))
            i.divideCount = strings(body.assoc("division")).count
            i.weight = number(body.assoc("weight")) ?? 0
            i.minSlots = slots(body.assoc("min-duration")) ?? 0
            interpolants.append(i)
        }
        for body in style.substitutions.reversed() {
            var s = Substitution()
            s.originals = strings(body.assoc("from"))
            s.subs = strings(body.assoc("to"))
            s.weight = number(body.assoc("weight")) ?? 0
            s.minSlots = slots(body.assoc("min-duration")) ?? 0
            substitutions.append(s)
        }
        if let last = style.interpolables.last { probability = number(last.assoc("weight")) ?? 0 }
    }
}

/// `PitchClass.transpose` and `findRise`, which pick enharmonic SPELLINGS
/// (the spelling decides whether a chord's tones are later transposed up or
/// down from C).
enum JavaPitchClass {
    /// PitchClass.java index order (a line of fifths).
    static let names = ["fb", "cb", "gb", "db", "ab", "eb", "bb", "f", "c", "g", "d", "a", "e", "b",
                        "f#", "c#", "g#", "d#", "a#", "e#", "b#"]
    private static let fb = 0, cb = 1, gb = 2, db = 3, ab = 4, eb = 5, bb = 6, f = 7, c = 8, g = 9, d = 10
    private static let a = 11, e = 12, b = 13, fs = 14, cs = 15, gs = 16, ds = 17, `as` = 18, es = 19, bs = 20

    private static let up: [[Int]] = [
        [fb, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs],
        [f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g, d, a, e, b, fs, cs],
        [fs, cs, gs, ds, `as`, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g, d],
        [g, d, a, e, b, fs, cs, gs, ds, `as`, f, c, g, d, a, e, b, fs, cs, gs, ds],
        [gs, ds, `as`, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g, d, a, e],
        [a, e, b, fs, cs, gs, ds, `as`, es, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es],
        [`as`, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g, d, a, e, b, fs],
        [b, fs, cs, gs, ds, `as`, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g],
        [c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g, d, a, e, b, fs, cs, gs],
        [cs, gs, ds, `as`, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g, d, a],
        [d, a, e, b, fs, cs, gs, ds, `as`, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`],
        [ds, `as`, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs, g, d, a, e, b],
    ]

    private static let down: [[Int]] = [
        [fb, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, fs, cs, gs, ds, `as`, es, bs],
        [eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb, bb, f, c, g, d, a, e, b],
        [d, a, fb, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb, bb],
        [db, ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb, bb, f, c, g, d, a],
        [c, g, d, a, fb, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab],
        [cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb, bb, f, c, g],
        [bb, f, c, g, d, a, e, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb],
        [a, fb, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb, bb, f],
        [ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb, bb, f, c, g, d, a, f],
        [g, d, a, fb, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb],
        [gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb, db, ab, eb, bb, f, c, g, d],
        [f, c, g, d, a, fb, cb, gb, db, ab, eb, bb, f, c, g, d, a, e, b, gb, db],
    ]

    /// `PitchClass.transpose(semitones)`, by name.
    static func transpose(_ name: String, _ semitones: Int) -> String {
        guard let index = names.firstIndex(of: name) else { return name }
        if semitones >= 0 {
            let s = semitones % 12
            return s == 0 ? name : names[up[s][index]]
        }
        let s = (-semitones) % 12
        return s == 0 ? name : names[down[s][index]]
    }

    /// `PitchClass.findRise(from, to)`.
    static func findRise(_ from: PitchClass, _ to: PitchClass) -> Int {
        var rise = to.semitones - from.semitones
        if rise < 0 { rise = 12 - ((-rise) % 12) }
        // Negative for targets that prefer flats, so spellings come out flat.
        if rise > 0 && !JavaPitch.prefersSharps(to) { rise = -(12 - rise) }
        return rise
    }
}

/// The rewrite itself. Chords are reference objects because Java mutates the
/// durations of the bounding chords while it walks the progression.
struct ChordInterpolator {
    final class IChord {
        var name: String
        var symbol: ChordSymbol?
        var rhythmValue: Int
        init(name: String, symbol: ChordSymbol?, rhythmValue: Int) {
            self.name = name
            self.symbol = symbol
            self.rhythmValue = rhythmValue
        }
    }

    let rules: InterpolationRules
    let vocabulary: Vocabulary

    /// Java `Chord.DEFAULT_RHYTHM_VALUE` is irrelevant here: every chord made
    /// below has its duration set before use.
    private func chord(_ name: String) -> IChord {
        let symbol = ChordSymbol.isRecognized(name, vocabulary: vocabulary)
            ? ChordSymbol.parse(name, vocabulary: vocabulary) : nil
        return IChord(name: name, symbol: symbol, rhythmValue: Constants.BEAT)
    }

    private func family(_ c: IChord) -> String { c.symbol?.form?.family ?? "other" }
    private func root(_ c: IChord) -> PitchClass { c.symbol?.root ?? PitchClass.named("c")! }

    /// `ChordSymbol.getQuality`: the name without its root and slash bass.
    private func quality(_ c: IChord) -> String {
        var q = Substring(c.name)
        let chars = Array(c.name)
        q = chars.count > 1 && (chars[1] == "b" || chars[1] == "#") ? q.dropFirst(2) : q.dropFirst(1)
        if let slash = q.firstIndex(of: "/") { q = q[..<slash] }
        return String(q)
    }

    private func capitalize(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// `Chord.transpose` → `ChordSymbol.transpose`: respell root and bass.
    private func transpose(_ c: IChord, _ semitones: Int) {
        guard let symbol = c.symbol, !symbol.isNoChord else { return }
        let newRoot = JavaPitchClass.transpose(symbol.root.name, semitones)
        let newBass = JavaPitchClass.transpose(symbol.bass.name, semitones)
        // The name is built from each pitch class's chord base (a# → Bb,
        // cb → B, fb → E …), which is PitchClass.spelling here.
        func base(_ n: String) -> String { PitchClass.named(n)?.spelling ?? capitalize(n) }
        var name = base(newRoot) + symbol.type
        if newBass != newRoot { name += "/" + base(newBass) }
        c.name = name
        c.symbol = ChordSymbol.parse(name, vocabulary: vocabulary)
    }

    // MARK: createInterpolatedChordPart

    func apply(to part: ChordPart, rng: inout JavaRandom) -> ChordPart {
        guard !rules.isEmpty, let probability = rules.probability, !part.entries.isEmpty else { return part }
        let minVal = rules.interpolants.first?.minSlots ?? rules.substitutions.first?.minSlots ?? 0
        guard minVal > 0 else { return part }

        // Interpolate.willInterpolate: one draw per chord.
        let chords = part.entries.map { IChord(name: $0.symbol.name, symbol: $0.symbol, rhythmValue: $0.duration) }
        var actions: [Bool] = []
        for (i, c) in chords.enumerated() {
            let steps = c.rhythmValue <= minVal ? 0 : c.rhythmValue / minVal - 1
            let draw = Int(rng.nextDouble() * 100 + 1)
            let hasNext = i + 1 < chords.count
            actions.append(!((Float(draw) > probability * 100 || steps == 0) && hasNext))
        }

        // mapPC + prepProgList: walk the pairs; a pair may grow passing chords.
        var progression: [IChord] = []
        var left = chords[0]
        var leftAction = actions[0]
        var index = 1
        while index < chords.count {
            let right = chords[index]
            if leftAction {
                var result = passingChords(right: right, left: left, &rng)
                let newRight = result.removeLast()
                progression += result
                left = newRight
            } else {
                progression.append(left)
                left = right
            }
            leftAction = actions[index]
            index += 1
        }
        progression.append(left)

        // substituteChords + extractSub.
        progression = substitute(progression[...], &rng)

        if ProcessInfo.processInfo.environment["IMPRO_TRACE"] != nil {
            FileHandle.standardError.write(("POST " + progression.map { "\($0.name)/\($0.rhythmValue)" }.joined(separator: " ") + "\n").data(using: .utf8)!)
        }
        var out = ChordPart(info: part.info)
        let noChord = ChordSymbol.parse(ChordSymbol.noChordName, vocabulary: vocabulary)!
        for c in progression where c.rhythmValue > 0 {
            out.append(ChordSymbol.isRecognized(c.name, vocabulary: vocabulary)
                       ? (ChordSymbol.parse(c.name, vocabulary: vocabulary) ?? noChord) : noChord,
                       duration: c.rhythmValue)
        }
        return out
    }

    // MARK: getPC / getTargetAndRoot

    private func targetAndRoot(_ target: String) -> (quality: String, root: PitchClass) {
        let c = chord(target)
        let r = root(c)
        switch family(c) {
        case "major", "augmented": return ("", r)
        case "minor", "minor7", "half-diminished": return ("m", r)
        case "dominant":
            let q = quality(c)
            return (q.contains("+") || q.contains("#") || q.contains("b9") || q.contains("alt") ? "7+" : "7", r)
        default: return ("7", r)
        }
    }

    /// The chords to play from `left` up to and including `right`.
    private func passingChords(right c: IChord, left prev: IChord, _ rng: inout JavaRandom) -> [IChord] {
        if rules.interpolants.isEmpty { return [prev, c] }
        var candidates: [InterpolationRules.Interpolant] = []
        var sum = 0.0
        // Java: declared outside the loop, so after the loop it holds the root
        // of the LAST interpolant examined — not of the one that gets chosen.
        var rootName = PitchClass.named("c")!
        var rootSet = false

        for interpolant in rules.interpolants {
            guard let first = interpolant.chords.first, let last = interpolant.chords.last else { continue }
            var targetRight = ""
            var targetLeft: String?
            var rootLeft: PitchClass?
            var targetsDistance = 0

            if first == "_" || last == "_" {
                if first == "_" {
                    let r = targetAndRoot(last)
                    targetRight = r.quality; rootName = r.root; rootSet = true
                }
                if last == "_" {
                    let r = targetAndRoot(first)
                    targetRight = r.quality; rootName = r.root; rootSet = true
                }
            } else {
                let l = targetAndRoot(first), r = targetAndRoot(last)
                targetRight = r.quality
                targetLeft = l.quality
                rootLeft = l.root
                rootName = r.root; rootSet = true
                targetsDistance = JavaPitchClass.findRise(l.root, r.root)
            }

            /// Both ends named: the previous chord must be of the left end's
            /// family and the same distance from the target.
            func leftMatches() -> Bool {
                guard let rootLeft, let targetLeft else { return false }
                let leftChord = chord(rootLeft.name.uppercased() + targetLeft)
                return family(prev) == family(leftChord)
                    && targetsDistance == JavaPitchClass.findRise(root(prev), root(c))
            }

            var matched = false
            switch family(c) {
            case "augmented", "major":
                // Java: with both ends named, the left end is NOT checked here.
                matched = targetRight == ""
            case "half-diminished", "minor7", "minor":
                matched = targetRight == "m" && (rootLeft == nil || leftMatches())
            case "sus4", "dominant":
                matched = (targetRight == "7" || targetRight == "7+") && (rootLeft == nil || leftMatches())
            default:
                break
            }
            if matched {
                candidates.insert(interpolant, at: 0)      // cons
                sum += Double(interpolant.weight)
            }
        }
        guard !candidates.isEmpty else { return [prev, c] }
        let transposition = rootSet ? JavaPitchClass.findRise(rootName, root(c)) : 0
        return choose(candidates, left: prev, right: c, sum: sum, transposition: transposition, &rng)
    }

    // MARK: choosePC / chooseMultiPC

    private func choose(_ list: [InterpolationRules.Interpolant], left: IChord, right: IChord,
                        sum: Double, transposition: Int, _ rng: inout JavaRandom) -> [IChord] {
        let random = rng.nextDouble()
        var weights = 0.0
        var chosen = list[0]
        for candidate in list {
            weights += Int(sum) == 1 ? Double(candidate.weight) : Double(candidate.weight / 2)
            if random < weights {
                chosen = candidate
                break
            }
        }
        let first = chosen.chords.first ?? "", last = chosen.chords.last ?? ""
        let middle = Array(chosen.chords.dropFirst().dropLast())

        if (first == "_" || last == "_") && middle.count == 1 {
            let pc = chord(middle[0])
            transpose(pc, transposition)
            if first == "_" {
                let dividor = chosen.divideCount - 2
                guard dividor > 0, left.rhythmValue / dividor >= chosen.minSlots else { return [left, right] }
                let rv = left.rhythmValue / dividor
                left.rhythmValue -= rv
                pc.rhythmValue = rv
            } else {
                guard right.rhythmValue / 2 >= chosen.minSlots else { return [left, right] }
                let rv = right.rhythmValue / 2
                right.rhythmValue = rv
                pc.rhythmValue = rv
            }
            return [left, pc, right]
        }

        func inserted(_ rv: Int) -> [IChord] {
            middle.map { name in
                let pc = chord(name)
                pc.rhythmValue = rv
                transpose(pc, transposition)
                return pc
            }
        }
        let parts = 1 + middle.count
        if first == "_" {
            guard left.rhythmValue % parts == 0, left.rhythmValue / parts >= chosen.minSlots else { return [left, right] }
            let rv = left.rhythmValue / parts
            left.rhythmValue = rv
            return [left] + inserted(rv) + [right]
        }
        if last == "_" {
            guard right.rhythmValue % parts == 0, right.rhythmValue / parts >= chosen.minSlots else { return [left, right] }
            let rv = right.rhythmValue / parts
            right.rhythmValue = rv
            return [left] + inserted(rv) + [right]
        }
        let total = right.rhythmValue + left.rhythmValue
        let count = middle.count + 2
        guard total % count == 0, total / count >= chosen.minSlots else { return [left, right] }
        let rv = total / count
        left.rhythmValue = rv
        let mid = inserted(rv)
        right.rhythmValue = rv
        return [left] + mid + [right]
    }

    // MARK: substituteChords

    private func substitute(_ original: ArraySlice<IChord>, _ rng: inout JavaRandom) -> [IChord] {
        var out: [IChord] = []
        var rest = original
        outer: while let first = rest.first {
            for sub in rules.substitutions {
                guard let str = sub.originals.first else { continue }
                if !str.contains("_") {
                    let subchord = chord(str)
                    if quality(subchord) != quality(first) { continue }
                    let random = Int(rng.nextDouble() * 100 + 1)
                    if random > Int(sub.weight * 100) { continue }
                    let length = sub.originals.count
                    let cut = Array(rest.prefix(length))
                    // checkSubChords: every later chord must have the quality
                    // the rule names at that position.
                    var matched = 1
                    for (k, c) in cut.dropFirst().enumerated() {
                        if quality(chord(sub.originals[k + 1])) == quality(c) { matched += 1 } else { break }
                    }
                    if matched != length { continue }
                    let transposition = JavaPitchClass.findRise(root(subchord), root(first))
                    out += setSubChords(cut, sub, transposition)
                    rest = rest.dropFirst(length)
                    continue outer
                } else {
                    let random = Int(rng.nextDouble() * 100 + 1)
                    if random > Int(sub.weight * 100) { continue }
                    // "substitutions from vocabulary": the chord form's own list.
                    let possible = first.symbol?.form?.substitutions ?? []
                    if !possible.isEmpty {
                        // Java: the substitute is used as written in the
                        // vocabulary (C-rooted) — it is not transposed.
                        let n = chord(possible[rng.nextInt(possible.count)])
                        n.rhythmValue = first.rhythmValue
                        out.append(n)
                        rest = rest.dropFirst()
                        continue outer
                    }
                }
            }
            out.append(first)
            rest = rest.dropFirst()
        }
        return out
    }

    private func setSubChords(_ cut: [IChord], _ sub: InterpolationRules.Substitution,
                              _ transposition: Int) -> [IChord] {
        guard !sub.subs.isEmpty, sub.minSlots > 0 else { return cut }
        let total = cut.reduce(0) { $0 + $1.rhythmValue }
        let rv = total / sub.subs.count
        // No triplet-ish values, nothing shorter than the minimum.
        if rv < sub.minSlots || rv % 120 != 0 || (rv * (480 / sub.minSlots)) % 480 != 0 { return cut }
        return sub.subs.map { name in
            let c = chord(name)
            c.rhythmValue = rv
            transpose(c, transposition)
            return c
        }
    }
}
