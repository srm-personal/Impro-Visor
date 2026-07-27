//
//  GrammarParser.swift
//  ImprovisorEngine
//
//  Parses a `.grammar` file into a `Grammar`. Ports the loading side of
//  imp/lickgen/Grammar. Top-level forms are `(parameter (name value))`,
//  `(startsymbol S)`, and `(rule lhs rhs [builtin…] weight)`.
//

import Foundation

public enum GrammarParser {

    /// Parse grammar text into a `Grammar`.
    public static func parse(_ content: String) -> Grammar {
        var grammar = Grammar()

        for form in PolyaParser.parseAll(content) {
            guard case let .list(list) = form,
                  case let .symbol(head) = list.firstOrNil()
            else { continue }

            switch head {
            case "parameter":
                // (parameter (name value))
                if case let .list(pair)? = list.secondOrNil(),
                   case let .symbol(name) = pair.firstOrNil(),
                   let value = pair.secondOrNil() {
                    grammar.parameters[name] = value
                }
            case "startsymbol":
                if let s = list.secondOrNil()?.symbolValue { grammar.startSymbol = s }
            case "rule":
                if let rule = parseRule(list) { grammar.rules.append(rule) }
            default:
                break
            }
        }

        return grammar
    }

    /// Convenience: parse a `.grammar` file from disk.
    public static func parse(contentsOf url: URL) throws -> Grammar {
        try parse(String(contentsOf: url, encoding: .utf8))
    }

    /// Parse `(rule lhs rhs [extra…] weight)`. lhs and rhs are the 2nd and 3rd
    /// elements; the weight is the trailing number; anything between rhs and the
    /// weight (e.g. `(builtin brick …)`) is preserved only in `raw`.
    private static func parseRule(_ list: Polylist) -> GrammarRule? {
        let elements = list.rest().toArray() // drop the "rule" keyword
        guard elements.count >= 3,
              case let .list(lhs) = elements[0],
              case let .list(rhs) = elements[1],
              let weight = elements.last?.doubleValue
        else { return nil }
        return GrammarRule(lhs: lhs, rhs: rhs, weight: weight, raw: list)
    }
}
