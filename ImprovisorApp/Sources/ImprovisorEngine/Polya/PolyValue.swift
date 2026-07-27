//
//  PolyValue.swift
//  ImprovisorEngine
//
//  A single element of a Polylist. In the original Java `polya` library the
//  elements of a `Polylist` are untyped `Object`s that are, in practice, always
//  one of four things: a `String` (symbol/word), a `Long`, a `Double`, or a
//  nested `Polylist`. Modelling that as a Swift enum keeps the tokenizer output
//  type-safe while preserving the Java structure the higher-level engines walk.
//

import Foundation

/// One element of an S-expression: a symbol, an integer, a floating-point
/// number, or a nested list. Mirrors the four concrete `Object` types the Java
/// `polya.Tokenizer` produces (`String`, `Long`, `Double`, `Polylist`).
public enum PolyValue: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// A word token — chord names, rule letters, style keywords, `|`, `,`, etc.
    case symbol(String)
    /// An integer token (Java `Long`). Durations and slot counts are integers.
    case long(Int)
    /// A floating-point token (Java `Double`). Tempos, weights, swing ratios.
    case double(Double)
    /// A nested list.
    indirect case list(Polylist)

    // MARK: Convenience accessors

    /// The symbol text if this value is a `.symbol`, else `nil`.
    public var symbolValue: String? {
        if case let .symbol(s) = self { return s }
        return nil
    }

    /// The nested list if this value is a `.list`, else `nil`.
    public var listValue: Polylist? {
        if case let .list(l) = self { return l }
        return nil
    }

    /// Numeric value as an `Int`, coercing `.double` by truncation.
    /// Returns `nil` for symbols and lists.
    public var intValue: Int? {
        switch self {
        case let .long(v): return v
        case let .double(v): return Int(v)
        default: return nil
        }
    }

    /// Numeric value as a `Double`, promoting `.long`.
    /// Returns `nil` for symbols and lists.
    public var doubleValue: Double? {
        switch self {
        case let .long(v): return Double(v)
        case let .double(v): return v
        default: return nil
        }
    }

    /// True when this value is the empty list `()`.
    public var isEmptyList: Bool {
        if case let .list(l) = self { return l.isEmpty }
        return false
    }

    // MARK: CustomStringConvertible

    /// Renders the value the way the Java `toString` chain does, so round-trips
    /// and log output match the original engine's textual form.
    public var description: String {
        switch self {
        case let .symbol(s): return s
        case let .long(v): return String(v)
        case let .double(v): return PolyValue.formatDouble(v)
        case let .list(l): return l.description
        }
    }

    /// Formats a double the way Java's `Double.toString` does for the values that
    /// appear in these data files: whole numbers keep a trailing `.0`
    /// (`140.0`), fractions print without exponent (`0.67`).
    static func formatDouble(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 {
            return String(format: "%.1f", v)
        }
        // Swift's default description matches Java closely enough for the
        // fractional weights/ratios found in the data (e.g. 0.67, 10.0, 1.5).
        return String(v)
    }
}
