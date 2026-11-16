//
//  StyleParser.swift
//  ImprovisorEngine
//
//  Parses a `.sty` style file into a `Style`. Ports the loading side of
//  imp/style/Style. A style file is a single `(style …)` S-expression whose
//  entries are scalar settings plus repeated `(bass-pattern …)`,
//  `(chord-pattern …)`, and `(drum-pattern …)` forms.
//

import Foundation

public enum StyleParser {

    public enum ParseError: Error, CustomStringConvertible {
        case notAStyle
        public var description: String { "file is not a (style …) form" }
    }

    /// Parse style text into a `Style`.
    public static func parse(_ content: String) throws -> Style {
        guard case let .list(top)? = PolyaParser.parse(content),
              top.firstOrNil() == .symbol("style")
        else { throw ParseError.notAStyle }

        var style = Style()
        for element in top.rest() {
            apply(element, to: &style)
        }
        return style
    }

    /// Apply one `(key value…)` style entry to `style`. Shared by file parsing
    /// and by leadsheet-embedded overrides (`Style.applying(override:)`).
    static func apply(_ element: PolyValue, to style: inout Style) {
        guard case let .list(entry) = element,
              case let .symbol(key) = entry.firstOrNil()
        else { return }
        let rest = entry.rest()

        switch key {
        case "name": style.name = rest.firstOrNil()?.description ?? ""
        case "swing": style.swing = rest.firstOrNil()?.doubleValue ?? style.swing
        case "comp-swing": style.compSwing = rest.firstOrNil()?.doubleValue ?? style.compSwing
        case "voicing-type": style.voicingType = rest.firstOrNil()?.description ?? style.voicingType
        case "voicing-name": style.voicingFileName = rest.firstOrNil()?.description ?? style.voicingFileName
        case "bass-high": style.bassHigh = rest.firstOrNil()?.description ?? style.bassHigh
        case "bass-low": style.bassLow = rest.firstOrNil()?.description ?? style.bassLow
        case "bass-base": style.bassBase = rest.firstOrNil()?.description ?? style.bassBase
        case "chord-high": style.chordHigh = rest.firstOrNil()?.description ?? style.chordHigh
        case "chord-low": style.chordLow = rest.firstOrNil()?.description ?? style.chordLow
        case "bass-pattern":
            if let p = parsePattern(entry) { style.bassPatterns.append(p) }
        case "chord-pattern":
            if let p = parsePattern(entry) { style.chordPatterns.append(p) }
        case "drum-pattern":
            if let p = parseDrumPattern(entry) { style.drumPatterns.append(p) }
        default:
            break
        }
    }

    /// Convenience: parse a `.sty` file from disk.
    public static func parse(contentsOf url: URL) throws -> Style {
        try parse(String(contentsOf: url, encoding: .utf8))
    }

    // MARK: Pattern parsing
    //
    // These follow the Java parsers segment by segment, including where they
    // stop: BassPattern.makePattern and ChordPattern.makePattern return as soon
    // as they meet something they do not recognize, so anything after it in the
    // pattern — more rules, or the weight — is not read and keeps its default.

    /// Java `Pattern.weight` default.
    static let defaultWeight = 10.0

    /// Whether the entry is a bass pattern (as opposed to a chord pattern).
    private static func isBass(_ entry: Polylist) -> Bool {
        entry.firstOrNil() == .symbol("bass-pattern")
    }

    /// Parse `(bass-pattern (rules …) (weight w))` or
    /// `(chord-pattern (rules …) (weight w) (push d))`. A rule is either a word
    /// (`B4`, `X8`, `V90`) or a list `(X degree duration [modifier])`, which is
    /// kept as its text (`"(X 5 8 U)"`).
    private static func parsePattern(_ entry: Polylist) -> Pattern? {
        let bass = isBass(entry)
        var rules: [String] = []
        var weight = defaultWeight
        var push: String?

        segments: for segment in entry.rest() {
            guard case let .list(item) = segment, item.nonEmpty,
                  case let .symbol(keyword) = item.firstOrNil() else {
                break segments          // Java: setError and return
            }
            let body = item.rest()
            switch keyword {
            case "name":
                continue
            case "rules":
                for rule in body {
                    switch rule {
                    case let .list(plist):
                        let parts = plist.toArray()
                        guard parts.count >= 3, parts[0] == .symbol("X") else { break segments }
                        rules.append(plist.description)
                    case let .symbol(word):
                        guard let letter = word.first else { break segments }
                        if bass {
                            if word == "U" || word == "D" { rules.append(word); continue }
                            guard "ABCNRSVX=".contains(letter) else { break segments }
                        } else {
                            guard "XRV".contains(letter) else { break segments }
                        }
                        rules.append(word)
                    default:
                        break segments  // a bare number is not a rule in Java
                    }
                }
            case "weight":
                guard let w = body.firstOrNil()?.doubleValue else {
                    if bass { break segments } else { continue }
                }
                // ChordPattern stores `w.intValue()`; BassPattern `w.floatValue()`.
                weight = bass ? Double(Float(w)) : Double(Int(w))
            case "push":
                guard !bass else { break segments }
                if let p = body.firstOrNil() { push = p.description }
            default:
                // `use` (rule definitions) is accepted by Java but no shipped
                // style has any; anything else ends the pattern.
                break segments
            }
        }
        return Pattern(rules: rules, weight: weight, push: push)
    }

    /// Parse `(drum-pattern (drum Name hits…)… (weight w))`. Each drum may list
    /// its hits bare (`X8 X8`) or inside `(rules X8 X8)`, optionally with a
    /// `(name …)`. A second rule for the same instrument REPLACES the first
    /// (Java `DrumPattern.addRule`).
    private static func parseDrumPattern(_ entry: Polylist) -> DrumPattern? {
        var voices: [DrumVoice] = []
        var weight = defaultWeight
        for element in entry.rest() {
            guard case let .list(sub) = element,
                  case let .symbol(tag) = sub.firstOrNil()
            else { continue }
            switch tag {
            case "drum":
                let body = sub.rest()
                guard let name = body.firstOrNil()?.description else { continue }
                var hits: [String] = []
                for item in body.rest() {
                    switch item {
                    case let .symbol(word):
                        hits.append(word)
                    case let .list(inner):
                        if inner.firstOrNil() == .symbol("rules") {
                            for hit in inner.rest() {
                                if case let .symbol(word) = hit { hits.append(word) }
                            }
                        }
                    default:
                        break
                    }
                }
                let number = DrumBank.number(for: name)
                voices.removeAll { DrumBank.number(for: $0.name) == number }
                voices.append(DrumVoice(name: name, hits: hits))
            case "weight":
                if let w = sub.secondOrNil()?.doubleValue { weight = Double(Float(w)) }
            default:
                break
            }
        }
        return DrumPattern(voices: voices, weight: weight)
    }
}
