//
//  JavaGrammarExpander.swift
//  ImprovisorEngine
//
//  Stage 1 of solo generation, ported from the Java original:
//
//    imp/lickgen/Grammar.java     run, outerFill, accumulateTerminals,
//                                 applyRules, expandNonTerminal, findRule,
//                                 setVars, replace, evaluate, evaluateBuiltin
//    imp/lickgen/Terminals.java   isTerminal …, getDuration,
//                                 truncateAbstractMelody
//    polya/Arith.java             add/subtract/multiply/divide
//
//  It turns a grammar into an "abstract melody": a list of terminals such as
//  `C8`, `R4`, `(X 5 8)`, `(slope 1 3 C8 L8)`. Random choices come from a
//  `JavaRandom` in Java's order (one draw per rule choice), so for a given seed
//  the result is the list Java produces — checked against
//  Testing/goldens/solo by SoloGoldenTests.
//
//  Trading is not modelled: this is `Grammar.run` with `whetherToTrade` false.
//

import Foundation

struct JavaGrammarExpander {
    let forms: [Polylist]
    let chords: ChordPart
    /// The roadmap brick (dashed name) covering a slot, for `(builtin brick …)`
    /// conditions; `nil` when there is no roadmap.
    var brickName: (Int) -> String? = { _ in nil }

    private var startSymbol: String?
    private var cache = Polylist.empty
    private var terminals: [PolyValue] = []
    private var chordSlot = 0
    /// Java can loop forever on grammars that never produce a terminal
    /// (BUG_LOG Q-05); the port gives up instead.
    private var budget = 2_000_000

    init(grammar: Grammar, chords: ChordPart) {
        self.forms = grammar.forms
        self.chords = chords
    }

    // MARK: Grammar.run

    mutating func run(startSlot: Int, slots initialNumSlots: Int, rng: inout JavaRandom) -> [PolyValue] {
        chordSlot = startSlot
        terminals = []
        var numSlotsToFill = initialNumSlots
        while numSlotsToFill > 0 && budget > 0 {
            guard let stack = addStart(numSlotsToFill) else { break }
            numSlotsToFill = outerFill(stack, numSlotsToFill, &rng).slots
        }
        return Self.truncate(terminals, to: initialNumSlots)
    }

    private mutating func addStart(_ numSlots: Int) -> Polylist? {
        for form in forms {
            guard form.firstOrNil() == .symbol("startsymbol") else { continue }
            guard form.length == 2, case let .symbol(symbol) = form.second() else { return nil }
            startSymbol = symbol
            return Polylist.list(.list(Polylist.list(.symbol(symbol), .long(numSlots))))
        }
        return nil
    }

    private typealias Expansion = (stack: Polylist, slots: Int)

    private mutating func outerFill(_ start: Polylist, _ slots: Int, _ rng: inout JavaRandom) -> Expansion {
        let original = start
        var stack = start
        var numSlotsToFill = slots
        while numSlotsToFill > 0 && budget > 0 {
            budget -= 1
            if stack.isEmpty { stack = original }
            var r = accumulateTerminals(stack, numSlotsToFill)
            r = applyRules(r.stack, r.slots, &rng)
            stack = r.stack
            numSlotsToFill = r.slots
        }
        return (stack, numSlotsToFill)
    }

    private mutating func accumulateTerminal(_ terminal: PolyValue, _ slots: Int) -> Int {
        let duration = Self.duration(terminal)
        terminals.append(terminal)
        chordSlot += duration
        return slots - duration
    }

    private mutating func accumulateTerminals(_ start: Polylist, _ slots: Int) -> Expansion {
        var stack = start
        var numSlotsToFill = slots
        while numSlotsToFill > 0 && stack.nonEmpty {
            let token = stack.first()
            if !Self.isTerminal(token) { return (stack, numSlotsToFill) }
            if Self.isWrappedTerminal(token), case let .list(wrapped) = token {
                numSlotsToFill = accumulateTerminal(wrapped.first(), numSlotsToFill)
            } else {
                numSlotsToFill = accumulateTerminal(token, numSlotsToFill)
            }
            stack = stack.rest()
        }
        return (stack, numSlotsToFill)
    }

    private mutating func applyRules(_ start: Polylist, _ slots: Int, _ rng: inout JavaRandom) -> Expansion {
        if start.isEmpty { return (start, slots) }
        let first = start.first()
        let stack = start.rest()
        let token: Polylist
        if case let .list(list) = first { token = list } else { token = Polylist.list(first) }
        guard let result = expandNonTerminal(token, slots, &rng) else { return (stack, slots) }
        return (result.stack.append(stack), result.slots)
    }

    // MARK: Grammar.expandNonTerminal

    private mutating func expandNonTerminal(_ original: Polylist, _ slotsToFill: Int,
                                            _ rng: inout JavaRandom) -> Expansion? {
        var token = original
        var shareable = false
        var unshare = false
        let head = token.firstOrNil()?.symbolValue

        switch (token.length, head) {
        case (3, "fill"):
            token = token.rest()
            guard let beats = token.first().doubleValue else { return nil }
            let slots = Int(beats * Double(Constants.BEAT))
            let result = outerFill(token.rest(), slots, &rng)
            let stack = result.stack.cons(.list(Polylist.list(.symbol("unshareall"))))
            return (stack, slotsToFill - slots)
        case (3, "muse-switch"):
            return nil          // needs a Muse headset; not supported
        case (2, "unshare"), (2, "share"):
            unshare = head == "unshare"
            shareable = true
            token = token.rest()
            let find = token.first()
            if let found = cache.assoc(find) {
                if unshare { cache = Self.drop(cache, find) }
                return (found.rest(), slotsToFill)
            }
        case (1, "unshareall"):
            cache = .empty
            return (.empty, slotsToFill)
        default:
            break
        }

        guard let expansion = findRule(token, &rng) else { return nil }
        if shareable && !unshare {
            cache = cache.cons(.list(token.append(expansion)))
        }
        return (expansion, slotsToFill)
    }

    private static func drop(_ list: Polylist, _ find: PolyValue) -> Polylist {
        if list.isEmpty { return list }
        guard case let .list(first) = list.first() else { return list.rest() }
        if first.firstOrNil() == find { return list.rest() }
        return drop(list.rest(), find).cons(.list(first))
    }

    // MARK: Grammar.findRule

    /// Choose a rule for `token` by weight; returns its (substituted,
    /// evaluated) right-hand side. Draws exactly once when any rule applies.
    private mutating func findRule(_ token: Polylist, _ rng: inout JavaRandom) -> Polylist? {
        guard case let .symbol(name)? = token.firstOrNil() else { return nil }
        var candidates: [(rhs: Polylist, weight: Double)] = []

        for form in forms {
            guard form.firstOrNil() == .symbol("rule"), form.length == 4 else { continue }
            let rawLHS = form.second(), rawRHS = form.third()
            let lhs: Polylist, rawRhs: Polylist
            if case let .list(l) = rawLHS { lhs = l } else { lhs = Polylist.list(rawLHS) }
            if case let .list(r) = rawRHS { rawRhs = r } else { rawRhs = Polylist.list(rawRHS) }
            guard lhs.firstOrNil() == .symbol(name) else { continue }

            // Unify the rule's variables with the token's numbers.
            guard let unified = Self.setVars(values: token, variables: lhs, in: rawRhs) else { continue }
            guard case let .list(evaluated)? = evaluate(.list(unified)) else { continue }

            // Drop a recursive (startsymbol n) with n <= 0.
            var kept: [PolyValue] = []
            for element in evaluated {
                if case let .list(p) = element, p.length == 2, p.first() == .symbol(startSymbol ?? ""),
                   let n = p.second().numberAsInt, n <= 0 {
                    continue
                }
                kept.append(element)
            }
            // The weight expression is evaluated as written (no substitution).
            if let weight = evaluate(form.fourth())?.doubleValue, weight > 0 {
                candidates.append((Polylist.of(kept), weight))
            }
        }

        guard !candidates.isEmpty else { return nil }
        let total = candidates.reduce(0.0) { $0 + $1.weight }
        let rand = total * rng.nextDouble()
        var offset = 0.0
        for c in candidates {
            if rand >= offset && rand < offset + c.weight { return c.rhs }
            offset += c.weight
        }
        return candidates[candidates.count - 1].rhs
    }

    /// `Grammar.setVars`: one-way unification of the rule's parameters with the
    /// token's arguments; `nil` when they do not unify.
    private static func setVars(values: Polylist, variables: Polylist, in toSet: Polylist) -> Polylist? {
        var vars = variables.rest()
        var vals = values.rest()
        var result = toSet
        while vars.nonEmpty && vals.nonEmpty {
            let variable = vars.first(), value = vals.first()
            switch (variable, value) {
            case (.long, _) where value.isNumber, (.double, _) where value.isNumber:
                if variable.numberAsInt != value.numberAsInt { return nil }
            case let (.symbol(name), _) where value.isNumber:
                result = replace(name, .long(value.numberAsInt ?? 0), result)
            case let (.symbol(a), .symbol(b)):
                if a != b { return nil }
            default:
                return nil
            }
            vars = vars.rest()
            vals = vals.rest()
        }
        return result
    }

    private static func replace(_ name: String, _ value: PolyValue, _ list: Polylist) -> Polylist {
        Polylist.of(list.toArray().map { element in
            if case let .list(sub) = element { return .list(replace(name, value, sub)) }
            return element == .symbol(name) ? value : element
        })
    }

    // MARK: Grammar.evaluate

    private func evaluate(_ value: PolyValue) -> PolyValue? {
        switch value {
        case .long, .double, .symbol:
            return value
        case let .list(list):
            guard list.nonEmpty else { return nil }
            if case let .symbol(op) = list.first() {
                switch op {
                case "builtin":
                    return evaluateBuiltin(list.nthOrNil(1), list.nthOrNil(2))
                case "+", "-", "*", "/":
                    guard let a = list.nthOrNil(1).flatMap(evaluate), let b = list.nthOrNil(2).flatMap(evaluate),
                          a.isNumber, b.isNumber else { return nil }
                    return Self.arith(op, a, b)
                default:
                    break
                }
            }
            var out: [PolyValue] = []
            for element in list {
                // Java conses a null for an unevaluable element; skip it.
                if let v = evaluate(element) { out.append(v) }
            }
            return .list(Polylist.of(out))
        }
    }

    /// polya.Arith: integer arithmetic when both are Long, otherwise double.
    private static func arith(_ op: String, _ a: PolyValue, _ b: PolyValue) -> PolyValue? {
        if case let .long(x) = a, case let .long(y) = b {
            switch op {
            case "+": return .long(x + y)
            case "-": return .long(x - y)
            case "*": return .long(x * y)
            default: return y == 0 ? nil : .long(x / y)
            }
        }
        guard let x = a.doubleValue, let y = b.doubleValue else { return nil }
        switch op {
        case "+": return .double(x + y)
        case "-": return .double(x - y)
        case "*": return .double(x * y)
        default: return .double(x / y)
        }
    }

    /// `(builtin chord-family (f1 f2 …))` → 1 when the chord at the current
    /// slot is of one of the families; `(builtin brick NAME)` → 1 when the
    /// roadmap brick at the current slot has that name, else 0.1.
    private func evaluateBuiltin(_ arg1: PolyValue?, _ arg2: PolyValue?) -> PolyValue {
        if arg1 == .symbol("chord-family") {
            // Java returns Integer 0 here, which still fails the `weight > 0` test.
            guard case let .list(families)? = arg2 else { return .long(0) }
            guard let chord = chords.chord(at: chordSlot) else { return .double(0) }
            let family = chord.form?.family ?? "other"
            return .double(families.member(.symbol(family)) ? 1 : 0)
        }
        if arg1 == .symbol("brick") {
            guard case let .symbol(wanted)? = arg2 else { return .double(0) }
            guard let name = brickName(chordSlot) else { return .double(0) }
            return .double(name == wanted ? 1 : 0.1)
        }
        return .double(0)
    }

    // MARK: Terminals

    static func isAbstractNote(_ value: PolyValue) -> Bool {
        guard case let .symbol(s) = value, let first = s.first, "ACHLRSXY".contains(first) else { return false }
        return isDuration(String(s.dropFirst()))
    }

    static func isScaleDegree(_ value: PolyValue) -> Bool {
        guard case let .list(l) = value, l.length == 3, l.first() == .symbol("X") else { return false }
        func ok(_ v: PolyValue) -> Bool {
            switch v {
            case .long, .symbol: return true
            default: return false
            }
        }
        return ok(l.second()) && ok(l.third())
    }

    static func isSlope(_ value: PolyValue) -> Bool {
        guard case let .list(l) = value, l.length >= 4 else { return false }
        return l.first() == .symbol("slope")
    }

    static func isTriadic(_ value: PolyValue) -> Bool {
        guard case let .list(l) = value, l.length == 3 else { return false }
        return l.first() == .symbol("triadic")
    }

    static func isWrappedTerminal(_ value: PolyValue) -> Bool {
        guard case let .list(l) = value else { return false }
        if isScaleDegree(value) || isSlope(value) || isTriadic(value) { return false }
        guard l.nonEmpty else { return false }
        return isAbstractNote(l.first())
    }

    static func isTerminal(_ value: PolyValue) -> Bool {
        isAbstractNote(value) || isScaleDegree(value) || isSlope(value) || isTriadic(value)
            || isWrappedTerminal(value)
    }

    /// `Terminals.getDuration`.
    static func duration(_ value: PolyValue) -> Int {
        if case let .symbol(s) = value { return Duration.slots(String(s.dropFirst())) }
        guard case let .list(l) = value else { return 0 }
        if isScaleDegree(value) { return Duration.slots(l.third().description) }
        if isSlope(value) {
            return l.rest().rest().rest().toArray().reduce(0) { $0 + duration($1) }
        }
        if isTriadic(value) { return Duration.slots(l.second().description) }
        return 0
    }

    /// `Terminals.truncateAbstractMelody`: whole terminals up to the length.
    static func truncate(_ list: [PolyValue], to desired: Int) -> [PolyValue] {
        var out: [PolyValue] = []
        var total = 0
        for item in list {
            let d = duration(item)
            if total + d > desired { break }
            out.append(item)
            total += d
        }
        return out
    }

    /// `Duration.isDuration`: a well-formed, non-zero duration string.
    static func isDuration(_ item: String) -> Bool {
        let chars = Array(item)
        guard let first = chars.first, first.isASCII, first.isNumber else { return false }
        if let value = Int(item), value == 0 { return false }
        var index = 0
        var duration = 0
        var firsttime = true
        while index < chars.count && (chars[index] == "+" || firsttime || chars[index] == "u") {
            if firsttime { firsttime = false } else { index += 1 }
            var digits = ""
            while index < chars.count, chars[index].isASCII, chars[index].isNumber {
                digits.append(chars[index]); index += 1
            }
            let numerator = digits.isEmpty ? 8 : (Int(digits) ?? 8)
            var slots = Constants.WHOLE
            var denominator = 1
            if index < chars.count && chars[index] == "/" {
                index += 1
                guard index < chars.count, chars[index].isASCII, chars[index].isNumber else { return false }
                var tuplet = ""
                while index < chars.count, chars[index].isASCII, chars[index].isNumber {
                    tuplet.append(chars[index]); index += 1
                }
                denominator = Int(tuplet) ?? 1
            }
            if denominator > 1 { slots *= denominator - 1 }
            guard numerator * denominator != 0 else { return false }
            var this = slots / (numerator * denominator)
            var increment = this
            while index < chars.count && chars[index] == "." {
                increment /= 2
                this += increment
                index += 1
            }
            duration += this
        }
        return index >= chars.count && duration > 0
    }
}

private extension PolyValue {
    var isNumber: Bool {
        switch self {
        case .long, .double: return true
        default: return false
        }
    }

    /// Java `((Number) x).longValue()` / `intValue()`.
    var numberAsInt: Int? {
        switch self {
        case let .long(v): return v
        case let .double(v): return Int(v)
        default: return nil
        }
    }
}
