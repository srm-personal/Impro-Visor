//
//  Grammar.swift
//  ImprovisorEngine
//
//  The data model for a solo-generation grammar, loaded from a `.grammar` file.
//  Ports the storage side of imp/lickgen/Grammar. A grammar is a set of
//  `(parameter (name value))` settings, a `(startsymbol S)`, and weighted
//  production `(rule lhs rhs [builtin…] weight)` forms. Rule *expansion* is the
//  job of the solo generator (Step 5); this type just holds the rules.
//

import Foundation

/// One weighted production rule.
public struct GrammarRule: Equatable, Sendable {
    /// Left-hand side, e.g. `(P Y)` or `(BRICK 960)`.
    public let lhs: Polylist
    /// Right-hand side: the list of symbols this rule expands to.
    public let rhs: Polylist
    /// Selection weight.
    public let weight: Double
    /// The complete original `(rule …)` form (retains any `builtin` tag).
    public let raw: Polylist

    /// The non-terminal name on the left, e.g. `P`, `BRICK`.
    public var head: String? { lhs.firstOrNil()?.symbolValue }
}

/// A solo-generation grammar.
public struct Grammar: Equatable, Sendable {
    /// Parameters keyed by name (values may be numbers, booleans, or symbols).
    public var parameters: [String: PolyValue]
    /// The start symbol (default `P`).
    public var startSymbol: String
    /// The production rules, in file order.
    public var rules: [GrammarRule]

    public init(parameters: [String: PolyValue] = [:],
                startSymbol: String = "P",
                rules: [GrammarRule] = []) {
        self.parameters = parameters
        self.startSymbol = startSymbol
        self.rules = rules
    }

    // MARK: Typed parameter access

    /// A numeric parameter (e.g. `chord-tone-weight`, `min-pitch`).
    public func number(_ name: String) -> Double? {
        parameters[name]?.doubleValue
    }

    /// An integer parameter.
    public func int(_ name: String) -> Int? {
        parameters[name]?.intValue
    }

    /// A boolean parameter (`true`/`false` symbols).
    public func bool(_ name: String) -> Bool? {
        guard case let .symbol(s)? = parameters[name] else { return nil }
        return s == "true" ? true : (s == "false" ? false : nil)
    }

    /// A symbol/string parameter (e.g. `scale-type`, `scale-root`).
    public func string(_ name: String) -> String? {
        parameters[name]?.description
    }

    /// Rules whose left-hand non-terminal is `head`.
    public func rules(for head: String) -> [GrammarRule] {
        rules.filter { $0.head == head }
    }
}
