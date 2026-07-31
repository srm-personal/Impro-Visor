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
            guard case let .list(entry) = element,
                  case let .symbol(key) = entry.firstOrNil()
            else { continue }
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

        return style
    }

    /// Convenience: parse a `.sty` file from disk.
    public static func parse(contentsOf url: URL) throws -> Style {
        try parse(String(contentsOf: url, encoding: .utf8))
    }

    // MARK: Pattern parsing

    /// Parse `(bass-pattern (rules …) (weight w) [(push d)])` or the chord form.
    private static func parsePattern(_ entry: Polylist) -> Pattern? {
        let rules = tokens(of: entry.assoc("rules"))
        let weight = entry.assoc("weight")?.secondOrNil()?.doubleValue ?? 0
        let push = entry.assoc("push")?.secondOrNil()?.description
        guard !rules.isEmpty else { return nil }
        return Pattern(rules: rules, weight: weight, push: push)
    }

    /// Parse `(drum-pattern (drum Name hits…)… (weight w))`.
    private static func parseDrumPattern(_ entry: Polylist) -> DrumPattern? {
        var voices: [DrumVoice] = []
        var weight = 0.0
        for element in entry.rest() {
            guard case let .list(sub) = element,
                  case let .symbol(tag) = sub.firstOrNil()
            else { continue }
            switch tag {
            case "drum":
                let body = sub.rest()
                guard let name = body.firstOrNil()?.description else { continue }
                let hits = body.rest().map(\.description)
                voices.append(DrumVoice(name: name, hits: hits))
            case "weight":
                weight = sub.secondOrNil()?.doubleValue ?? 0
            default:
                break
            }
        }
        guard !voices.isEmpty else { return nil }
        return DrumPattern(voices: voices, weight: weight)
    }

    /// Tokens after the keyword of a `(rules …)`-style sub-list.
    private static func tokens(of list: Polylist?) -> [String] {
        guard let list else { return [] }
        return list.rest().map(\.description)
    }
}
